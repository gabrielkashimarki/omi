import GRDB
import OmiSupport
import XCTest

@testable import Omi_Computer

private final class OwnerDatabaseCommitObserver: TransactionObserver, @unchecked Sendable {
  private let releaseCommit = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var reachedWillCommit = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool { true }
  func databaseDidChange(with event: DatabaseEvent) {}

  func databaseWillCommit() throws {
    let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
      reachedWillCommit = true
      let pending = waiters
      waiters.removeAll()
      return pending
    }
    for continuation in pending { continuation.resume() }
    releaseCommit.wait()
  }

  func databaseDidCommit(_ db: Database) {}
  func databaseDidRollback(_ db: Database) {}

  func waitUntilWillCommit() async {
    if lock.withLock({ reachedWillCommit }) { return }
    await withCheckedContinuation { continuation in
      let shouldResume = lock.withLock { () -> Bool in
        guard !reachedWillCommit else { return true }
        waiters.append(continuation)
        return false
      }
      if shouldResume { continuation.resume() }
    }
  }

  func allowCommit() {
    releaseCommit.signal()
  }
}

#if compiler(>=6.4)
  private actor SiriMemoryWriteGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pauseBeforeWrite() async {
      entered = true
      enteredWaiter?.resume()
      enteredWaiter = nil
      await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
      if entered { return }
      await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
      releaseWaiter?.resume()
      releaseWaiter = nil
    }
  }

  private final class SiriMemoryIndexCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
  }
#endif

@MainActor
final class EffectiveOwnerDatabaseBoundaryTests: XCTestCase {
  private var originalAuthOwner: String?
  private var originalOverride: String?
  private var originalBackup: String?
  private var createdOwnerIDs: [String] = []

  #if compiler(>=6.4)
    func testSiriRememberDoesNotCacheOrIndexAfterOwnerSwitchDuringAwait() async throws {
      let ownerA = makeOwnerID("siri-memory-a")
      let ownerB = makeOwnerID("siri-memory-b")
      await setOwner(ownerA)
      let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
      let gate = SiriMemoryWriteGate()
      let indexCalls = SiriMemoryIndexCallCounter()
      let memory = ServerMemory(
        id: "siri-memory-owner-fence", content: "Only owner A may see this", category: .manual,
        tier: .longTerm, tierIsExplicit: true, createdAt: Date(), updatedAt: Date(),
        conversationId: nil, reviewed: false, userReview: nil, visibility: "private",
        manuallyAdded: true, scoring: nil, source: "siri", confidence: nil,
        sourceApp: nil, contextSummary: nil, isRead: false, isDismissed: false,
        isLocked: false, tags: ["siri"], reasoning: nil, currentActivity: nil,
        inputDeviceName: nil, windowTitle: nil, headline: nil)
      let write = Task {
        await SiriIntentService.confirmedMemoryResult(memory) {
          try await MemoryStorage.shared.syncServerMemory(
            memory, authorization: TasksStore.localMutationAuthorization(snapshot: snapshot),
            beforeLocalWrite: { await gate.pauseBeforeWrite() },
            onIndexChange: { _ in indexCalls.increment() })
        }
      }
      await gate.waitUntilEntered()
      await setOwner(ownerB)
      await gate.release()
      let confirmed = await write.value
      XCTAssertEqual(confirmed.id, memory.id, "The server already confirmed Remember")
      let ownerBMemory = try await MemoryStorage.shared.getMemoryByBackendId(memory.id)
      XCTAssertNil(ownerBMemory)
      await RewindDatabase.shared.close()
      XCTAssertEqual(try readMemoryBackendIDs(ownerID: ownerA), [])
      XCTAssertEqual(try readMemoryBackendIDs(ownerID: ownerB), [])
      XCTAssertEqual(indexCalls.count, 0)
    }
  #endif

  override func setUp() async throws {
    originalAuthOwner = UserDefaults.standard.string(forKey: .authUserId)
    originalOverride = UserDefaults.standard.string(forKey: .automationOwnerOverride)
    originalBackup = UserDefaults.standard.string(forKey: .automationOwnerABackup)
    try await RuntimeOwnerIdentity.performEffectiveOwnerTransition(
      allowAutomationOverride: true,
      plannedNextOwner: { _, _ in nil },
      { defaults in
        defaults.removeObject(forKey: .authUserId)
        defaults.removeObject(forKey: .automationOwnerOverride)
        defaults.removeObject(forKey: .automationOwnerABackup)
      })
    await RewindDatabase.shared.close()
  }

  override func tearDown() async throws {
    await RewindDatabase.shared.close()
    let authOwner = originalAuthOwner
    let override = originalOverride
    let backup = originalBackup
    try await RuntimeOwnerIdentity.performEffectiveOwnerTransition(
      allowAutomationOverride: true,
      plannedNextOwner: { _, _ in
        let normalizedOverride = override?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedOverride, !normalizedOverride.isEmpty { return normalizedOverride }
        return authOwner?.trimmingCharacters(in: .whitespacesAndNewlines)
      },
      { defaults in
        Self.restore(authOwner, forKey: .authUserId, in: defaults)
        Self.restore(override, forKey: .automationOwnerOverride, in: defaults)
        Self.restore(backup, forKey: .automationOwnerABackup, in: defaults)
      })
    for ownerID in createdOwnerIDs {
      try? FileManager.default.removeItem(at: userDirectory(ownerID))
    }
    createdOwnerIDs = []
  }


  private func setOwner(_ ownerID: String) async {
    do {
      try await RuntimeOwnerIdentity.performEffectiveOwnerTransition(
        allowAutomationOverride: false,
        plannedNextOwner: { _, _ in ownerID },
        { defaults in
          defaults.set(ownerID, forKey: .authUserId)
        })
    } catch {
      XCTFail("owner transition failed: \(error)")
    }
  }

  private func readProbeValues(ownerID: String) throws -> [String] {
    let pool = try DatabasePool(
      path: userDirectory(ownerID).appendingPathComponent("omi.db").path)
    return try pool.read { db in
      try String.fetchAll(db, sql: "SELECT value FROM owner_probe ORDER BY rowid")
    }
  }

  private func readMemoryBackendIDs(ownerID: String) throws -> [String] {
    let pool = try DatabasePool(path: userDirectory(ownerID).appendingPathComponent("omi.db").path)
    return try pool.read { db in
      try String.fetchAll(db, sql: "SELECT backendId FROM memories WHERE backendId IS NOT NULL")
    }
  }

  private func makeOwnerID(_ prefix: String) -> String {
    let ownerID = "\(prefix)-\(UUID().uuidString)"
    createdOwnerIDs.append(ownerID)
    return ownerID
  }

  private func userDirectory(_ ownerID: String) -> URL {
    DesktopLocalProfile.applicationSupportURL()
      .appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(ownerID, isDirectory: true)
  }

  nonisolated private static func restore(
    _ value: String?,
    forKey key: DefaultsKey,
    in defaults: UserDefaults
  ) {
    if let value {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  nonisolated private static func insertIndexedFile(path: String, in db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO indexed_files
          (path, filename, fileType, sizeBytes, folder, depth, indexedAt)
        VALUES (?, ?, 'document', 1, 'Documents', 0, ?)
        """,
      arguments: [path, URL(fileURLWithPath: path).lastPathComponent, Date()])
  }
}
