import AppKit
import CryptoKit
import Foundation
import Network
import OmiSupport
import OmiTheme

enum DesktopAutomationLaunchOptions {
  static let enableFlag = "--automation-bridge"
  static let portPrefix = "--automation-port="
  static let captureRootPrefix = "--automation-capture-root="
  static let uiPresentationPrefix = "--automation-ui="
  static let uiPresentationEnvironmentKey = "OMI_AUTOMATION_UI_MODE"
  static let defaultPort: UInt16 = 47777
  static let tokenEnvironmentKey = "OMI_AUTOMATION_TOKEN"
  static let tokenFileEnvironmentKey = "OMI_AUTOMATION_TOKEN_FILE"

  private static let generatedToken =
    "omi_auto_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"

  static var isEnabled: Bool {
    isEnabled(
      allowsLocalAutomation: AppBuild.allowsLocalAutomation,
      arguments: CommandLine.arguments,
      environment: ProcessInfo.processInfo.environment
    )
  }

  static func isEnabled(
    allowsLocalAutomation: Bool,
    arguments: [String],
    environment: [String: String]
  ) -> Bool {
    guard allowsLocalAutomation else {
      return false
    }
    // Explicit opt-out always wins, so a dev build can be run "clean" if needed.
    if environment["OMI_DISABLE_LOCAL_AUTOMATION"] == "1" {
      return false
    }
    // Auto-enable on local bundles (Omi Dev + every `omi-*` named test bundle) so agents
    // can drive the app without remembering a launch flag. Published previews are excluded
    // by `allowsLocalAutomation` above even if their process environment is contaminated.
    return arguments.contains(enableFlag)
      || environment["OMI_ENABLE_LOCAL_AUTOMATION"] == "1"
      || allowsLocalAutomation
  }

  static var port: UInt16 {
    for argument in CommandLine.arguments {
      guard argument.hasPrefix(portPrefix) else { continue }
      let rawValue = String(argument.dropFirst(portPrefix.count))
      if let parsed = UInt16(rawValue) {
        return parsed
      }
    }

    if let rawValue = ProcessInfo.processInfo.environment["OMI_AUTOMATION_PORT"],
      let parsed = UInt16(rawValue)
    {
      return parsed
    }

    return defaultPort
  }

  static var uiPresentationMode: DesktopAutomationUIPresentationMode {
    uiPresentationMode(
      allowsLocalAutomation: AppBuild.allowsLocalAutomation,
      arguments: CommandLine.arguments,
      environment: ProcessInfo.processInfo.environment)
  }

  static func uiPresentationMode(
    allowsLocalAutomation: Bool,
    arguments: [String],
    environment: [String: String]
  ) -> DesktopAutomationUIPresentationMode {
    guard allowsLocalAutomation else { return .normal }
    for argument in arguments where argument.hasPrefix(uiPresentationPrefix) {
      let rawValue = String(argument.dropFirst(uiPresentationPrefix.count)).lowercased()
      return DesktopAutomationUIPresentationMode(rawValue: rawValue) ?? .normal
    }
    let rawValue = environment[uiPresentationEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return rawValue.flatMap(DesktopAutomationUIPresentationMode.init(rawValue:)) ?? .normal
  }

  static var token: String {
    let env = ProcessInfo.processInfo.environment[tokenEnvironmentKey] ?? ""
    let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? generatedToken : trimmed
  }

  static var tokenFileURL: URL {
    if let rawValue = ProcessInfo.processInfo.environment[tokenFileEnvironmentKey],
      !rawValue.isEmpty
    {
      return URL(fileURLWithPath: rawValue).standardizedFileURL
    }
    return URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("omi-automation-\(port).token")
      .standardizedFileURL
  }

  static func writeTokenFileIfNeeded() {
    guard isEnabled else { return }
    let url = tokenFileURL
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try token.write(to: url, atomically: true, encoding: .utf8)
      chmod(url.path, S_IRUSR | S_IWUSR)
    } catch {
      logError("DesktopAutomationBridge: failed to write automation token file", error: error)
    }
  }

  static var captureRoot: URL {
    for argument in CommandLine.arguments {
      guard argument.hasPrefix(captureRootPrefix) else { continue }
      let rawValue = String(argument.dropFirst(captureRootPrefix.count))
      if !rawValue.isEmpty {
        return URL(fileURLWithPath: rawValue).standardizedFileURL
      }
    }

    if let rawValue = ProcessInfo.processInfo.environment["OMI_AUTOMATION_CAPTURE_ROOT"],
      !rawValue.isEmpty
    {
      return URL(fileURLWithPath: rawValue).standardizedFileURL
    }

    return URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("omi-harness", isDirectory: true)
      .standardizedFileURL
  }
}

struct DesktopAutomationSnapshot: Codable, Sendable {
  /// The app has one shell. Flows and the navigation-visibility policy still read
  /// `shellVariant`, so it is pinned here rather than removed from the contract.
  static let singleShellVariant = "chat_first"

  var bridgeEnabled: Bool
  var bridgePort: UInt16
  var bundleIdentifier: String
  var appState: String
  var selectedTab: String?
  var selectedTabIndex: Int?
  var selectedSettingsSection: String?
  var highlightedSettingId: String?
  /// Home stage mode: `hub`, `chat`, or `connect`. `DashboardPage` was the only view that ever
  /// rendered that stage and it no longer exists, so this is now always nil. Kept in the snapshot
  /// so an older flow reading it sees "no stage" rather than a missing key.
  var homeMode: String?
  /// Always `chat_first` on a mounted shell: the app has exactly one. Nil only before the shell has
  /// reported state. Never a local preference.
  var shellVariant: String?
  /// Stable typed route for the one shell.
  var chatFirstRoute: String?
  /// Set only by the mounted Chat-first destination after it has appeared. This
  /// keeps a successful navigation response equivalent to the target being
  /// visible, rather than merely accepted by the root reducer.
  var visibleChatFirstRoute: String?
  /// Shape-only focus telemetry for route acknowledgement; entity IDs stay local.
  var pendingFocusKind: String?
  var acknowledgedFocusKind: String?
  /// The focused entity is available only through the local non-production
  /// bridge so named-bundle probes can prove the acknowledgement target. It is
  /// never an analytics dimension or a persisted navigation value.
  var focusedEntityID: String?
  var isFocusedEntityAcknowledged: Bool
  /// Retained for snapshot compatibility; the legacy sidebar shell is gone, so it is always false.
  var showsPrimarySidebar: Bool
  var isSidebarCollapsed: Bool
  var hasCompletedOnboarding: Bool
  var isSignedIn: Bool
  /// Which account this bundle is actually signed into.
  ///
  /// `isSignedIn` alone cannot answer "is this the account I think it is", and
  /// a named bundle's identity is not stable across rebuilds: `run.sh` reseeds
  /// auth from a source bundle, so reinstalling a QA bundle can silently swap
  /// the signed-in account. On 2026-09-18 that turned a free-tier verification
  /// into a managed-path run against a different account, and nothing in the
  /// snapshot could have revealed it.
  ///
  /// The uid is the machine-checkable half — it is what rollout cohorts are
  /// keyed on, so a harness can assert the bundle is the account it configured.
  /// Non-production bundles only, like the rest of this bridge.
  var accountUserID: String?
  /// Human-readable half, for a developer reading `omi-ctl state` rather than
  /// asserting on it.
  var accountEmail: String?
  var isRestoringAuth: Bool
  var isAppActive: Bool
  var mainWindowTitle: String?
  var updatedAt: String
  /// True when the live MainActor refresh timed out and this is the last cached
  /// snapshot instead — e.g. the main thread is wedged on a blocking Keychain
  /// read during sign-in. The bridge still answers `/state` so harnesses don't
  /// hang; callers can detect that the live fields may be stale.
  var snapshotStale: Bool = false
}

struct DesktopAutomationOpenConversationRequest: Codable {
  let conversationId: String
  let showTranscript: Bool?
  let activateApp: Bool?
  let settleMs: Int?
}

struct DesktopAutomationVisualExportRequest: Codable {
  let path: String
  let target: String?
}

struct DesktopAutomationVisualExportResult: Codable {
  let path: String
  let width: Int
  let height: Int
}

struct DesktopAutomationExecuteExportRequest: Codable {
  let destination: String
}

struct DesktopAutomationOpenImportRequest: Codable {
  let connector: String
}

/// Describes a semantic action exposed over `GET /actions` so an agent can discover
/// what it can drive without inspecting the UI tree.
struct DesktopAutomationActionDescriptor: Codable {
  let name: String
  let summary: String
  /// Names of params the handler reads (hints for the caller; not enforced).
  let params: [String]
  /// Coarse grouping for scanners and harness UIs.
  let category: String
  /// Screens or app surfaces this action is meant to replace AX interaction on.
  let surfaces: [String]
  /// Explicit effect union, sorted for stable discovery JSON. Empty means read-only.
  let effects: [DesktopAutomationActionEffect]
  /// Derived coarse risk label for discovery clients.
  let safety: String
  /// Plain-language effects so callers can prefer read-only probes before clicks.
  let sideEffects: [String]
  /// Copy-pasteable examples for `scripts/omi-ctl action ...`.
  let examples: [String]
  /// Semantic bridge actions should be preferred over `agent-swift` clicks when covered.
  let preferSemantic: Bool

  init(
    name: String,
    effects: Set<DesktopAutomationActionEffect>,
    summary: String,
    params: [String] = [],
    category: String? = nil,
    surfaces: [String]? = nil,
    sideEffects: [String]? = nil,
    examples: [String] = [],
    preferSemantic: Bool = true
  ) {
    self.name = name
    self.summary = summary
    self.params = params
    let inferredCategory = Self.inferCategory(name)
    self.category = category ?? (effects.isEmpty ? "read" : (inferredCategory == "read" ? "write" : inferredCategory))
    self.surfaces = surfaces ?? Self.inferSurfaces(name)
    self.effects = effects.sorted { $0.rawValue < $1.rawValue }
    self.safety = DesktopAutomationActionEffect.safety(for: effects)
    self.sideEffects = self.effects.map(\.description) + (sideEffects ?? [])
    self.examples = examples.isEmpty ? [Self.commandExample(name: name, params: params)] : examples
    self.preferSemantic = preferSemantic
  }

  private static func inferCategory(_ name: String) -> String {
    if name.contains("snapshot") || name.contains("probe") || name.contains("state")
      || name.contains("tail") || name.contains("evidence") || name.contains("qa_export")
    {
      return "read"
    }
    if name.hasPrefix("capture") {
      return "capture"
    }
    if name.contains("coordinator") {
      return "coordinator"
    }
    if name.contains("ask") || name.contains("chat") || name.contains("omni") {
      return "chat"
    }
    if name.contains("spatial_overlay") || name.contains("debug_bar") || name.contains("subagent") {
      return "visual"
    }
    if name.contains("transcription") || name.contains("refresh") {
      return "app_control"
    }
    return "general"
  }

  private static func inferSurfaces(_ name: String) -> [String] {
    if name.hasPrefix("capture_main_window") {
      return ["main_window"]
    }
    if name.hasPrefix("capture_floating_bar") || name.contains("debug_bar") {
      return ["floating_bar"]
    }
    if name.contains("main_chat") {
      return ["main_chat"]
    }
    if name.contains("ask_omi") || name == "ask" || name.contains("floating") || name.contains("subagent") {
      return ["floating_bar", "ask_omi"]
    }
    if name.contains("coordinator") {
      return ["coordinator"]
    }
    if name.contains("spatial_overlay") || name.contains("cloud_connector") {
      return ["cloud_connector_guidance"]
    }
    if name.contains("calendar") {
      return ["calendar_connector"]
    }
    if name.contains("gmail") {
      return ["gmail_connector"]
    }
    if name.contains("apple_notes") || name.contains("local_file") {
      return ["import_connectors"]
    }
    return ["app"]
  }

  private static func commandExample(name: String, params: [String]) -> String {
    var pieces = ["./scripts/omi-ctl", "action", name]
    for param in params {
      pieces.append("\(param)=<value>")
    }
    return pieces.joined(separator: " ")
  }
}

/// Returned by `POST /action`: what ran, any handler detail, and the resulting state.
struct DesktopAutomationActionResult: Codable {
  let action: String
  let detail: [String: String]?
  let state: DesktopAutomationSnapshot
}

struct DesktopAutomationCapabilities: Codable {
  let schemaVersion: Int
  let routes: [String]
  let lanes: [String]
  let waits: [String]
  let assertions: [String]
  let artifactTypes: [String]
  let actions: [DesktopAutomationActionDescriptor]
}

struct DesktopAutomationRouteTrace: Codable {
  let method: String
  let path: String
  let statusCode: Int
  let durationMs: Double
  let finishedAt: String
}

enum DesktopAutomationActionError: LocalizedError {
  case unknownAction(String)
  case requiresEffects(String)
  case invalidParams(String)

  var errorDescription: String? {
    switch self {
    case .unknownAction(let name): return "unknown_action: \(name)"
    case .requiresEffects(let name): return "action_requires_effects: \(name)"
    case .invalidParams(let detail): return "invalid_params: \(detail)"
    }
  }
}

enum DesktopAutomationRevisionComparator {
  static func matchesAtMillisecondPrecision(_ lhs: Date?, _ rhs: Date?) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    let lhsMilliseconds = Int64((lhs.timeIntervalSince1970 * 1_000).rounded())
    let rhsMilliseconds = Int64((rhs.timeIntervalSince1970 * 1_000).rounded())
    return lhsMilliseconds == rhsMilliseconds
  }
}

private func automationSafeErrorDetail(_ raw: String) -> String {
  var detail = raw.replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
  let redactions: [(String, String)] = [
    (#"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, "[redacted-jwt]"),
    (#"(?i)bearer\s+[A-Za-z0-9._~+/=-]{8,}"#, "Bearer [redacted]"),
    (#"sk-[A-Za-z0-9_-]{20,}"#, "sk-[redacted]"),
  ]
  for (pattern, replacement) in redactions {
    detail = detail.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
  }
  return String(detail.prefix(500))
}

private func automationActionErrorDescription(_ error: Error) -> String {
  if case APIError.httpError(let statusCode, let detail) = error {
    let suffix = detail.map { " detail=\(automationSafeErrorDetail($0))" } ?? ""
    return "api_http_error status=\(statusCode)\(suffix)"
  }
  return automationSafeErrorDetail(error.localizedDescription)
}

private struct DesktopAutomationResponse<T: Codable>: Codable {
  let ok: Bool
  let result: T?
  let error: String?
}

final class DesktopAutomationStateStore {
  nonisolated(unsafe) static let shared = DesktopAutomationStateStore()
  private let lock = NSLock()

  private var snapshot = DesktopAutomationSnapshot(
    bridgeEnabled: DesktopAutomationLaunchOptions.isEnabled,
    bridgePort: DesktopAutomationLaunchOptions.port,
    bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
    appState: "launching",
    selectedTab: nil,
    selectedTabIndex: nil,
    selectedSettingsSection: nil,
    highlightedSettingId: nil,
    homeMode: nil,
    shellVariant: nil,
    chatFirstRoute: nil,
    visibleChatFirstRoute: nil,
    pendingFocusKind: nil,
    acknowledgedFocusKind: nil,
    focusedEntityID: nil,
    isFocusedEntityAcknowledged: false,
    showsPrimarySidebar: false,
    isSidebarCollapsed: true,
    hasCompletedOnboarding: false,
    isSignedIn: false,
    accountUserID: nil,
    accountEmail: nil,
    isRestoringAuth: true,
    isAppActive: false,
    mainWindowTitle: nil,
    updatedAt: ISO8601DateFormatter().string(from: Date())
  )

  func update(_ snapshot: DesktopAutomationSnapshot) {
    lock.lock()
    defer { lock.unlock() }
    self.snapshot = snapshot
  }

  func updateLiveFields(_ update: (inout DesktopAutomationSnapshot) -> Void) -> DesktopAutomationSnapshot {
    lock.lock()
    defer { lock.unlock() }
    update(&snapshot)
    return snapshot
  }

  func current() -> DesktopAutomationSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return snapshot
  }
}

/// How long `/state` waits for the live MainActor refresh before serving the last
/// cached snapshot instead. Generous enough not to false-trip under normal load,
/// small enough that a wedged main thread can't stall the harness.
private let liveSnapshotMainActorTimeout: Duration = .seconds(3)

/// Single-resume guard for a continuation raced between two unstructured tasks.
private final class TimeoutRaceBox<T>: @unchecked Sendable {
  private var resumed = false
  private let lock = NSLock()
  private let continuation: CheckedContinuation<T?, Never>

  init(_ continuation: CheckedContinuation<T?, Never>) {
    self.continuation = continuation
  }

  func resume(_ value: sending T?) {
    lock.lock()
    defer { lock.unlock() }
    guard !resumed else { return }
    resumed = true
    continuation.resume(returning: value)
  }
}

/// Await `operation`, but give up after `timeout` and return `nil`.
///
/// The automation bridge uses this so a wedged MainActor — e.g. a blocking
/// Keychain read on the main thread during sign-in (`AuthService.storedIdToken`
/// → `SecItemCopyMatching`) — can't hang `/state`. Crucially the operation runs
/// in an *unstructured* task, not a `withTaskGroup` child: a task group awaits all
/// children at scope exit, so a non-cancellable wedged `MainActor.run` would hang
/// the timeout itself. Here we resume on whichever finishes first and leave the
/// abandoned operation task to complete (harmlessly) on its own later. Pure and
/// self-contained, so it is hermetically testable.
func awaitWithTimeout<T: Sendable>(
  _ timeout: Duration,
  operation: @escaping @Sendable () async -> T
) async -> T? {
  await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
    let box = TimeoutRaceBox<T>(continuation)
    let operationTask = Task { box.resume(await operation()) }
    Task {
      try? await Task.sleep(for: timeout)
      box.resume(nil)
      operationTask.cancel()
    }
  }
}

func liveAutomationSnapshot() async -> DesktopAutomationSnapshot {
  // Bound the MainActor hop: if the main thread is wedged (blocking Keychain read
  // during sign-in), fall back to the last cached snapshot so `/state` still
  // answers instead of hanging the whole bridge. See awaitWithTimeout.
  guard let live = await awaitWithTimeout(liveSnapshotMainActorTimeout, operation: liveAutomationSnapshotFromMainActor)
  else {
    log("DesktopAutomationBridge: live /state refresh timed out (main thread busy); serving cached snapshot")
    var stale = await cachedAutomationSnapshot()
    stale.snapshotStale = true
    return stale
  }
  return live
}

@Sendable
private func liveAutomationSnapshotFromMainActor() async -> DesktopAutomationSnapshot {
  let isAppActive = await MainActor.run { NSApp.isActive }
  return DesktopAutomationStateStore.shared.updateLiveFields { snapshot in
    snapshot.isAppActive = isAppActive
    snapshot.updatedAt = ISO8601DateFormatter().string(from: Date())
    snapshot.snapshotStale = false
  }
}

func cachedAutomationSnapshot() async -> DesktopAutomationSnapshot {
  var snapshot = DesktopAutomationStateStore.shared.current()
  snapshot.updatedAt = ISO8601DateFormatter().string(from: Date())
  return snapshot
}

actor DesktopAutomationTraceStore {
  static let shared = DesktopAutomationTraceStore()

  private var traces: [DesktopAutomationRouteTrace] = []
  private let formatter = ISO8601DateFormatter()

  func record(method: String, path: String, statusCode: Int, durationMs: Double) {
    traces.append(
      DesktopAutomationRouteTrace(
        method: method,
        path: path,
        statusCode: statusCode,
        durationMs: durationMs,
        finishedAt: formatter.string(from: Date())
      )
    )
    if traces.count > 200 {
      traces.removeFirst(traces.count - 200)
    }
  }

  func recent(limit: Int = 50) -> [DesktopAutomationRouteTrace] {
    Array(traces.suffix(max(1, min(limit, 200))))
  }

  func clear() {
    traces.removeAll(keepingCapacity: true)
  }
}

/// In-process registry of semantic, cursor-free actions the automation bridge can
/// run. Handlers invoke the app's real code (notifications, services) directly, so
/// no synthetic mouse events are ever generated — this is the deterministic
/// "command channel" equivalent of the Flutter app's Marionette driver.
///
/// Built-ins are registered at bridge startup. Feature code can register more via
/// `register(name:effects:summary:params:handler:)` (e.g. from a view model's lifecycle) and
/// remove them with `unregister(_:)`.
@MainActor
private func ensureConversationsTabVisibleForAutomation() async throws {
  NotificationCenter.default.post(
    name: .navigateToSidebarItem,
    object: nil,
    userInfo: ["rawValue": SidebarNavItem.conversations.rawValue]
  )
  // Propagate cancellation instead of swallowing it with try? — if the
  // automation task is cancelled during the settle sleep, the caller should
  // not continue to post further notifications.
  try await Task.sleep(nanoseconds: 150_000_000)
}

private func requestAutomationConversationOpen(conversationId: String, showTranscript: Bool) async {
  await MainActor.run {
    ConversationDetailAutomationState.shared.requestOpen(
      conversationId: conversationId,
      showTranscript: showTranscript
    )
    NotificationCenter.default.post(name: .desktopAutomationOpenConversationRequested, object: nil)
  }
}

@MainActor
final class DesktopAutomationActionRegistry {
  static let shared = DesktopAutomationActionRegistry()

  /// Handler runs on the main actor and returns optional string detail for the caller.
  typealias Handler = (_ params: [String: String]) async throws -> [String: String]?

  private struct Entry {
    let descriptor: DesktopAutomationActionDescriptor
    let run: Handler
  }

  /// A 1x1 PNG, for the hermetic half of `screen_frame_quick_look_probe`. Literal bytes rather
  /// than a rendered image so the probe has no dependency on capture history, a backend, or AppKit
  /// drawing — the thing it is verifying is the panel, not the picture.
  static let onePixelPNGBase64 =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

  private var entries: [String: Entry] = [:]
  private var didRegisterBuiltins = false
  /// Non-prod harness latch so race probes stay busy without relying on LLM latency.
  private var harnessBusyUntil: Date?

  private func harnessBusyLatchActive(now: Date = Date()) -> Bool {
    guard let until = harnessBusyUntil else { return false }
    if now >= until {
      harnessBusyUntil = nil
      return false
    }
    return true
  }

  private func clearHarnessBusyLatch() {
    harnessBusyUntil = nil
  }

  private func armHarnessBusyLatch(holdBusyMs: Int) {
    let ms = max(0, holdBusyMs)
    guard ms > 0 else { return }
    harnessBusyUntil = Date().addingTimeInterval(Double(ms) / 1000.0)
  }

  func register(
    name: String,
    effects: Set<DesktopAutomationActionEffect>,
    summary: String,
    params: [String] = [],
    category: String? = nil,
    surfaces: [String]? = nil,
    sideEffects: [String]? = nil,
    examples: [String] = [],
    preferSemantic: Bool = true,
    handler: @escaping Handler
  ) {
    entries[name] = Entry(
      descriptor: DesktopAutomationActionDescriptor(
        name: name,
        effects: effects,
        summary: summary,
        params: params,
        category: category,
        surfaces: surfaces,
        sideEffects: sideEffects,
        examples: examples,
        preferSemantic: preferSemantic
      ),
      run: handler)
  }

  func unregister(_ name: String) { entries[name] = nil }

  func descriptors() -> [DesktopAutomationActionDescriptor] {
    entries.values.map(\.descriptor).sorted { $0.name < $1.name }
  }

  func perform(
    _ name: String, params: [String: String], readOnly: Bool = false
  ) async throws -> [String: String]? {
    guard let entry = entries[name] else {
      throw DesktopAutomationActionError.unknownAction(name)
    }
    // Check before invoking the handler, including handlers that launch Tasks.
    guard !readOnly || entry.descriptor.effects.isEmpty else {
      throw DesktopAutomationActionError.requiresEffects(name)
    }
    return try await entry.run(params)
  }

  /// Register the always-available actions that don't need any view's `@State` —
  /// they post the same notifications / hit the same services as the real controls,
  /// so they exercise the genuine code paths. Idempotent.
  func registerBuiltins() {
    guard !didRegisterBuiltins else { return }
    didRegisterBuiltins = true
    registerProactiveCaptureStatusSnapshot()
    register(
      name: "set_automation_ui_presentation",
      effects: [.localState],
      summary:
        "Park automation windows quietly, reveal them briefly for Accessibility, or restore normal user presentation",
      params: ["mode", "activate"],
      category: "app_control",
      surfaces: ["app"],
      sideEffects: ["changes non-production window placement and input handling"],
      examples: [
        "./scripts/omi-ctl ui quiet",
        "./scripts/omi-ctl ui interactive --activate",
        "./scripts/omi-ctl ui normal --activate",
      ]
    ) { params in
      // This registry is reachable only through DesktopAutomationBridge, whose listener cannot start
      // for production-family or published-preview bundles. Keep the handler itself exercisable in a
      // hermetic test instead of duplicating the bridge's stronger process boundary here.
      guard let requested = params["mode"]?.lowercased() else {
        return [
          "mode": DesktopAutomationWindowPresentation.currentMode.rawValue,
          "available_modes": DesktopAutomationUIPresentationMode.allCases.map(\.rawValue).joined(
            separator: ","),
        ]
      }
      guard let mode = DesktopAutomationUIPresentationMode(rawValue: requested) else {
        throw DesktopAutomationActionError.invalidParams(
          "mode must be normal, quiet, or interactive")
      }
      let activate = boolParam(params["activate"], default: false)
      let previous = DesktopAutomationWindowPresentation.setMode(mode, activate: activate)
      return [
        "previous_mode": previous.rawValue,
        "mode": DesktopAutomationWindowPresentation.currentMode.rawValue,
        "activated": activate ? "true" : "false",
      ]
    }
    registerActivationActions()
    registerItemLinkActions()
    registerConversationRecordingActions()
    registerCaptureRecoveryActions()
    register(
      name: "refresh_all_data",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Refresh conversations, chat, tasks, and memories (same as Cmd+R)"
    ) { _ in
      NotificationCenter.default.post(name: .refreshAllData, object: nil)
      return nil
    }

    // Posts a real keyDown+keyUp pair through the app's own event queue, so local
    // NSEvent monitors and SwiftUI key equivalents see it exactly like a physical
    // keypress — lets a headless harness drive keyboard navigation without
    // Accessibility permission or a frontmost window. Non-prod only.
    register(
      name: "post_key",
      effects: [.localState, .localArtifact, .networkOrModel, .remoteWrite],
      summary:
        "Post a keyDown+keyUp NSEvent through the app event queue (e.g. key_code=124 for right arrow). Non-prod only.",
      params: ["key_code", "modifiers"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "post_key is disabled on production bundles"]
      }
      guard let codeText = params["key_code"], let keyCode = UInt16(codeText) else {
        throw DesktopAutomationActionError.invalidParams("key_code must be a numeric macOS key code")
      }
      var modifiers: NSEvent.ModifierFlags = []
      for token in (params["modifiers"] ?? "").split(separator: ",") {
        switch token.trimmingCharacters(in: .whitespaces).lowercased() {
        case "command", "cmd": modifiers.insert(.command)
        case "shift": modifiers.insert(.shift)
        case "option", "alt": modifiers.insert(.option)
        case "control", "ctrl": modifiers.insert(.control)
        case "function", "fn": modifiers.insert(.function)
        case "": break
        default:
          throw DesktopAutomationActionError.invalidParams("unknown modifier '\(token)'")
        }
      }
      // Arrow keys carry their function-key character and the flags a physical
      // press would have, so consumers that look at characters/flags match too.
      let arrowCharacters: [UInt16: String] = [
        123: "\u{F702}", 124: "\u{F703}", 125: "\u{F701}", 126: "\u{F700}",
      ]
      let characters = arrowCharacters[keyCode] ?? ""
      if arrowCharacters[keyCode] != nil {
        modifiers.formUnion([.function, .numericPad])
      }
      let window = NSApp.keyWindow ?? NSApp.mainWindow
      var posted = 0
      for phase in [NSEvent.EventType.keyDown, .keyUp] {
        if let event = NSEvent.keyEvent(
          with: phase, location: .zero, modifierFlags: modifiers,
          timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window?.windowNumber ?? 0, context: nil,
          characters: characters, charactersIgnoringModifiers: characters,
          isARepeat: false, keyCode: keyCode)
        {
          NSApp.postEvent(event, atStart: false)
          posted += 1
        }
      }
      return [
        "posted_events": "\(posted)",
        "key_code": "\(keyCode)",
        "window": window.map { $0.title.isEmpty ? "untitled" : $0.title } ?? "none",
      ]
    }

    register(
      name: "task_capture_fixture",
      effects: [],
      summary: "Evaluate canonical screen-capture policy facts without screenshot bytes",
      params: ["facts_json"]
    ) { params in
      guard let json = params["facts_json"], let data = json.data(using: .utf8) else {
        throw DesktopAutomationActionError.invalidParams("facts_json must be canonical capture facts JSON")
      }
      guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw DesktopAutomationActionError.invalidParams("facts_json must be a JSON object")
      }
      func value<T>(_ camel: String, _ snake: String, default fallback: T) -> T {
        payload[camel] as? T ?? payload[snake] as? T ?? fallback
      }
      let facts = ScreenCaptureFacts(
        explicitCommand: value("explicitCommand", "explicit_command", default: false),
        clearCommitment: value("clearCommitment", "clear_commitment", default: false),
        concreteDeliverable: value("concreteDeliverable", "concrete_deliverable", default: false),
        directRequest: value("directRequest", "direct_request", default: false),
        inferredNextStep: value("inferredNextStep", "inferred_next_step", default: false),
        owner: value("owner", "owner", default: "unknown"),
        publicBroadcast: value("publicBroadcast", "public_broadcast", default: false),
        directMention: value("directMention", "direct_mention", default: false),
        alreadyDone: value("alreadyDone", "already_done", default: false),
        duplicateOf: payload["duplicateOf"] as? String ?? payload["duplicate_of"] as? String,
        refinesTask: payload["refinesTask"] as? String ?? payload["refines_task"] as? String,
        captureConfidence: value("captureConfidence", "capture_confidence", default: 0.5),
        ownershipConfidence: value("ownershipConfidence", "ownership_confidence", default: 0.5)
      )
      return ["outcome": ScreenCapturePolicy.evaluate(facts).rawValue]
    }

    register(
      name: "configure_contextual_task_interruptions",
      effects: [.localState],
      summary: "Configure the non-production contextual task interruption gate",
      params: [
        "enabled", "daily_limit", "minimum_spacing_seconds",
        "notifications_enabled", "frequency", "task_notifications_enabled",
      ]
    ) { params in
      var configuration = ProactiveTaskInterruptionSettings.load()
      configuration.userOptedIn = boolParam(params["enabled"], default: false)
      configuration.dailyLimit = max(0, intParam(params["daily_limit"], default: configuration.dailyLimit))
      configuration.minimumSpacing = TimeInterval(
        max(
          0, intParam(params["minimum_spacing_seconds"], default: Int(configuration.minimumSpacing))))
      ProactiveTaskInterruptionSettings.save(configuration)
      if params["notifications_enabled"] != nil {
        UserDefaults.standard.set(
          boolParam(params["notifications_enabled"], default: false),
          forKey: NotificationService.masterEnabledDefaultsKey
        )
      }
      if params["frequency"] != nil {
        UserDefaults.standard.set(
          max(0, min(5, intParam(params["frequency"], default: 0))),
          forKey: NotificationService.frequencyDefaultsKey
        )
      }
      if params["task_notifications_enabled"] != nil {
        TaskAssistantSettings.shared.notificationsEnabled = boolParam(
          params["task_notifications_enabled"], default: false)
      }
      return [
        "enabled": configuration.userOptedIn ? "true" : "false",
        "cohort": ProactiveTaskCohort.current.rawValue,
      ]
    }

    register(
      name: "probe_contextual_task_interruption",
      effects: [.localState],
      summary: "Evaluate a synthetic bounded recommendation through the real interruption gate",
      params: ["can_wait", "expires_in_seconds"]
    ) { params in
      guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
        return ["error": "runtime_owner_unavailable"]
      }
      let nonce = UUID().uuidString.lowercased()
      let trace = NotificationService.shared.sendContextualTaskInterruption(
        TaskInterruptionCandidate(
          recommendationID: "automation:\(nonce)",
          interventionID: "automation-intervention:\(nonce)",
          dedupeKey: "automation-dedupe:\(nonce)",
          headline: "Review a relevant update",
          whyNow: "The linked context changed materially.",
          recommendedAction: "Review update",
          expiresAt: Date().addingTimeInterval(
            TimeInterval(
              intParam(params["expires_in_seconds"], default: 300))),
          canWait: boolParam(params["can_wait"], default: false)
        ),
        authorizationSnapshot: authorizationSnapshot
      )
      return [
        "reason": trace.reason.rawValue,
        "cohort": trace.cohort.rawValue,
        "dedupe_hash": trace.dedupeHash,
        "intervention_id": trace.interventionID,
      ]
    }

    register(
      name: "probe_suggestion_nudge",
      effects: [.localState, .networkOrModel],
      summary: "Run the real suggestion grounding/evaluation/delivery path on the latest frame",
      params: ["app", "window_title"],
      sideEffects: [
        "may call model/backend services",
        "may deliver a user-visible suggestion when notification controls allow",
      ]
    ) { params in
      let app = params["app"].flatMap { $0.isEmpty ? nil : $0 }
      let title = params["window_title"].flatMap { $0.isEmpty ? nil : $0 }
      return await ProactiveAssistantsPlugin.shared.probeSuggestionNudge(
        appOverride: app,
        windowTitleOverride: title
      )
    }

    register(
      name: "set_contextual_task_focus",
      effects: [.localState],
      summary: "Set deterministic focus suppression for contextual task interruptions",
      params: ["suppressed"]
    ) { params in
      let suppressed = boolParam(params["suppressed"], default: true)
      UserDefaults.standard.set(
        suppressed, forKey: ProactiveTaskInterruptionSettings.focusSuppressedKey)
      return ["suppressed": suppressed ? "true" : "false"]
    }

    register(
      name: "observe_task_context",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Submit a normalized task-context event and optionally flush re-evaluation",
      params: [
        "kind", "reference", "subject_kind", "subject_id", "workstream_id", "urgency", "flush",
      ]
    ) { params in
      guard let kind = TaskContextEventKind(rawValue: params["kind"] ?? "app_window") else {
        throw DesktopAutomationActionError.invalidParams("kind is invalid")
      }
      guard let reference = params["reference"], !reference.isEmpty else {
        throw DesktopAutomationActionError.invalidParams("reference is required")
      }
      let subject: TaskContextSubject?
      if let subjectID = params["subject_id"], !subjectID.isEmpty,
        let kind = OmiAPI.RecommendationSubjectKind(rawValue: params["subject_kind"] ?? "task")
      {
        subject = TaskContextSubject(
          kind: kind,
          id: subjectID,
          workstreamID: params["workstream_id"]?.isEmpty == false ? params["workstream_id"] : nil
        )
      } else {
        subject = nil
      }
      guard
        let event = TaskLocalContextEvent.normalized(
          kind: kind,
          rawReference: reference,
          subject: subject,
          urgency: TaskContextUrgency(rawValue: params["urgency"] ?? "can_wait") ?? .canWait
        )
      else {
        throw DesktopAutomationActionError.invalidParams("context event could not be normalized")
      }
      let matched = await ContextSubjectBindingService.shared.resolve(event)
      let referenceHash = matched.referenceHash
      await TaskContextualResurfacingService.shared.observe(matched)
      let shouldFlush = boolParam(params["flush"], default: true)
      if shouldFlush { await TaskContextualResurfacingService.shared.flush() }
      return [
        "reference_hash": referenceHash,
        "pending_workstreams": "\(await TaskContextualResurfacingService.shared.pendingWorkstreamCount())",
        "flushed": shouldFlush ? "true" : "false",
      ]
    }


    // Runs the exact service + outcome mapping the ChatGPT/Claude import
    // sheets use, so harnesses can assert outcome copy without driving the
    // TextEditor. Writes real memories on success, like the sheet would.
    register(
      name: "memory_log_import_probe",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary:
        "Import a ChatGPT/Claude memory-log text through the real connector pipeline and return the outcome message",
      params: ["source", "text", "fixture"],
      category: "write",
      surfaces: ["import_connectors"],
      sideEffects: [
        "may call model/backend services",
        "may save imported memory data",
      ]
    ) { params in
      guard let raw = params["source"], let source = OnboardingMemoryLogSource(rawValue: raw) else {
        throw DesktopAutomationActionError.invalidParams("source must be chatgpt or claude")
      }
      guard let text = params["text"], !text.isEmpty else {
        throw DesktopAutomationActionError.invalidParams("text must be non-empty")
      }
      let outcome: ConnectorImportOperations.Outcome
      if params["fixture"] == "structured" {
        guard AppBuild.isNonProduction else {
          return ["error": "structured memory-log fixture is disabled on production bundles"]
        }
        // Offline providers intentionally return a marker echo rather than JSON.
        // Inject only the extracted provider result; the real connector operation
        // still owns validation, durable save, and user-facing outcome mapping.
        outcome = await ConnectorImportOperations.importMemoryLog(
          text: text,
          source: source,
          extractedFixture: OnboardingMemoryLogImportService.ExtractedMemoryLog(
            memories: [text],
            profileSummary: "desktop qualification fixture"
          )
        )
      } else {
        outcome = await ConnectorImportOperations.importMemoryLog(text: text, source: source)
      }
      switch outcome {
      case .success(let result, let message):
        return [
          "outcome": "success",
          "message": message,
          "memories": "\(result.memoryCount ?? 0)",
        ]
      case .failure(let message, failureClass: _):
        return ["outcome": "failure", "message": message]
      }
    }

    register(
      name: "toggle_transcription",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Enable or disable live transcription (mirrors the menu-bar toggle)",
      params: ["enabled"]
    ) { params in
      let enabled = boolParam(params["enabled"], default: true)
      AssistantSettings.shared.audioRecordingMode = enabled ? .onlyMeetings : .off
      return ["enabled": enabled ? "true" : "false"]
    }

    register(
      name: "capture_test_transcript",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Hermetic capture seam: start/inject/stop a test recording session without mic/STT",
      params: ["phase", "text", "segments"]
    ) { params in
      guard let appState = AppState.current else { return ["error": "app state unavailable"] }
      let phase = (params["phase"] ?? "inject").lowercased()
      switch phase {
      case "start":
        return await appState.automationStartCaptureTestSession()
      case "inject":
        return await appState.automationInjectCaptureTestTranscript(text: params["text"] ?? "")
      case "inject_multi":
        return await appState.automationInjectCaptureTestTranscriptMulti(
          segmentsJSON: params["segments"] ?? params["text"] ?? "")
      case "meeting_start", "meeting_end":
        return ["conversation_role": appState.automationObserveMeetingBoundary(active: phase == "meeting_start")]
      case "stop":
        return await appState.automationStopCaptureTestSession()
      case "lifecycle":
        let marker = params["text"] ?? "[[MARKER:capture-lifecycle]]"
        let startResult = await appState.automationStartCaptureTestSession()
        if startResult["error"] != nil {
          return startResult
        }
        _ = await appState.automationInjectCaptureTestTranscript(text: marker)
        return await appState.automationStopCaptureTestSession()
      default:
        return ["error": "phase must be start, inject, inject_multi, meeting_start, meeting_end, stop, or lifecycle"]
      }
    }

    register(
      name: "local_summary_benchmark",
      effects: [.localArtifact, .networkOrModel],
      summary:
        "S12: run the local summarizer over the last K GRDB sessions and write schema-validity + timings JSON",
      params: ["limit", "engine", "output"],
      category: "debug",
      surfaces: ["app"],
      sideEffects: ["writes a JSON report under Application Support; does not persist projections"],
      examples: [
        "./scripts/omi-ctl action local_summary_benchmark limit=5 engine=local-server"
      ]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "local_summary_benchmark is disabled on production bundles"]
      }
      let limit = max(1, min(LocalSummaryBenchmark.maxSessions, intParam(params["limit"], default: 5)))
      let engineRaw = (params["engine"] ?? "local-server").trimmingCharacters(in: .whitespacesAndNewlines)
      guard let engineID = LocalInferenceEngineID.parse(engineRaw) else {
        throw DesktopAutomationActionError.invalidParams("engine must be local-server or afm")
      }
      guard let queue = await RewindDatabase.shared.getDatabaseQueue() else {
        return ["error": "rewind database unavailable"]
      }
      let sessions: [LocalSummaryBenchmark.Session]
      do {
        sessions = try await queue.read { db in
          try LocalSummaryBenchmark.loadRecentSessions(from: db, limit: limit)
        }
      } catch {
        return ["error": "session_load_failed"]
      }
      guard !sessions.isEmpty else {
        return ["error": "no_sessions", "limit": "\(limit)"]
      }
      let runtime = LocalInferenceRuntime.makeDefault(
        killSwitches: LocalInferenceKillSwitches(isDisabled: false, forcedEngineRaw: engineID.rawValue)
      )
      let summarizer = ConversationChunkSummarizer(
        runtime: runtime,
        store: MemoryLocalProjectionStore()
      )
      let report = await LocalSummaryBenchmark.run(
        sessions: sessions,
        summarizer: summarizer,
        engineID: engineID.rawValue
      )
      let output: URL
      if let raw = params["output"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
        output = URL(fileURLWithPath: raw)
      } else {
        output = LocalSummaryBenchmark.defaultReportURL()
      }
      do {
        try LocalSummaryBenchmark.write(report, to: output)
      } catch {
        return ["error": "report_write_failed"]
      }
      let valid = report.cases.filter(\.schemaValid).count
      return [
        "path": output.path,
        "engine": engineID.rawValue,
        "case_count": "\(report.cases.count)",
        "schema_valid_count": "\(valid)",
        "kind": report.kind,
      ]
    }


    register(
      name: "local_embedding_benchmark",
      effects: [.localArtifact],
      summary: "Run synthetic local hybrid retrieval metrics (recall@10 / nDCG@10) and write JSON",
      params: ["output"],
      category: "debug",
      surfaces: ["app"],
      sideEffects: ["writes a JSON report under Application Support; uses an in-memory synthetic DB"],
      examples: ["./scripts/omi-ctl action local_embedding_benchmark"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "local_embedding_benchmark is disabled on production bundles"]
      }
      let runtime = LocalEmbeddingRuntime.makeDefault()
      guard case .engine(let engine) = await runtime.selectEngine() else {
        return [
          "kind": LocalEmbeddingBenchmark.reportKind,
          "error": "local_engine_unavailable",
        ]
      }
      let report: LocalEmbeddingBenchmark.Report
      do {
        report = try await LocalEmbeddingBenchmark.runSynthetic(engine: engine, runtime: runtime)
      } catch {
        return [
          "kind": LocalEmbeddingBenchmark.reportKind,
          "error": "benchmark_failed",
        ]
      }
      let output: URL
      if let raw = params["output"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
        output = URL(fileURLWithPath: raw)
      } else {
        output = LocalEmbeddingBenchmark.defaultReportURL()
      }
      do {
        try LocalEmbeddingBenchmark.write(report, to: output)
      } catch {
        return ["error": "report_write_failed"]
      }
      return [
        "path": output.path,
        "engine": engine.engineID,
        "kind": report.kind,
        "fixture": report.fixture,
        "metric_count": "\(report.metrics.count)",
      ]
    }

    register(
      name: "conversation_list_snapshot",
      effects: [.localState, .networkOrModel],
      summary: "Return conversation list counts and recent titles for harness assertions",
      params: ["limit"]
    ) { params in
      guard let appState = AppState.current else { return ["error": "app state unavailable"] }
      let limit = max(1, intParam(params["limit"], default: 5))
      let titles = appState.conversations.prefix(limit).map { $0.structured.title }
      let ids = appState.conversations.prefix(limit).map { $0.id }
      let titlesJSON: String
      let idsJSON: String
      if let data = try? JSONSerialization.data(withJSONObject: Array(titles)),
        let encoded = String(data: data, encoding: .utf8)
      {
        titlesJSON = encoded
      } else {
        titlesJSON = "[]"
      }
      if let data = try? JSONSerialization.data(withJSONObject: Array(ids)),
        let encoded = String(data: data, encoding: .utf8)
      {
        idsJSON = encoded
      } else {
        idsJSON = "[]"
      }
      let starredCount = appState.conversations.filter(\.starred).count
      if appState.folders.isEmpty {
        await appState.loadFolders()
      }
      return [
        "conversation_count": "\(appState.totalConversationsCount ?? appState.conversations.count)",
        "loaded_count": "\(appState.conversations.count)",
        "is_transcribing": appState.isTranscribing ? "true" : "false",
        "recent_titles_json": titlesJSON,
        "recent_ids_json": idsJSON,
        "folder_count": "\(appState.folders.count)",
        "starred_count": "\(starredCount)",
        "active_folder_id": appState.selectedFolderId ?? "none",
        "show_starred_only": appState.showStarredOnly ? "true" : "false",
      ]
    }

    register(
      name: "conversation_reconciliation_snapshot",
      effects: [.localState, .networkOrModel],
      summary: "Exercise cache-first list/detail reconciliation and open the canonical detail",
      params: []
    ) { _ in
      guard let appState = AppState.current else { return ["error": "app state unavailable"] }
      await appState.loadConversations()
      guard let seed = appState.conversations.first else {
        return ["error": "no conversation available for reconciliation"]
      }

      var cachedProjectionId: String?
      let detail = await appState.loadConversationDetail(seed) { cached in
        cachedProjectionId = cached.id
      }
      let persisted = try? await TranscriptionStorage.shared.getCachedConversation(id: detail.id)

      await requestAutomationConversationOpen(conversationId: detail.id, showTranscript: true)

      return [
        "list_loaded": appState.conversations.isEmpty ? "false" : "true",
        "cached_projection_seen": cachedProjectionId == seed.id ? "true" : "false",
        "detail_id_matches": detail.id == seed.id ? "true" : "false",
        "detail_has_revision": detail.updatedAt == nil ? "false" : "true",
        "detail_transcript_included": detail.transcriptSegmentsIncluded ? "true" : "false",
        "cache_id_matches": persisted?.id == detail.id ? "true" : "false",
        "cache_revision_matches": DesktopAutomationRevisionComparator.matchesAtMillisecondPrecision(
          persisted?.updatedAt, detail.updatedAt)
          ? "true" : "false",
        "opened_detail": "true",
      ]
    }

    register(
      name: "memories_snapshot",
      effects: [.localState, .networkOrModel],
      summary: "Return memories page load state for harness assertions",
      params: []
    ) { _ in
      guard AuthState.shared.isSignedIn else {
        return [
          "is_signed_in": "false",
          "load_state": "signed_out",
          "memory_count_valid": "false",
        ]
      }
      do {
        // Same local-first path MemoriesViewModel.loadMemories uses: API page → SQLite sync → count.
        let page = try await APIClient.shared.getMemoriesPage(limit: 100, offset: 0)
        try await MemoryStorage.shared.syncServerMemories(page.memories)
        let memoryCount = try await MemoryStorage.shared.getLocalMemoriesCount()
        return [
          "is_signed_in": "true",
          "load_state": "loaded",
          "memory_count": "\(memoryCount)",
          "api_page_count": "\(page.memories.count)",
          "memory_count_valid": "true",
          "has_error": "false",
        ]
      } catch {
        return [
          "is_signed_in": "true",
          "load_state": "error",
          "has_error": "true",
          "memory_count_valid": "false",
          "error_message": error.localizedDescription,
        ]
      }
    }

    register(
      name: "tasks_snapshot",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Return tasks store counts for harness assertions",
      params: []
    ) { _ in
      guard AuthState.shared.isSignedIn else {
        return [
          "is_signed_in": "false",
          "load_state": "signed_out",
          "task_count_valid": "false",
        ]
      }
      let store = TasksStore.shared
      await store.loadTasksIfNeeded()
      let deadline = Date().addingTimeInterval(30)
      while store.isLoading, Date() < deadline {
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      let total = store.tasksWithoutDueDate.count + store.overdueTasks.count + store.todaysTasks.count
      let loadState: String
      if store.error != nil {
        loadState = "error"
      } else if store.isLoading {
        loadState = "loading"
      } else {
        loadState = "loaded"
      }
      return [
        "is_signed_in": "true",
        "load_state": loadState,
        "task_count": "\(total)",
        "overdue_count": "\(store.overdueTasks.count)",
        "today_count": "\(store.todaysTasks.count)",
        "task_count_valid": loadState == "loaded" ? "true" : "false",
        "has_error": store.error != nil ? "true" : "false",
      ]
    }









    // Same code path as the status-menu "Reset Onboarding..." item and the
    // Settings "Reset & Restart" button — clears onboarding state and restarts
    // the app. Lets agents exercise the reset→restart→onboarding flow without
    // driving menus or the cursor.
    register(
      name: "reset_onboarding",
      effects: [.localState],
      summary: "Reset onboarding state and restart the app (same path as the Reset Onboarding menu item)"
    ) { _ in
      await MainActor.run {
        (AppState.current ?? AppState()).resetOnboardingAndRestart()
      }
      return ["status": "resetting and restarting"]
    }

    register(
      name: "sign_out",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Sign out via AuthService (local Auth emulator harness only)",
      params: ["accepted_account_deletion"]
    ) { params in
      guard DesktopLocalProfile.isEnabled else {
        return ["error": "sign_out is only available with OMI_DESKTOP_LOCAL_PROFILE=1 (local Auth emulator)"]
      }
      let acceptedAccountDeletion = boolParam(params["accepted_account_deletion"], default: false)
      guard AuthState.shared.isSignedIn else {
        return ["signed_out": "true", "was_signed_in": "false"]
      }
      try await AuthService.shared.signOut(acceptedAccountDeletion: acceptedAccountDeletion)
      return [
        "accepted_account_deletion": acceptedAccountDeletion ? "true" : "false",
        "signed_out": "true",
        "was_signed_in": "true",
        "is_signed_in": AuthState.shared.isSignedIn ? "true" : "false",
      ]
    }




    // Drives the real post-meeting completion signal so the entire production
    // chain runs (banner service → conversation + recipients fetch → persistent
    // share card). Same NotificationCenter signal the finalization service posts.
    register(
      name: "trigger_meeting_completion",
      effects: [.localState],
      summary:
        "Post the real meeting-completion signal for a conversation id (presents the meeting summary share card). Non-prod only.",
      params: ["conversation_id"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "trigger_meeting_completion is disabled on production bundles"]
      }
      guard let conversationID = params["conversation_id"], !conversationID.isEmpty else {
        throw DesktopAutomationActionError.invalidParams("conversation_id is required")
      }
      NotificationCenter.default.post(
        name: .desktopMeetingConversationDidComplete,
        object: MeetingCompletionNotification(conversationIDs: [conversationID]))
      return ["posted": conversationID]
    }


    // Presents the same "Omi is taking notes" notice the meeting boundary
    // posts once a detected meeting has rotated into its recording session.
    register(
      name: "trigger_meeting_started_notice",
      effects: [.localState],
      summary:
        "Present the meeting-started note-taking notice (the card shown when a meeting is detected). Non-prod only.",
      params: []
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "trigger_meeting_started_notice is disabled on production bundles"]
      }
      MeetingNoteTakingNotice.present()
      return ["presented": "true"]
    }






















    register(
      name: "memories_qa_export",
      effects: [.networkOrModel],
      summary: "Export memory counts by tier from the live API (local QA automation)",
      params: ["limit"]
    ) { params in
      let limit = Int(params["limit"] ?? "") ?? 50
      let memories = try await APIClient.shared.getMemories(limit: limit, offset: 0)
      let shortCount = memories.filter { $0.tier == .shortTerm }.count
      let longCount = memories.filter { $0.tier == .longTerm }.count
      let samples: [[String: String]] = memories.prefix(12).map { memory in
        [
          "id": memory.id,
          "tier": memory.tier.rawValue,
          "tierIsExplicit": memory.tierIsExplicit ? "true" : "false",
          "content": String(memory.content.prefix(90)),
          "conversationId": memory.conversationId ?? "",
        ]
      }
      let samplesData = try JSONSerialization.data(withJSONObject: samples)
      let samplesJson = String(data: samplesData, encoding: .utf8) ?? "[]"
      return [
        "total": "\(memories.count)",
        "short_term": "\(shortCount)",
        "long_term": "\(longCount)",
        "samples_json": samplesJson,
      ]
    }

    register(
      name: "apple_notes_read_probe",
      effects: [.localState],
      summary: "Probe Apple Notes access without importing or saving memories",
      params: ["folderPath", "maxResults", "remember"]
    ) { params in
      let maxResults = min(max(intParam(params["maxResults"], default: 20), 1), 250)
      let remember = boolParam(params["remember"], default: false)

      do {
        let selectedFolderPath: String?
        if let requestedFolder = try AppleNotesReadProbe.resolveRequestedFolder(path: params["folderPath"]) {
          let resolved = try await AppleNotesReaderService.shared.validateSelectedFolder(
            path: requestedFolder.path,
            remember: remember
          )
          selectedFolderPath = resolved.path
        } else {
          selectedFolderPath = nil
        }

        let status = await AppleNotesReaderService.shared.connectionStatus(
          maxResults: maxResults,
          selectedFolderPath: selectedFolderPath,
          userInitiated: true
        )
        switch status {
        case .connected(let noteCount, _):
          return [
            "ok": "true",
            "classification": "readable",
            "noteCount": "\(noteCount)",
            "folderSelected": selectedFolderPath == nil ? "false" : "true",
          ]
        case .needsAccess(let message, let reasonCode):
          return [
            "ok": "false",
            "classification": reasonCode,
            "message": message,
            "needsFolderSelection": "true",
          ]
        case .error(let message, let reasonCode):
          return [
            "ok": "false",
            "classification": reasonCode,
            "message": message,
            "needsFolderSelection": "false",
          ]
        }
      } catch let error as AppleNotesReaderError {
        return [
          "ok": "false",
          "classification": error.reasonCode,
          "message": error.localizedDescription,
          "needsFolderSelection": "\(error.shouldPromptForFolderSelection)",
        ]
      } catch {
        return [
          "ok": "false",
          "classification": "unknown_error",
          "message": error.localizedDescription,
        ]
      }
    }


    register(
      name: "delete_conversation",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Delete conversation with cascade (API + conversationDeleted notification)",
      params: ["id"]
    ) { params in
      guard let id = params["id"], !id.isEmpty else {
        return ["error": "missing 'id'"]
      }
      if let appState = await MainActor.run(body: { AppState.current }) {
        guard await appState.deleteConversation(id) else {
          throw APIError.invalidResponse
        }
      } else {
        try await APIClient.shared.deleteConversation(id: id)
        NotificationCenter.default.post(
          name: .conversationDeleted,
          object: nil,
          userInfo: ["conversationId": id]
        )
      }
      return ["deleted": id]
    }

    register(
      name: "capture_main_window_png",
      effects: [.localArtifact],
      summary: "Write PNG of the frontmost Omi window (in-process capture)",
      params: ["path", "surface"]
    ) { params in
      guard let path = params["path"], !path.isEmpty else {
        return ["error": "missing 'path'"]
      }
      return await MainActor.run { () -> [String: String] in
        guard
          let window = NSApp.windows.first(where: {
            $0.isVisible && $0.title.range(of: "omi", options: .caseInsensitive) != nil
          })
        else {
          return ["error": "no_visible_window"]
        }
        let requestedSheet = params["surface"] == "sheet"
        let captureWindow = requestedSheet ? (window.attachedSheet ?? window) : window
        guard let contentView = captureWindow.contentView else {
          return ["error": "no_content_view"]
        }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
          return ["error": "bitmap_rep_failed"]
        }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
          return ["error": "png_encode_failed"]
        }
        do {
          try data.write(to: URL(fileURLWithPath: path))
          var result = [
            "path": path,
            "bytes": "\(data.count)",
            "captured_surface": requestedSheet && window.attachedSheet != nil ? "sheet" : "window",
            "frame_x": "\(Int(window.frame.origin.x.rounded()))",
            "frame_y": "\(Int(window.frame.origin.y.rounded()))",
            "frame_width": "\(Int(window.frame.width.rounded()))",
            "frame_height": "\(Int(window.frame.height.rounded()))",
            "backing_scale": String(format: "%.1f", window.backingScaleFactor),
          ]
          if let sheet = window.attachedSheet {
            result["has_sheet"] = "true"
            result["sheet_frame_x"] = "\(Int(sheet.frame.origin.x.rounded()))"
            result["sheet_frame_y"] = "\(Int(sheet.frame.origin.y.rounded()))"
            result["sheet_frame_width"] = "\(Int(sheet.frame.width.rounded()))"
            result["sheet_frame_height"] = "\(Int(sheet.frame.height.rounded()))"
          } else {
            result["has_sheet"] = "false"
          }
          return result
        } catch {
          return ["error": error.localizedDescription]
        }
      }
    }






    register(
      name: "spatial_overlay_present_fixture",
      effects: [.localState],
      summary: "Present a deterministic spatial-overlay fixture for dogfood harnesses",
      params: ["fixture", "settleMs"]
    ) { params in
      guard let fixture = SpatialOverlayDogfoodFixture(rawValue: params["fixture"] ?? "") else {
        throw DesktopAutomationActionError.invalidParams(
          "unknown fixture; expected one of \(SpatialOverlayDogfoodFixture.allCases.map(\.rawValue).joined(separator: ","))"
        )
      }
      let state = CloudConnectorGuidanceOverlay.shared.presentAutomationFixture(fixture)
      return state
    }

    register(
      name: "spatial_overlay_state",
      effects: [],
      summary: "Return the current spatial-overlay dogfood state"
    ) { _ in
      CloudConnectorGuidanceOverlay.shared.automationState()
    }

    register(
      name: "spatial_overlay_dismiss",
      effects: [.localState],
      summary: "Dismiss the current spatial-overlay dogfood overlay"
    ) { _ in
      CloudConnectorGuidanceOverlay.shared.dismiss()
      return ["dismissed": "true", "visible": "false"]
    }

    register(
      name: "integration_nudge_evaluate",
      effects: [.localState],
      summary:
        "Read-only: which integration a given frontmost app/window maps to, and whether a nudge would fire",
      params: ["bundle_id", "window_title"],
      category: "read",
    ) { params in
      await IntegrationNudgeAutomation.evaluate(
        bundleID: params["bundle_id"],
        windowTitle: params["window_title"]
      )
    }

    register(
      name: "integration_nudge_present",
      effects: [.localState],
      summary: "Present the integration-connect card for one catalog entry (QA of the real card path)",
      params: ["telemetry_id"],
      category: "write",
      surfaces: ["floating_bar"],
    ) { params in
      await MainActor.run { IntegrationNudgeAutomation.present(telemetryID: params["telemetry_id"] ?? "") }
    }

    register(
      name: "cloud_connector_guidance_probe",
      effects: [],
      summary: "Read-only diagnostic of the live Claude Add detection (no overlay, no clicks)"
    ) { _ in
      await MainActor.run { CloudConnectorFormAutomation.claudeAddGuidanceDiagnostics() }
    }










    register(
      name: "calendar_read_probe",
      effects: [.localState, .networkOrModel],
      summary: "Read Google Calendar through the real connector path and return classified status",
      params: ["daysBack", "daysForward", "maxResults"]
    ) { params in
      let requestedDaysBack = intParam(params["daysBack"], default: 1)
      let requestedDaysForward = intParam(params["daysForward"], default: 1)
      let requestedMaxResults = intParam(params["maxResults"], default: 1)
      let normalized = CalendarFetchParameters.normalized(
        daysBack: requestedDaysBack,
        daysForward: requestedDaysForward,
        maxResults: requestedMaxResults
      )

      do {
        let events = try await CalendarReaderService.shared.readEvents(
          daysBack: normalized.daysBack,
          daysForward: normalized.daysForward,
          maxResults: normalized.maxResults,
          userInitiated: true
        )
        return [
          "status": "connected",
          "classification": "readable",
          "eventCount": "\(events.count)",
          "daysBack": "\(normalized.daysBack)",
          "daysForward": "\(normalized.daysForward)",
          "maxResults": "\(normalized.maxResults)",
        ]
      } catch let error as CalendarReaderError {
        let classification: String
        switch error {
        case .noBrowserFound:
          classification = "no_browser"
        case .notSignedIn:
          classification = "not_signed_in"
        case .sessionExpired:
          classification = "session_expired"
        case .cookieDecryptionFailed:
          classification = "decrypt_failed"
        case .configurationError:
          classification = "configuration"
        case .networkError:
          classification = "network"
        case .pythonNotFound:
          classification = "python_not_found"
        }
        return [
          "status": "error",
          "classification": classification,
          "message": error.errorDescription ?? "\(error)",
          "daysBack": "\(normalized.daysBack)",
          "daysForward": "\(normalized.daysForward)",
          "maxResults": "\(normalized.maxResults)",
        ]
      }
    }

    register(
      name: "gmail_read_probe",
      effects: [.localState, .networkOrModel],
      summary: "Read Gmail through the real connector path and return classified status",
      params: ["maxResults", "query"]
    ) { params in
      let requestedMaxResults = intParam(params["maxResults"], default: 1)
      let maxResults = min(max(requestedMaxResults, 1), 500)
      let rawQuery = params["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let query = rawQuery.isEmpty ? "newer_than:1d" : rawQuery

      do {
        let emails = try await GmailReaderService.shared.readRecentEmails(
          maxResults: maxResults,
          query: query,
          userInitiated: true
        )
        return [
          "status": "connected",
          "classification": "readable",
          "emailCount": "\(emails.count)",
          "maxResults": "\(maxResults)",
          "query": query,
        ]
      } catch let error as GmailReaderError {
        let classification: String
        switch error {
        case .noBrowserFound:
          classification = "no_browser"
        case .noGmailCookies, .notSignedIn:
          classification = "not_signed_in"
        case .sessionExpired, .authFailed:
          classification = "session_expired"
        case .cookieDecryptionFailed:
          classification = "decrypt_failed"
        case .networkError:
          classification = "network"
        case .pythonNotFound:
          classification = "python_not_found"
        }
        return [
          "status": "error",
          "classification": classification,
          "message": error.errorDescription ?? "\(error)",
          "maxResults": "\(maxResults)",
          "query": query,
        ]
      } catch {
        return [
          "status": "error",
          "classification": "unknown",
          "message": error.localizedDescription,
          "maxResults": "\(maxResults)",
          "query": query,
        ]
      }
    }

    register(
      name: "spatial_overlay_present_instruction",
      effects: [.localState],
      summary: "Present the Screen Recording fallback instruction card (dogfood/visual)"
    ) { params in
      let title = params["title"] ?? "Allow Screen Recording for Omi"
      let subtitle =
        params["subtitle"]
        ?? "Turn on Omi under Screen & System Audio Recording, then return to Claude and click Add."
      let anchor = CloudConnectorGuidanceOverlay.anchorRect(fromParam: params["anchor"])
      CloudConnectorGuidanceOverlay.shared.presentInstructionCard(
        title: title, subtitle: subtitle, near: anchor)
      return CloudConnectorGuidanceOverlay.shared.automationState()
    }

    register(
      name: "preview_screen_recording_drag_helper",
      effects: [.localState],
      summary: "Open Screen Recording settings and show the drag-to-enable helper"
    ) { _ in
      await MainActor.run { ScreenCaptureService.openScreenRecordingPreferences() }
      return CloudConnectorGuidanceOverlay.shared.automationState()
    }

    register(
      name: "open_conversation",
      effects: [.localState, .networkOrModel],
      summary: "Open a conversation detail view (same path as POST /conversation/open)",
      params: ["conversationId", "showTranscript", "timeoutMs"]
    ) { params in
      guard let conversationId = params["conversationId"]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !conversationId.isEmpty
      else {
        return ["error": "missing conversationId"]
      }
      let showTranscript = boolParam(params["showTranscript"], default: false)
      try await ensureConversationsTabVisibleForAutomation()
      await requestAutomationConversationOpen(conversationId: conversationId, showTranscript: showTranscript)
      let timeoutMs = max(500, intParam(params["timeoutMs"], default: 5_000))
      let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
      while ConversationDetailAutomationState.shared.openConversationId != conversationId,
        Date() < deadline
      {
        try await Task.sleep(nanoseconds: 50_000_000)
      }
      return [
        "opened": conversationId,
        "show_transcript": showTranscript ? "true" : "false",
        "detail_open": ConversationDetailAutomationState.shared.openConversationId == conversationId ? "true" : "false",
      ]
    }

    register(
      name: "set_conversations_search",
      effects: [.localState, .networkOrModel],
      summary: "Set the Conversations page search query (drives the real debounced search path)",
      params: ["query"]
    ) { params in
      try await ensureConversationsTabVisibleForAutomation()
      NotificationCenter.default.post(
        name: .desktopAutomationSetConversationsSearchRequested,
        object: nil,
        userInfo: ["query": params["query"] ?? ""]
      )
      return ["query": params["query"] ?? ""]
    }

    register(
      name: "open_latest_conversation",
      effects: [.localState, .networkOrModel],
      summary: "Open the most recently loaded conversation detail view",
      params: ["showTranscript", "timeoutMs"]
    ) { params in
      guard let appState = AppState.current else {
        return ["error": "app state unavailable"]
      }
      if appState.conversations.isEmpty {
        await appState.refreshConversations()
      }
      guard let conversationId = appState.conversations.first?.id else {
        return ["error": "no conversations available"]
      }
      let showTranscript = boolParam(params["showTranscript"], default: false)
      try await ensureConversationsTabVisibleForAutomation()
      await requestAutomationConversationOpen(conversationId: conversationId, showTranscript: showTranscript)
      let timeoutMs = max(500, intParam(params["timeoutMs"], default: 5_000))
      let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
      while ConversationDetailAutomationState.shared.openConversationId != conversationId,
        Date() < deadline
      {
        try await Task.sleep(nanoseconds: 50_000_000)
      }
      return [
        "opened": conversationId,
        "show_transcript": showTranscript ? "true" : "false",
        "detail_open": ConversationDetailAutomationState.shared.openConversationId == conversationId ? "true" : "false",
      ]
    }

    register(
      name: "conversation_detail_snapshot",
      effects: [.localState, .networkOrModel],
      summary: "Return open conversation detail fields for harness assertions",
      params: ["conversationId"]
    ) { params in
      var requestedId = params["conversationId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      if requestedId == "latest" {
        if let appState = AppState.current, appState.conversations.isEmpty {
          await appState.refreshConversations()
        }
        requestedId = AppState.current?.conversations.first?.id
      }
      let automation = ConversationDetailAutomationState.shared
      let conversationId = (requestedId?.isEmpty == false ? requestedId : automation.openConversationId)
      guard let conversationId, !conversationId.isEmpty else {
        return [
          "detail_open": "false",
          "error": "no open conversation",
        ]
      }
      let detailOpen = automation.openConversationId == conversationId
      let drawerOpen = detailOpen && automation.transcriptDrawerOpen
      do {
        let conversation = try await APIClient.shared.getConversation(id: conversationId)
        let segmentCount = conversation.transcriptSegments.count
        return [
          "detail_open": detailOpen ? "true" : "false",
          "conversation_id": conversationId,
          "title": conversation.structured.title,
          "segment_count": "\(segmentCount)",
          "transcript_drawer_open": drawerOpen ? "true" : "false",
          "folder_id": conversation.folderId ?? "none",
          "starred": conversation.starred ? "true" : "false",
        ]
      } catch {
        guard let appState = AppState.current,
          let cached = appState.conversations.first(where: { $0.id == conversationId })
        else {
          return [
            "detail_open": detailOpen ? "true" : "false",
            "conversation_id": conversationId,
            "transcript_drawer_open": drawerOpen ? "true" : "false",
            "error": error.localizedDescription,
          ]
        }
        return [
          "detail_open": detailOpen ? "true" : "false",
          "conversation_id": conversationId,
          "title": cached.structured.title,
          "segment_count": "\(cached.transcriptSegments.count)",
          "transcript_drawer_open": drawerOpen ? "true" : "false",
          "folder_id": cached.folderId ?? "none",
          "starred": cached.starred ? "true" : "false",
        ]
      }
    }

    register(
      name: "create_test_memory",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Create a hermetic test memory via the real API",
      params: ["content", "source"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "create_test_memory is disabled on production bundles"]
      }
      let content = params["content"] ?? "[[MARKER:memory-crud]] hermetic desktop memory"
      let response = try await APIClient.shared.createMemory(
        content: content,
        source: params["source"] ?? "harness"
      )
      if let page = try? await APIClient.shared.getMemoriesPage(limit: 100, offset: 0) {
        _ = try? await MemoryStorage.shared.syncServerMemories(page.memories)
      }
      let memoryCount = (try? await MemoryStorage.shared.getLocalMemoriesCount()) ?? 0
      return [
        "created": "true",
        "memory_id": response.id,
        "memory_count": "\(memoryCount)",
      ]
    }

    register(
      name: "edit_test_memory",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Edit a hermetic test memory via the real API",
      params: ["id", "marker", "content"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "edit_test_memory is disabled on production bundles"]
      }
      let content = params["content"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !content.isEmpty else {
        return ["error": "missing content"]
      }
      let id: String?
      if let explicit = params["id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
        id = explicit
      } else if let marker = params["marker"]?.trimmingCharacters(in: .whitespacesAndNewlines), !marker.isEmpty {
        let page = try await APIClient.shared.getMemoriesPage(limit: 100, offset: 0)
        id = page.memories.first(where: { $0.content.contains(marker) })?.id
      } else {
        id = nil
      }
      guard let id, !id.isEmpty else {
        return ["error": "missing id or marker match"]
      }
      try await APIClient.shared.editMemory(id: id, content: content)
      if let page = try? await APIClient.shared.getMemoriesPage(limit: 100, offset: 0) {
        _ = try? await MemoryStorage.shared.syncServerMemories(page.memories)
      }
      return [
        "edited": id,
        "content": content,
      ]
    }

    register(
      name: "delete_test_memory",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Delete a hermetic test memory via the real API",
      params: ["id", "marker"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "delete_test_memory is disabled on production bundles"]
      }
      let id: String?
      if let explicit = params["id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
        id = explicit
      } else if let marker = params["marker"]?.trimmingCharacters(in: .whitespacesAndNewlines), !marker.isEmpty {
        let page = try await APIClient.shared.getMemoriesPage(limit: 100, offset: 0)
        id = page.memories.first(where: { $0.content.contains(marker) })?.id
      } else {
        id = nil
      }
      guard let id, !id.isEmpty else {
        return ["error": "missing id or marker match"]
      }
      try await APIClient.shared.deleteMemory(id: id)
      try? await MemoryStorage.shared.deleteMemoryByBackendId(id)
      if let page = try? await APIClient.shared.getMemoriesPage(limit: 100, offset: 0) {
        _ = try? await MemoryStorage.shared.syncServerMemories(page.memories)
      }
      let memoryCount = (try? await MemoryStorage.shared.getLocalMemoriesCount()) ?? 0
      return [
        "deleted": id,
        "memory_count": "\(memoryCount)",
      ]
    }

    register(
      name: "vocabulary_snapshot",
      effects: [],
      summary: "Return transcription custom vocabulary for harness assertions"
    ) { _ in
      let terms = AssistantSettings.shared.transcriptionVocabulary
      let termsJSON: String
      if let data = try? JSONSerialization.data(withJSONObject: terms),
        let encoded = String(data: data, encoding: .utf8)
      {
        termsJSON = encoded
      } else {
        termsJSON = "[]"
      }
      return [
        "term_count": "\(terms.count)",
        "terms_json": termsJSON,
      ]
    }

    register(
      name: "vocabulary_set_terms",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Set transcription custom vocabulary (local + backend)",
      params: ["terms"]
    ) { params in
      let raw = params["terms"] ?? ""
      let terms = raw.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      // Persist remotely first. A Settings-page hydration already in flight may
      // write its response into UserDefaults; the final assignment makes this
      // completed mutation authoritative without relying on a settle delay.
      let saved = try await APIClient.shared.updateTranscriptionPreferences(vocabulary: terms)
      AssistantSettings.shared.transcriptionVocabulary = saved.vocabulary
      return [
        "saved": "true",
        "term_count": "\(saved.vocabulary.count)",
      ]
    }

    register(
      name: "goals_snapshot",
      effects: [.networkOrModel],
      summary: "Return dashboard goals state for harness assertions"
    ) { _ in
      let goals: [Goal]
      if let apiGoals = try? await APIClient.shared.getGoals() {
        goals = apiGoals
      } else if let localGoals = try? await GoalStorage.shared.getLocalGoals() {
        goals = localGoals
      } else {
        goals = []
      }
      let titles = goals.map(\.title)
      let titlesJSON: String
      if let data = try? JSONSerialization.data(withJSONObject: titles),
        let encoded = String(data: data, encoding: .utf8)
      {
        titlesJSON = encoded
      } else {
        titlesJSON = "[]"
      }
      return [
        "goal_count": "\(goals.count)",
        "titles_json": titlesJSON,
      ]
    }

    register(
      name: "create_test_goal",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Create a hermetic dashboard goal via the real API",
      params: ["title", "targetValue", "currentValue"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "create_test_goal is disabled on production bundles"]
      }
      let title = params["title"] ?? "[[MARKER:goals-dashboard]] harness goal"
      let targetValue = Double(params["targetValue"] ?? "") ?? 10
      let currentValue = Double(params["currentValue"] ?? "") ?? 0
      let goal = try await APIClient.shared.createGoal(
        title: title,
        goalType: .numeric,
        targetValue: targetValue,
        currentValue: currentValue,
        source: "user"
      )
      _ = try? await GoalStorage.shared.syncServerGoal(goal)
      let goals = (try? await GoalStorage.shared.getLocalGoals()) ?? []
      return [
        "created": "true",
        "goal_id": goal.id,
        "goal_count": "\(goals.count)",
      ]
    }

    register(
      name: "apps_catalog_snapshot",
      effects: [.networkOrModel],
      summary: "Return apps marketplace catalog counts for harness assertions"
    ) { _ in
      let v2 = try await APIClient.shared.getAppsV2()
      let marketplaceCount = v2.groups.reduce(0) { $0 + $1.data.count }
      let installed = try await APIClient.shared.searchApps(installedOnly: true, limit: 100)
      return [
        "marketplace_count": "\(marketplaceCount)",
        "group_count": "\(v2.meta.groupCount)",
        "capability_count": "\(v2.meta.capabilities.count)",
        "installed_count": "\(installed.count)",
      ]
    }

    register(
      name: "subscription_snapshot",
      effects: [.networkOrModel],
      summary: "Return cached subscription/plan info from the billing API"
    ) { _ in
      let response = try await APIClient.shared.getUserSubscription()
      let subscription = response.subscription
      return [
        "plan": subscription.plan.rawValue,
        "status": subscription.status.rawValue,
        "show_subscription_ui": response.showSubscriptionUI ? "true" : "false",
        "transcription_seconds_used": "\(response.transcriptionSecondsUsed)",
        "transcription_seconds_limit": "\(response.transcriptionSecondsLimit)",
      ]
    }

    register(
      name: "settings_privacy_snapshot",
      effects: [.networkOrModel],
      summary: "Return privacy toggle defaults (store recordings, cloud sync, tracking)"
    ) { _ in
      async let recordingTask = APIClient.shared.getRecordingPermission()
      async let cloudSyncTask = APIClient.shared.getPrivateCloudSync()
      let (recording, cloudSync) = try await (recordingTask, cloudSyncTask)
      let trackingEnabled = PostHogManager.shared.hasOptedOut
      return [
        "store_recordings": recording.enabled ? "true" : "false",
        "cloud_sync": cloudSync.enabled ? "true" : "false",
        "tracking_enabled": trackingEnabled ? "true" : "false",
      ]
    }

    register(
      name: "permissions_snapshot", effects: [.localState], summary: "Every permission row the Permissions page shows"
    ) {
      _ in await PermissionsSnapshot.capture()
    }

    register(
      name: "create_test_folder",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Create a hermetic conversation folder via the real API",
      params: ["name"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "create_test_folder is disabled on production bundles"]
      }
      let name = params["name"] ?? "[[MARKER:conversation-folders]] harness folder"
      guard let appState = AppState.current else {
        return ["error": "app state unavailable"]
      }
      guard let folder = await appState.createFolder(name: name) else {
        return ["error": "failed to create folder"]
      }
      return [
        "created": "true",
        "folder_id": folder.id,
        "folder_name": folder.name,
        "folder_count": "\(appState.folders.count)",
      ]
    }

    register(
      name: "set_conversation_starred",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Set conversation starred status via the real API",
      params: ["conversationId", "starred"]
    ) { params in
      guard let conversationId = params["conversationId"]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !conversationId.isEmpty
      else {
        return ["error": "missing conversationId"]
      }
      let resolvedConversationId: String
      if conversationId == "latest" {
        guard let appState = AppState.current else {
          return ["error": "app state unavailable"]
        }
        if appState.conversations.isEmpty {
          await appState.refreshConversations()
        }
        guard let latestId = appState.conversations.first?.id else {
          return ["error": "no conversations available"]
        }
        resolvedConversationId = latestId
      } else {
        resolvedConversationId = conversationId
      }
      let starred = boolParam(params["starred"], default: true)
      guard let appState = AppState.current else {
        return ["error": "app state unavailable"]
      }
      try await appState.conversationRepository.setStarred(
        id: resolvedConversationId, starred: starred)
      return [
        "conversation_id": resolvedConversationId,
        "starred": starred ? "true" : "false",
      ]
    }

    register(
      name: "set_conversation_folder",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Move a conversation into a folder via the real API",
      params: ["conversationId", "folderId"]
    ) { params in
      let rawConversationId = params["conversationId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let rawConversationId, !rawConversationId.isEmpty else {
        return ["error": "missing conversationId"]
      }
      let conversationId: String
      if rawConversationId == "latest" {
        guard let appState = AppState.current else {
          return ["error": "app state unavailable"]
        }
        if appState.conversations.isEmpty {
          await appState.refreshConversations()
        }
        guard let latestId = appState.conversations.first?.id else {
          return ["error": "no conversations available"]
        }
        conversationId = latestId
      } else {
        conversationId = rawConversationId
      }
      let folderId = params["folderId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      let resolvedFolderId = (folderId?.isEmpty == false && folderId != "none") ? folderId : nil
      guard let appState = AppState.current else {
        return ["error": "app state unavailable"]
      }
      await appState.moveConversationToFolder(conversationId, folderId: resolvedFolderId)
      return [
        "conversation_id": conversationId,
        "folder_id": resolvedFolderId ?? "none",
      ]
    }

    register(
      name: "set_transcription_language",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Set transcription language (local + backend)",
      params: ["language", "autoDetect"]
    ) { params in
      guard let rawLanguage = params["language"]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !rawLanguage.isEmpty
      else {
        return ["error": "missing language"]
      }
      let normalized = AssistantSettings.normalizeTranscriptionLanguageCode(rawLanguage)
      if let autoDetectRaw = params["autoDetect"] {
        AssistantSettings.shared.transcriptionAutoDetect = boolParam(autoDetectRaw, default: true)
      }
      AssistantSettings.shared.transcriptionLanguage = normalized
      _ = try await APIClient.shared.updateUserLanguage(normalized)
      return [
        "saved": "true",
        "language": normalized,
        "auto_detect": AssistantSettings.shared.transcriptionAutoDetect ? "true" : "false",
        "effective_language": AssistantSettings.shared.effectiveTranscriptionLanguage,
      ]
    }

    register(
      name: "transcription_language_snapshot",
      effects: [],
      summary: "Return transcription language settings for harness assertions"
    ) { _ in
      let settings = AssistantSettings.shared
      return [
        "language": settings.transcriptionLanguage,
        "auto_detect": settings.transcriptionAutoDetect ? "true" : "false",
        "effective_language": settings.effectiveTranscriptionLanguage,
      ]
    }

    register(
      name: "memory_graph_rebuild",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary:
        "Regenerate the server-side knowledge graph from the signed-in account's memories",
      params: []
    ) { _ in
      // Mutating and not undoable: the backend deletes the stored graph before
      // the background rebuild runs, so a caller that loses the race sees an
      // empty graph. Exposed for cursor-free QA of the Brain Map's own rebuild
      // control, which is otherwise only reachable by clicking.
      do {
        let response = try await APIClient.shared.rebuildKnowledgeGraph()
        return [
          "status": response.status,
          "nodes_count": "\(response.nodesCount ?? 0)",
          "edges_count": "\(response.edgesCount ?? 0)",
        ]
      } catch {
        return [
          "has_error": "true",
          "error_message": error.localizedDescription,
        ]
      }
    }

    register(
      name: "memory_graph_snapshot",
      effects: [.networkOrModel],
      summary: "Return knowledge graph node/edge counts (no SceneKit rendering)",
      params: ["label"]
    ) { params in
      do {
        let graph = try await APIClient.shared.getKnowledgeGraph()
        let atlas = MemoryAtlasProjection(graph: graph.atlasResponse, userName: nil)
        var detail = [
          "node_count": "\(graph.nodes.count)",
          "edge_count": "\(graph.edges.count)",
          "catalog_memory_count": "\(graph.catalogNodes?.count ?? 0)",
          "atlas_mark_count": "\(atlas.snapshot.nodes.count)",
          "is_empty": graph.nodes.isEmpty ? "true" : "false",
        ]
        // A label resolves to the ids and citations the inspector needs.
        if let query = params["label"]?.lowercased(), !query.isEmpty {
          if let match = graph.nodes.first(where: { $0.label.lowercased().contains(query) }) {
            let edges = graph.edges.filter { $0.sourceId == match.id || $0.targetId == match.id }
            detail["match_id"] = match.id
            detail["match_label"] = match.label
            detail["match_edge_count"] = "\(edges.count)"
            detail["match_cited_memory_count"] = "\(Set(edges.flatMap(\.memoryIds)).count)"
            if let first = edges.first {
              detail["match_first_edge_id"] = first.id
              detail["match_first_edge_memory_count"] = "\(first.memoryIds.count)"
            }
          } else {
            detail["match_id"] = ""
          }
        }
        return detail
      } catch {
        return [
          "node_count": "0",
          "edge_count": "0",
          "is_empty": "true",
          "has_error": "true",
          "error_message": error.localizedDescription,
        ]
      }
    }

    register(
      name: "memory_atlas_select",
      effects: [.localState],
      summary: "Select a Brain Map entity or connection so the inspector can be checked cursor-free",
      params: ["target", "node_id", "label", "edge_id", "clear"]
    ) { params in
      let target = params["target"] == "inline" ? "inline" : "page"
      var userInfo: [String: Any] = ["target": target]
      if let nodeID = params["node_id"], !nodeID.isEmpty { userInfo["node_id"] = nodeID }
      if let label = params["label"], !label.isEmpty { userInfo["label"] = label }
      if let edgeID = params["edge_id"], !edgeID.isEmpty { userInfo["edge_id"] = edgeID }
      if params["clear"] == "true" { userInfo["clear"] = true }
      await MainActor.run {
        NotificationCenter.default.post(
          name: .desktopAutomationMemoryAtlasSelectRequested,
          object: nil,
          userInfo: userInfo
        )
      }
      return [
        "posted": "true",
        "target": target,
        "node_id": params["node_id"] ?? "",
        "label": params["label"] ?? "",
        "edge_id": params["edge_id"] ?? "",
        "clear": params["clear"] ?? "false",
      ]
    }

    register(
      name: "memories_open_detail",
      effects: [.localState, .networkOrModel],
      summary: "Open a memory's detail panel by backend id (omit the id to close it)",
      params: ["memory_id"]
    ) { params in
      let memoryId = params["memory_id"] ?? ""
      await MainActor.run {
        NotificationCenter.default.post(
          name: .desktopAutomationMemoryDetailOpenRequested,
          object: nil,
          userInfo: memoryId.isEmpty ? [:] : ["memory_id": memoryId]
        )
      }
      return ["posted": "true", "memory_id": memoryId]
    }

    register(
      name: "open_memory_atlas",
      effects: [.localState, .networkOrModel],
      summary: "Open the canonical memory atlas page for non-production UI and performance harnesses"
    ) { _ in
      await MainActor.run {
        NotificationCenter.default.post(
          name: .desktopAutomationOpenMemoryAtlasRequested,
          object: nil
        )
      }
      return ["opened": "true", "target": "page"]
    }

    register(
      name: "memory_atlas_set_viewport",
      effects: [.localState],
      summary: "Set memory atlas zoom and pan for deterministic non-production performance sweeps",
      params: ["target", "zoom", "pan_x", "pan_y", "reset"]
    ) { params in
      let target = params["target"] == "inline" ? "inline" : "page"
      var userInfo: [String: Any] = ["target": target]
      if let zoom = params["zoom"].flatMap(Double.init) { userInfo["zoom"] = zoom }
      if let panX = params["pan_x"].flatMap(Double.init) { userInfo["pan_x"] = panX }
      if let panY = params["pan_y"].flatMap(Double.init) { userInfo["pan_y"] = panY }
      if let reset = params["reset"] { userInfo["reset"] = reset == "true" }
      await MainActor.run {
        NotificationCenter.default.post(
          name: .desktopAutomationMemoryAtlasViewportRequested,
          object: nil,
          userInfo: userInfo
        )
      }
      return [
        "posted": "true",
        "target": target,
        "zoom": params["zoom"] ?? "unchanged",
        "pan_x": params["pan_x"] ?? "unchanged",
        "pan_y": params["pan_y"] ?? "unchanged",
      ]
    }

    register(
      name: "memory_atlas_enter_region",
      effects: [.localState],
      summary: "Go into a Brain Map neighbourhood by caption, or leave the one you are in",
      params: ["target", "caption", "leave"]
    ) { params in
      let target = params["target"] == "inline" ? "inline" : "page"
      var userInfo: [String: Any] = ["target": target]
      if let caption = params["caption"] { userInfo["caption"] = caption }
      if let leave = params["leave"] { userInfo["leave"] = leave == "true" }
      await MainActor.run {
        NotificationCenter.default.post(
          name: .desktopAutomationMemoryAtlasRegionRequested,
          object: nil,
          userInfo: userInfo
        )
      }
      return [
        "posted": "true", "target": target,
        "caption": params["caption"] ?? "", "leave": params["leave"] ?? "false",
      ]
    }

    register(
      name: "memory_atlas_set_time",
      effects: [.localState],
      summary: "Scrub or play the memory atlas time axis for deterministic non-production checks",
      params: ["target", "fraction", "play", "reset_to_start", "reset"]
    ) { params in
      let target = params["target"] == "inline" ? "inline" : "page"
      var userInfo: [String: Any] = ["target": target]
      if let fraction = params["fraction"].flatMap(Double.init) { userInfo["fraction"] = fraction }
      if let play = params["play"] { userInfo["play"] = play == "true" }
      if let resetToStart = params["reset_to_start"] { userInfo["reset_to_start"] = resetToStart == "true" }
      if let reset = params["reset"] { userInfo["reset"] = reset == "true" }
      await MainActor.run {
        NotificationCenter.default.post(
          name: .desktopAutomationMemoryAtlasTimeRequested,
          object: nil,
          userInfo: userInfo
        )
      }
      return [
        "posted": "true",
        "target": target,
        "fraction": params["fraction"] ?? "unchanged",
        "play": params["play"] ?? "unchanged",
      ]
    }

    register(
      name: "open_quick_note",
      effects: [.localState],
      summary: "Open Quick Note via Rewind notes path (same as dashboard Quick Note button)"
    ) { _ in
      NotificationCenter.default.post(name: .navigateToRewindNotes, object: nil)
      return [
        "posted": "navigateToRewindNotes",
        "expected_tab_index": "\(SidebarNavItem.conversations.rawValue)",
        "expected_memory_destination": "\(MemoryHubDestination.rewind.rawValue)",
      ]
    }

    register(
      name: "about_snapshot",
      effects: [],
      summary: "Return About settings version/build/bundle metadata"
    ) { _ in
      let updater = UpdaterViewModel.shared
      return [
        "version": updater.currentVersion,
        "build": updater.buildNumber,
        "bundle_id": AppBuild.bundleIdentifier,
        "channel": updater.activeChannelLabel,
      ]
    }

    register(
      name: "client_telemetry_flag_snapshot",
      effects: [],
      summary: "Return the client telemetry migration/retirement flag state (e2e flow: client-telemetry-shadow)"
    ) { _ in
      [
        "transport_shadow_enabled": ClientTelemetryFlags.transportShadowEnabled ? "true" : "false",
        "posthog_retirement_enabled": ClientTelemetryFlags.postHogRetirementEnabled ? "true" : "false",
        "retires_infrastructure_posthog": ClientTelemetryFlags.retiresInfrastructurePostHog ? "true" : "false",
      ]
    }

    register(
      name: "client_telemetry_shadow_probe",
      effects: [.localState],
      summary:
        "Enqueue one shadow observation, reload the store from disk, and prove the wire payload stays owner-free (e2e flow: client-telemetry-shadow)",
      params: ["owner_id", "population"]
    ) { params in
      let ownerID = params["owner_id"] ?? "e2e-telemetry-owner"
      let population = params["population"] ?? "physical_shortcut"
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("e2e-client-telemetry", isDirectory: true)
      let limits = ClientTelemetryLimits.production
      let now = Date()
      let operationID = UUID()
      let observation = ClientTelemetryObservation(
        eventID: UUID(),
        occurredAt: now,
        platform: "macos",
        channel: "e2e",
        family: "voice_turn",
        attributes: [
          "operation_id": .string(operationID.uuidString.lowercased()),
          "phase": .string("terminal"),
          "population": .string(population),
          "route": .string("hub"),
          "intent": .string("hold"),
          "outcome": .string("success"),
          "latency_ms": .int(1200),
        ],
        ownerID: ownerID,
        enqueuedAt: now,
        attemptCount: 0
      )
      let store = ClientTelemetryStore(directory: directory, limits: limits)
      // Enqueue through the same validation path the transport uses.
      let enqueueOK = store.enqueue(observation, now: now)
      let pendingAfterEnqueue = store.observations(ownerID: ownerID)
      // Reload from disk through a second store instance (restart semantics).
      let reloadedStore = ClientTelemetryStore(directory: directory, limits: limits)
      let pendingAfterReload = reloadedStore.observations(ownerID: ownerID)
      let reloadedAttempts = pendingAfterReload.first?.attemptCount
      // Build the wire body exactly as the transport does and assert it is owner-free.
      var wireContainsOwnerID = false
      if let body = ClientTelemetryCodec.batchData(batchID: UUID(), observations: pendingAfterReload) {
        wireContainsOwnerID = String(data: body, encoding: .utf8)?.contains(ownerID) == true
      }
      return [
        "enqueued": enqueueOK ? "true" : "false",
        "pending_count": "\(pendingAfterEnqueue.count)",
        "reloaded_pending_count": "\(pendingAfterReload.count)",
        "wire_contains_owner_id": wireContainsOwnerID ? "true" : "false",
        "attempt_count_after_reload": "\(reloadedAttempts ?? -1)",
      ]
    }

    registerNotificationActions()
    registerRatingPromptActions()
    registerGlassTransparencyActions()
    registerRemotePromptActions()
    register(
      name: "rewind_settings_snapshot",
      effects: [],
      summary: "Return Rewind settings retention and excluded-app counts"
    ) { _ in
      let settings = RewindSettings.shared
      let stats = await RewindIndexer.shared.getStats()
      return [
        "retention_days": "\(settings.retentionDays)",
        "capture_interval": String(format: "%.1f", settings.captureInterval),
        "excluded_app_count": "\(settings.excludedApps.count)",
        "indexed_frames": "\(stats?.indexed ?? 0)",
        "total_frames": "\(stats?.total ?? 0)",
        "storage_bytes": "\(stats?.storageSize ?? 0)",
      ]
    }
    registerRewindArtifactRecoveryGauntlet()
    register(
      name: "navigate_via_shortcut",
      effects: [.localState],
      summary: "Post the same navigation notification as the Cmd+1..4 / Cmd+, shortcuts",
      params: ["shortcut"]
    ) { params in
      let shortcut = (params["shortcut"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      guard !shortcut.isEmpty else {
        return ["error": "missing shortcut (1-4 or comma)"]
      }
      let item: SidebarNavItem?
      // ⌘1…⌘4 are the top bar's pills; ⌘2 opens Memories on Activity. Hub pages also by name.
      let hub: MemoryHubDestination? = shortcut == "2" ? .activity : nil
      switch shortcut {
      case "1", "home", "dashboard", "chat": item = .dashboard
      case "2", "conversations": item = .conversations
      case "memories": item = .memories
      case "3", "tasks": item = .tasks
      case "rewind": item = .rewind
      case "4", "apps": item = .apps
      case ",", "comma", "settings": item = .settings
      // Settings sub-sections ride the same notifications the app already posts
      // for its own deep-links (the Tasks gear, the floating-bar context menu),
      // so QA can land on a specific pane without any cursor input.
      case "tasksettings", "advancedsettings":
        NotificationCenter.default.post(name: .navigateToTaskSettings, object: nil)
        return ["navigated": "Settings › Advanced"]
      case "floatingbarsettings":
        NotificationCenter.default.post(name: .navigateToFloatingBarSettings, object: nil)
        return ["navigated": "Settings › Floating Bar"]
      default: item = nil
      }
      guard let item else {
        return ["error": "unsupported shortcut '\(shortcut)'"]
      }
      var info: [String: Any] = ["rawValue": item.rawValue]
      if let hub { info["hubDestination"] = hub.rawValue }
      NotificationCenter.default.post(name: .navigateToSidebarItem, object: nil, userInfo: info)
      return [
        "navigated": item.title,
        "selected_tab_index": "\(item.rawValue)",
      ]
    }

    register(
      name: "advanced_settings_snapshot",
      effects: [],
      summary: "Return safe Advanced settings booleans (never raw BYOK keys)",
      params: []
    ) { _ in
      let task = TaskAssistantSettings.shared
      let memory = MemoryAssistantSettings.shared
      let assistant = AssistantSettings.shared
      return [
        "task_enabled": task.isEnabled ? "true" : "false",
        "memory_enabled": memory.isEnabled ? "true" : "false",
        "screen_analysis_enabled": assistant.screenAnalysisEnabled ? "true" : "false",
        "transcription_enabled": assistant.audioRecordingMode != .off ? "true" : "false",
        "audio_recording_mode": assistant.audioRecordingMode.rawValue,
      ]
    }

    register(
      name: "settings_aichat_snapshot",
      effects: [],
      summary: "Return AI Chat settings safe fields (provider mode, working directory presence)",
      params: []
    ) { _ in
      let bridgeMode = UserDefaults.standard.string(forKey: .chatBridgeMode) ?? "piMono"
      let workingDirectory = UserDefaults.standard.string(forKey: .aiChatWorkingDirectory) ?? ""
      return [
        "bridge_mode": bridgeMode,
        "working_directory_set": workingDirectory.isEmpty ? "false" : "true",
      ]
    }

    register(
      name: "assign_speaker_fixture",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Assign a person name to a conversation segment (hermetic speaker naming)",
      params: ["conversationId", "segmentIndex", "personName"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "assign_speaker_fixture is disabled on production bundles"]
      }
      guard let appState = AppState.current else {
        return ["error": "app state unavailable"]
      }
      let personName =
        params["personName"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "[[MARKER:speaker-naming]] Harness Speaker"
      let segmentIndex = max(0, Int(params["segmentIndex"] ?? "") ?? 0)

      // Raw mode: drive assignSpeakerToSegments with the ids exactly as given,
      // without resolving the conversation first — the seam that exercises the
      // local-first fallback for conversations the backend does not have yet.
      if let rawConversationId = params["rawConversationId"]?.trimmingCharacters(
        in: .whitespacesAndNewlines), !rawConversationId.isEmpty
      {
        let rawSegmentIds = (params["rawSegmentIds"] ?? "").split(separator: ",").map(String.init)
        guard !rawSegmentIds.isEmpty else { return ["error": "rawSegmentIds required in raw mode"] }
        guard let person = await appState.createPerson(name: personName) else {
          return ["error": "failed to create person"]
        }
        let assigned = await appState.assignSpeakerToSegments(
          conversationId: rawConversationId,
          segmentIds: rawSegmentIds,
          personId: person.id,
          isUser: false
        )
        return [
          "raw_mode": "true",
          "assigned": assigned ? "true" : "false",
          "conversation_id": rawConversationId,
          "person_id": person.id,
        ]
      }

      var conversationId = params["conversationId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      if conversationId == "latest" || conversationId?.isEmpty != false {
        if appState.conversations.isEmpty {
          await appState.refreshConversations()
        }
        conversationId = appState.conversations.first?.id
      }
      guard let conversationId, !conversationId.isEmpty else {
        return ["error": "no conversation available"]
      }

      let conversation = try await APIClient.shared.getConversation(id: conversationId)
      guard segmentIndex < conversation.transcriptSegments.count else {
        return [
          "error": "segment index out of range",
          "segment_count": "\(conversation.transcriptSegments.count)",
        ]
      }
      let segment = conversation.transcriptSegments[segmentIndex]
      guard let person = await appState.createPerson(name: personName) else {
        return ["error": "failed to create person"]
      }
      let assigned = await appState.assignSpeakerToSegments(
        conversationId: conversationId,
        segmentIds: [segment.id],
        personId: person.id,
        isUser: false
      )
      guard assigned else {
        return ["error": "assign segments failed"]
      }
      let refreshed = try await APIClient.shared.getConversation(id: conversationId)
      let assignedSegment = refreshed.transcriptSegments.first(where: { $0.id == segment.id })
      return [
        "assigned": "true",
        "conversation_id": conversationId,
        "segment_id": segment.id,
        "segment_index": "\(segmentIndex)",
        "person_id": person.id,
        "person_name": person.name,
        "speaker_label": assignedSegment?.speaker ?? segment.speaker ?? "",
        "segment_count": "\(refreshed.transcriptSegments.count)",
      ]
    }

    register(
      name: "screen_frame_quick_look_probe",
      effects: [.localState, .localArtifact, .networkOrModel],
      summary: "Open screenshots in Quick Look and read the panel back",
      params: ["conversationId", "source", "dismiss"]
    ) { params in
      // Quick Look's panel is a system window, so no capture path in this app can photograph it —
      // see `ScreenFrameQuickLook.probeState()`. This is how the responder-chain claim, the
      // materialisation of signed URLs into files, and the panel actually opening are verified.
      if params["dismiss"] == "true" {
        await ScreenFrameQuickLook.shared.dismissForProbe()
        return ["dismissed": "true"]
      }
      // Two sources, because they materialise by completely different routes: a meeting frame is a
      // signed URL to download, a Rewind moment is usually a frame inside a video chunk to decode.
      // A probe that only exercised one would leave the other unproven.
      let source = params["source"] ?? "conversation"
      let frames: [QuickLookFrame]
      let subject: String
      if source == "synthetic" {
        // The hermetic case. It needs neither a signed URL nor a Rewind chunk, so it can run on a
        // fresh bundle with no capture history and no backend — which is what makes it usable as
        // an e2e step. `URLSession` serves `file://` for a data task, so this reaches the panel
        // through exactly the same materialise-then-present path a real frame does.
        let seed = FileManager.default.temporaryDirectory
          .appendingPathComponent("omi-quick-look-probe.png")
        guard let png = Data(base64Encoded: Self.onePixelPNGBase64) else {
          return ["error": "probe_seed_undecodable"]
        }
        do {
          try png.write(to: seed, options: .atomic)
        } catch {
          return ["error": "probe_seed_unwritable: \(error.localizedDescription)"]
        }
        frames = [QuickLookFrame(id: "probe", source: .remote(seed), title: "Quick Look probe")]
        subject = "synthetic"
      } else if source == "rewind" {
        let recent = try await RewindDatabase.shared.getRecentScreenshots(limit: 6)
        frames = recent.map { QuickLookFrame(screenshot: $0) }
        subject = "rewind"
      } else {
        let rawConversationId = params["conversationId"]?
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawConversationId, !rawConversationId.isEmpty else {
          return ["error": "missing conversationId"]
        }
        let set = try await APIClient.shared.getConversationScreenFrames(
          conversationID: rawConversationId)
        let ordered = (set.banner.map { [$0] } ?? []) + set.strip
        frames = ordered.compactMap { QuickLookFrame(frame: $0) }
        subject = rawConversationId
      }
      guard let first = frames.first else {
        return ["error": "no_frames", "conversation_id": subject]
      }
      await MainActor.run {
        ScreenFrameQuickLook.shared.present(frames, startingAt: first.id)
      }
      // `present` fetches the clicked frame before it shows anything, so the panel is not up the
      // instant this returns. Poll rather than sleep a guessed interval.
      // Both conditions, not just visibility: an ordered-out panel can still report itself visible
      // while its data source is gone, so polling on `panel_visible` alone returns the *previous*
      // presentation's window and reads zero ready items off the new one.
      for _ in 0..<40 {
        let state = await MainActor.run { ScreenFrameQuickLook.shared.probeState() }
        if state["panel_visible"] == "true", state["panel_controlled"] == "true",
          state["ready_count"] != "0"
        {
          break
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      var result = await MainActor.run { ScreenFrameQuickLook.shared.probeState() }
      result["conversation_id"] = subject
      result["source"] = source
      result["requested_count"] = "\(frames.count)"
      return result
    }

    register(
      name: "conversation_share_probe",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Hermetic share affordance probe — fetches share link without clipboard",
      params: ["conversationId"]
    ) { params in
      let rawConversationId = params["conversationId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let rawConversationId, !rawConversationId.isEmpty else {
        return ["error": "missing conversationId"]
      }
      let conversationId: String
      if rawConversationId == "latest" {
        guard let appState = AppState.current else {
          return ["error": "app state unavailable"]
        }
        if appState.conversations.isEmpty {
          await appState.refreshConversations()
        }
        guard let latestId = appState.conversations.first?.id else {
          return ["error": "no conversations available"]
        }
        conversationId = latestId
      } else {
        conversationId = rawConversationId
      }
      let shareURL = try await APIClient.shared.getConversationShareLink(id: conversationId)
      let shareAvailable = !shareURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      return [
        "conversation_id": conversationId,
        "share_available": shareAvailable ? "true" : "false",
        "share_url_present": shareAvailable ? "true" : "false",
      ]
    }

    // SET-02: assemble the exact payload FeedbackView.submitFeedback() would
    // record — the report title plus a redacted incident diagnostics attachment —
    // without any cloud submission. The dry-run uses the same builders as the
    // real submit path, so a harness can secret-scan the attachment and cannot
    // drift toward a raw-log upload.
    register(
      name: "dump_feedback_payload_dryrun",
      effects: [.localArtifact],
      summary:
        "Assemble the feedback report payload (title + redacted desktop_diagnostics.json) without submitting anywhere; returns the diagnostics JSON for secret-scanning. Non-prod only.",
      params: ["message"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "dump_feedback_payload_dryrun is disabled on production bundles"]
      }
      let message = (params["message"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      var detail: [String: String] = [
        "report_title": feedbackReportTitle(for: message),
        "diagnostics_filename": feedbackDiagnosticsAttachmentFilename,
        "cloud_submission_invoked": "false",
        "would_submit_to_cloud": "false",
      ]

      if let url = DesktopDiagnosticsManager.shared.writeIncidentDiagnosticsAttachment(
        area: "other",
        failureClass: "user_report",
        phase: "other"
      ) {
        defer { try? FileManager.default.removeItem(at: url) }
        if let data = try? Data(contentsOf: url), let json = String(data: data, encoding: .utf8) {
          detail["diagnostics_json"] = json
          detail["diagnostics_byte_count"] = "\(data.count)"
        } else {
          detail["diagnostics_error"] = "unreadable_attachment"
        }
      } else {
        detail["diagnostics_error"] = "attachment_write_failed"
      }
      return detail
    }

    // Deliberately wedge the main thread for durationMs so harnesses can prove the
    // `/state` fallback: the bridge must keep answering `/state` from the cached
    // snapshot (snapshotStale=true) while the MainActor is blocked, instead of
    // hanging as it did when a sign-in Keychain read wedged the main thread. The
    // sleep is scheduled async so this action's own response returns first; the
    // wedge then races the next `/state` live refresh. Non-prod only; mirrors
    // `suspend_agent_stream`'s role for the agent-stall path.
    register(
      name: "debug_block_main_thread",
      effects: [.localState],
      summary: "Block the main thread for durationMs to exercise the /state wedged-MainActor fallback. Non-prod only.",
      params: ["durationMs"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "debug_block_main_thread is disabled on production bundles"]
      }
      let durationMs = min(max(intParam(params["durationMs"], default: 5000), 100), 20000)
      // Delay the wedge briefly so this action's own POST /action response (which
      // itself builds a live snapshot via a MainActor hop) returns *before* the
      // main thread blocks — otherwise the response would be queued behind the
      // sleep and take the full 3s /state fallback, which looks like a hang.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        Thread.sleep(forTimeInterval: Double(durationMs) / 1000.0)
      }
      return ["blocking_main_thread_ms": "\(durationMs)"]
    }

    // AUTH-03: force the stored idToken's expiry into the past through AuthService's own
    // storage abstraction, so a harness can relaunch and prove the app REFRESHES an
    // expired token without signing the user out. The old harness trick
    // (`defaults write <bundle> auth_tokenExpiry -float 1000`) tampers a key the app no
    // longer reads now that tokens are keychain-backed — it measured nothing and reported
    // a false regression. This seam is storage-agnostic and never exposes token material.
    // Non-prod only (double-gated: here and inside AuthService).
    register(
      name: "expire_auth_token",
      effects: [.localState],
      summary:
        "Expire the stored idToken via AuthService's real storage path (keychain or UserDefaults) so a relaunch must refresh it without signing out — AUTH-03. Status only, no token material. Non-prod only.",
      params: []
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "expire_auth_token is disabled on production bundles"]
      }
      return await MainActor.run { AuthService.shared.expireStoredTokenForAutomation() }
    }

    // AUTH-03 read-back: which backend actually holds the tokens, and is the stored
    // idToken currently expired? Lets a harness assert "expired -> relaunch -> refreshed,
    // still signed in" against the REAL storage rather than a UserDefaults key the app may
    // no longer use. Presence/expiry booleans only — never token material. Non-prod only.
    register(
      name: "auth_token_status",
      effects: [],
      summary:
        "Read-only auth token status (signed_in, storage backend, has_id_token, has_refresh_token, is_token_expired) — AUTH-03. No token material. Non-prod only.",
      params: []
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "auth_token_status is disabled on production bundles"]
      }
      return await MainActor.run { AuthService.shared.tokenStatusForAutomation() }
    }

    // CHAT-07: post `NSWorkspace.didWakeNotification` on the WORKSPACE notification
    // center — the top of the real wake chain. Every production consumer then fires
    // exactly as on a physical wake: RealtimeHubController re-warms/defers its
    // session ("system_wake"), and AppState's observer re-broadcasts the
    // default-center `.systemDidWake` for downstream consumers. (Posting only the
    // default-center `.systemDidWake` would MISS RealtimeHub, which observes the
    // workspace center directly.) Transcription restart stays guarded by
    // wasTranscribingBeforeSleep, so a synthetic wake is a safe no-op there.
    // Read-only with respect to user data; non-prod only.
    register(
      name: "simulate_system_wake",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary:
        "Post NSWorkspace.didWakeNotification on the workspace center (the top of the real wake chain: RealtimeHub re-warm + AppState .systemDidWake re-broadcast) so post-wake restart paths run without a real sleep — CHAT-07 harness. Non-prod only.",
      params: []
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "simulate_system_wake is disabled on production bundles"]
      }
      await MainActor.run {
        NSWorkspace.shared.notificationCenter.post(
          name: NSWorkspace.didWakeNotification, object: nil)
      }
      log("DesktopAutomationBridge: simulate_system_wake posted NSWorkspace.didWakeNotification")
      return ["posted": "NSWorkspace.didWakeNotification"]
    }

    // PERM-06: trigger the permission-flow "Quit & Reopen" restart — the exact
    // AppState.restartApp() path used after granting Accessibility / Screen
    // Recording — so a harness can prove the SAME bundle relaunches with the
    // session intact. Distinct from `reset_onboarding`, which mutates onboarding
    // state. The restart is scheduled after a short delay so this action's HTTP
    // response flushes before restartApp() terminates the process. Non-prod only.
    register(
      name: "quit_and_reopen",
      effects: [.localState],
      summary:
        "Trigger the permission-flow Quit & Reopen restart (AppState.restartApp) — relaunches the same bundle; auth/onboarding session persists. Non-prod only.",
      params: ["delayMs"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "quit_and_reopen is disabled on production bundles"]
      }
      guard let appState = AppState.current else {
        return ["error": "app state unavailable"]
      }
      if UpdaterViewModel.isUpdateInProgress {
        return ["error": "sparkle update in progress — restart is deferred to Sparkle"]
      }
      let bundleId = Bundle.main.bundleIdentifier ?? ""
      let relaunchPath = Bundle.main.bundleURL.path
      let delayMs = min(max(intParam(params["delayMs"], default: 400), 100), 5000)
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(delayMs) / 1000.0) {
        appState.restartApp()
      }
      return [
        "restarting": "true",
        "bundle_id": bundleId,
        "relaunch_path": relaunchPath,
        "delay_ms": "\(delayMs)",
      ]
    }
  }
}

/// Coerce a string param ("true"/"1"/"yes") into a Bool, falling back when absent.
func boolParam(_ raw: String?, default fallback: Bool) -> Bool {
  guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
    return fallback
  }
  return ["1", "true", "yes", "on"].contains(raw)
}

private func intParam(_ raw: String?, default fallback: Int) -> Int {
  guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
    return fallback
  }
  return Int(raw) ?? fallback
}

final class DesktopAutomationBridge: @unchecked Sendable {
  static let shared = DesktopAutomationBridge()

  private let queue = DispatchQueue(label: "com.omi.desktop.automation-bridge")
  private var listener: NWListener?
  private var bindAttempts = 0
  private let maxBindAttempts = 3

  /// Upper bound on a request body's declared Content-Length. Requests over this
  /// are rejected before the body is sliced (see parseRequest); the automation
  /// bridge only ever receives small JSON action payloads.
  static let maxRequestBodyBytes = 8 * 1024 * 1024

  private init() {}

  func startIfNeeded() {
    guard DesktopAutomationLaunchOptions.isEnabled else { return }
    guard listener == nil else { return }
    bindAttempts = 0
    attemptStartListener()
  }

  private func attemptStartListener() {
    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      guard let port = NWEndpoint.Port(rawValue: DesktopAutomationLaunchOptions.port) else {
        log("DesktopAutomationBridge: invalid port \(DesktopAutomationLaunchOptions.port)")
        return
      }
      guard let loopback = IPv4Address("127.0.0.1") else {
        log("DesktopAutomationBridge: failed to resolve loopback address")
        return
      }
      parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(loopback), port: port)

      let listener = try NWListener(using: parameters)
      listener.newConnectionHandler = { [weak self] connection in
        self?.handleConnection(connection)
      }
      listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
        log("DesktopAutomationBridge: listener state changed to \(String(describing: state))")
        if case .failed(let error) = state {
          self?.handleListenerBindFailure(error: error)
        }
      }
      listener.start(queue: queue)
      self.listener = listener
      bindAttempts = 0
      DesktopAutomationLaunchOptions.writeTokenFileIfNeeded()
      Task { @MainActor in DesktopAutomationActionRegistry.shared.registerBuiltins() }
      log(
        "DesktopAutomationBridge: listening on http://127.0.0.1:\(DesktopAutomationLaunchOptions.port)"
      )
    } catch {
      handleListenerBindFailure(error: error)
    }
  }

  private func handleListenerBindFailure(error: Error) {
    listener?.cancel()
    listener = nil
    bindAttempts += 1
    let reason = error.localizedDescription
    if bindAttempts < maxBindAttempts {
      log(
        "DesktopAutomationBridge: bind failed (attempt \(bindAttempts)/\(maxBindAttempts)), retrying: \(reason)")
      queue.asyncAfter(deadline: .now() + Double(bindAttempts)) { [weak self] in
        self?.attemptStartListener()
      }
      return
    }
    log(
      "DesktopAutomationBridge: bind failed after \(maxBindAttempts) attempts "
        + "(failure_class=bind_failed recovery_action=retry_exhausted recovery_result=exhausted): \(reason)")
    logError("DesktopAutomationBridge: failed to start listener", error: error)
    DesktopDiagnosticsManager.shared.recordAutomationBridgeBindFailed(
      port: Int(DesktopAutomationLaunchOptions.port),
      reason: reason
    )
  }

  private func handleConnection(_ connection: NWConnection) {
    connection.start(queue: queue)
    receiveRequest(on: connection, buffer: Data())
  }

  private func receiveRequest(on connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }

      if let error {
        self.sendError(
          "receive_failed: \(error.localizedDescription)", statusCode: 500, on: connection)
        return
      }

      var accumulated = buffer
      if let data {
        accumulated.append(data)
      }

      if let request = self.parseRequest(from: accumulated) {
        Task {
          let response = await self.route(request: request)
          self.send(response, on: connection)
        }
        return
      }

      if isComplete {
        self.sendError("incomplete_request", statusCode: 400, on: connection)
        return
      }

      self.receiveRequest(on: connection, buffer: accumulated)
    }
  }

  private func parseRequest(from data: Data) -> DesktopAutomationHTTPRequest? {
    guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
      return nil
    }

    let headerData = data[..<headerRange.lowerBound]
    guard let headerString = String(data: headerData, encoding: .utf8) else {
      return nil
    }

    let lines = headerString.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else { return nil }
    let requestParts = requestLine.split(separator: " ")
    guard requestParts.count >= 2 else { return nil }

    let method = String(requestParts[0])
    let path = String(requestParts[1])

    var headers: [String: String] = [:]
    var contentLength = 0
    for line in lines.dropFirst() {
      let pieces = line.split(separator: ":", maxSplits: 1)
      guard pieces.count == 2 else { continue }
      let key = pieces[0].trimmingCharacters(in: .whitespaces).lowercased()
      let value = pieces[1].trimmingCharacters(in: .whitespaces)
      headers[key] = value
      if key == "content-length" {
        // Reject negative/absurd lengths before the body-slice range and the
        // `distance + contentLength` addition below (which would trap/overflow).
        // Reachable pre-auth from any local process, so fail closed.
        guard
          let parsed = LoopbackHTTPParsing.parseContentLength(value, maxBytes: Self.maxRequestBodyBytes)
        else {
          return nil
        }
        contentLength = parsed
      }
    }

    let bodyStart = headerRange.upperBound
    let expectedLength = data.distance(from: data.startIndex, to: bodyStart) + contentLength
    guard data.count >= expectedLength else {
      return nil
    }

    let body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: contentLength)])
    return DesktopAutomationHTTPRequest(method: method, path: path, headers: headers, body: body)
  }

  /// Parse a `POST /action` body: `{ "name": "...", "params": { "k": "v", ... } }`.
  /// Param values are coerced to strings (bools → "true"/"false", numbers → digits)
  /// so callers can send natural JSON types.
  private func parseActionRequest(from body: Data) -> (name: String, params: [String: String], readOnly: Bool)? {
    guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let name = object["name"] as? String, !name.isEmpty
    else {
      return nil
    }

    var readOnly = false
    if let raw = object["readOnly"] {
      guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
      readOnly = value.boolValue
    }
    var params: [String: String] = [:]
    if let raw = object["params"] as? [String: Any] {
      for (key, value) in raw {
        if let string = value as? String {
          params[key] = string
        } else if let number = value as? NSNumber {
          if CFGetTypeID(number) == CFBooleanGetTypeID() {
            params[key] = number.boolValue ? "true" : "false"
          } else {
            params[key] = number.stringValue
          }
        } else {
          params[key] = String(describing: value)
        }
      }
    }
    return (name, params, readOnly)
  }

  private func route(request: DesktopAutomationHTTPRequest) async -> DesktopAutomationHTTPResponse {
    let started = DispatchTime.now().uptimeNanoseconds
    let response = await self.response(for: request)
    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    await DesktopAutomationTraceStore.shared.record(
      method: request.method,
      path: request.path,
      statusCode: response.statusCode,
      durationMs: (elapsedMs * 100).rounded() / 100
    )
    return response
  }

  /// Internal executable route seam used by both the loopback listener and
  /// behavioral tests. Keeping auth, dispatch, and JSON encoding on this path
  /// prevents tests from validating a parallel fake router.
  func response(for request: DesktopAutomationHTTPRequest) async -> DesktopAutomationHTTPResponse {
    guard acceptsLoopbackHostAndOrigin(request.headers) else {
      return jsonResponse(
        DesktopAutomationResponse<DesktopAutomationSnapshot>(
          ok: false, result: nil, error: "invalid_host_or_origin"),
        statusCode: 403)
    }
    if request.method == "GET", request.path == "/health", request.headers["authorization"] == nil {
      return jsonResponse(
        DesktopAutomationHealth(
          ok: true,
          name: "omi-desktop-automation",
          bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
          sourceIdentity: DesktopBuildIdentity.current,
          processID: getpid(),
          logFilePath: omiLogFilePath(),
          logLaunchID: omiLogLaunchID(),
          bridgePort: DesktopAutomationLaunchOptions.port,
          requiresAuth: true,
          backendEnvironment: DesktopBackendEnvironment.shouldUseDevelopmentBackends ? "development" : "production",
          pythonBackendURL: DesktopBackendEnvironment.pythonBaseURL(),
          rustBackendURL: DesktopBackendEnvironment.rustBackendURL()
        )
      )
    }
    guard authenticate(request.headers["authorization"]) else {
      return jsonResponse(
        DesktopAutomationResponse<DesktopAutomationSnapshot>(
          ok: false, result: nil, error: "invalid_or_missing_automation_token"),
        statusCode: 401)
    }

    switch (request.method, request.path) {
    case ("GET", "/health"):
      let snapshot = await cachedAutomationSnapshot()
      return jsonResponse(DesktopAutomationResponse(ok: true, result: snapshot, error: nil))
    case ("GET", "/state"):
      let snapshot = await liveAutomationSnapshot()
      return jsonResponse(DesktopAutomationResponse(ok: true, result: snapshot, error: nil))
    case ("GET", "/traces/recent"):
      let traces = await DesktopAutomationTraceStore.shared.recent()
      return jsonResponse(DesktopAutomationResponse(ok: true, result: traces, error: nil))
    case ("POST", "/traces/clear"):
      await DesktopAutomationTraceStore.shared.clear()
      return jsonResponse(DesktopAutomationResponse(ok: true, result: "cleared", error: nil))
    case ("POST", "/navigate"):
      do {
        let payload = try JSONDecoder().decode(
          DesktopAutomationNavigationRequest.self, from: request.body)
        try await dispatchNavigation(payload)
        let snapshot = try await navigationSnapshot(for: payload)
        try await sleepForAutomationSettle(payload.settleMs)
        return jsonResponse(DesktopAutomationResponse(ok: true, result: snapshot, error: nil))
      } catch {
        return jsonResponse(
          DesktopAutomationResponse<DesktopAutomationSnapshot>(
            ok: false,
            result: nil,
            error: error.localizedDescription
          ),
          statusCode: 400
        )
      }
    case ("POST", "/conversation/open"):
      do {
        let payload = try JSONDecoder().decode(
          DesktopAutomationOpenConversationRequest.self, from: request.body)
        try await dispatchOpenConversation(payload)
        try await sleepForAutomationSettle(payload.settleMs)
        let snapshot = await cachedAutomationSnapshot()
        return jsonResponse(DesktopAutomationResponse(ok: true, result: snapshot, error: nil))
      } catch {
        return jsonResponse(
          DesktopAutomationResponse<DesktopAutomationSnapshot>(
            ok: false,
            result: nil,
            error: error.localizedDescription
          ),
          statusCode: 400
        )
      }
    case ("POST", "/execute-export"):
      struct ExecResult: Codable { let taskTitle: String }
      do {
        let payload = try JSONDecoder().decode(
          DesktopAutomationExecuteExportRequest.self, from: request.body)
        guard let destination = MemoryExportDestination(rawValue: payload.destination) else {
          return jsonResponse(
            DesktopAutomationResponse<ExecResult>(
              ok: false, result: nil, error: "unknown destination: \(payload.destination)"),
            statusCode: 400)
        }
        let outcome = try await MemoryExportExecutor.run(destination)
        return jsonResponse(
          DesktopAutomationResponse(
            ok: true, result: ExecResult(taskTitle: outcome.taskTitle), error: nil))
      } catch {
        return jsonResponse(
          DesktopAutomationResponse<ExecResult>(
            ok: false, result: nil, error: error.localizedDescription),
          statusCode: 500)
      }
    case ("GET", "/actions"):
      let descriptors = await DesktopAutomationActionRegistry.shared.descriptors()
      return jsonResponse(DesktopAutomationResponse(ok: true, result: descriptors, error: nil))
    case ("GET", "/capabilities"):
      let descriptors = await DesktopAutomationActionRegistry.shared.descriptors()
      let capabilities = DesktopAutomationCapabilities(
        schemaVersion: 2,
        routes: [
          "GET /health",
          "GET /state",
          "GET /capabilities",
          "GET /actions",
          "GET /traces/recent",
          "POST /traces/clear",
          "POST /navigate",
          "POST /conversation/open",
          "POST /action",
          "POST /visual/export",
        ] + DesktopAutomationPresentationRoute.allCases.map(\.capability),
        lanes: ["bridge", "visual", "ui"],
        waits: ["state", "log", "trace"],
        assertions: ["state", "log", "trace", "ax"],
        artifactTypes: ["state", "bridge_response", "visual_png", "logs", "traces", "summary"],
        actions: descriptors
      )
      return jsonResponse(DesktopAutomationResponse(ok: true, result: capabilities, error: nil))
    case ("POST", "/action"):
      guard let parsed = parseActionRequest(from: request.body) else {
        return jsonResponse(
          DesktopAutomationResponse<DesktopAutomationActionResult>(
            ok: false, result: nil, error: "invalid_action_request"),
          statusCode: 400
        )
      }
      do {
        let detail = try await DesktopAutomationActionRegistry.shared.perform(
          parsed.name, params: parsed.params, readOnly: parsed.readOnly)
        try await sleepForAutomationSettle(intParam(parsed.params["settleMs"], default: 0))
        let snapshot = await liveAutomationSnapshot()
        let result = DesktopAutomationActionResult(
          action: parsed.name, detail: detail, state: snapshot)
        return jsonResponse(DesktopAutomationResponse(ok: true, result: result, error: nil))
      } catch {
        return jsonResponse(
          DesktopAutomationResponse<DesktopAutomationActionResult>(
            ok: false, result: nil, error: automationActionErrorDescription(error)),
          statusCode: 400
        )
      }
    case ("POST", "/visual/export"):
      do {
        let payload = try JSONDecoder().decode(
          DesktopAutomationVisualExportRequest.self, from: request.body)
        let result = try await exportWindow(payload)
        return jsonResponse(DesktopAutomationResponse(ok: true, result: result, error: nil))
      } catch {
        return jsonResponse(
          DesktopAutomationResponse<DesktopAutomationVisualExportResult>(
            ok: false, result: nil, error: error.localizedDescription),
          statusCode: 500
        )
      }
    case ("POST", let path) where path == DesktopAutomationPresentationRoute.openExport.rawValue:
      struct OpenResult: Codable {
        let destination: String
        let generation: UInt64
      }
      guard
        let payload = try? JSONDecoder().decode(
          DesktopAutomationExecuteExportRequest.self, from: request.body)
      else {
        return jsonResponse(
          DesktopAutomationResponse<OpenResult>(
            ok: false, result: nil, error: "invalid_request"),
          statusCode: 400)
      }
      let gate = await currentAutomationPresentationGate()
      let outcome = await DesktopAutomationPresentationRequestHandler.shared.openExport(
        identifier: payload.destination,
        knownIdentifiers: Set(MemoryExportDestination.allCases.map(\.rawValue)),
        gate: gate
      )
      guard let command = outcome.command else {
        return jsonResponse(
          DesktopAutomationResponse<OpenResult>(
            ok: false, result: nil, error: outcome.errorCode),
          statusCode: outcome.statusCode)
      }
      return jsonResponse(
        DesktopAutomationResponse(
          ok: true,
          result: OpenResult(
            destination: payload.destination,
            generation: command.generation
          ),
          error: nil
        ))
    case ("POST", let path) where path == DesktopAutomationPresentationRoute.openImport.rawValue:
      struct OpenResult: Codable {
        let connector: String
        let generation: UInt64
      }
      guard
        let payload = try? JSONDecoder().decode(
          DesktopAutomationOpenImportRequest.self, from: request.body)
      else {
        return jsonResponse(
          DesktopAutomationResponse<OpenResult>(
            ok: false, result: nil, error: "invalid_request"),
          statusCode: 400)
      }
      let knownIDs = await MainActor.run { ImportConnector.all.map(\.id) }
      let gate = await currentAutomationPresentationGate()
      let outcome = await DesktopAutomationPresentationRequestHandler.shared.openImport(
        identifier: payload.connector,
        knownIdentifiers: Set(knownIDs),
        gate: gate
      )
      guard let command = outcome.command else {
        return jsonResponse(
          DesktopAutomationResponse<OpenResult>(
            ok: false, result: nil, error: outcome.errorCode),
          statusCode: outcome.statusCode)
      }
      return jsonResponse(
        DesktopAutomationResponse(
          ok: true,
          result: OpenResult(
            connector: payload.connector,
            generation: command.generation
          ),
          error: nil
        ))
    case ("POST", "/gmail-read"):
      struct RemovedRoute: Codable {
        let message: String
        let replacement: String
      }
      return jsonResponse(
        DesktopAutomationResponse(
          ok: false,
          result: RemovedRoute(
            message:
              "The legacy Gmail import route was removed because automation responses must not expose email contents or trigger memory writes.",
            replacement: "Use POST /action with gmail_read_probe for privacy-safe Gmail status checks."
          ),
          error: "gmail_read_removed"
        ),
        statusCode: 410
      )
    default:
      return jsonResponse(
        DesktopAutomationResponse<DesktopAutomationSnapshot>(
          ok: false,
          result: nil,
          error: "unsupported_route"
        ),
        statusCode: 404
      )
    }
  }

  private func dispatchNavigation(_ payload: DesktopAutomationNavigationRequest) async throws {
    let activateApp = DesktopAutomationNavigationDelivery.resolvesActivation(
      explicit: payload.activateApp)
    await activateMainWindowIfNeeded(activateApp)
    await MainActor.run {
      NotificationCenter.default.post(
        name: .desktopAutomationNavigateRequested,
        object: nil,
        userInfo: DesktopAutomationNavigationDelivery.userInfo(
          for: payload,
          activateApp: activateApp)
      )
    }
  }

  @MainActor
  private func currentAutomationPresentationGate() -> DesktopAutomationPresentationGate {
    let authState = AuthState.shared
    if authState.isRestoringAuth {
      return .presentationUnavailable
    }
    guard authState.isSignedIn else {
      return .signedOut
    }
    guard let appState = AppState.current else {
      return .presentationUnavailable
    }
    return appState.hasCompletedOnboarding ? .ready : .onboardingIncomplete
  }

  private func dispatchOpenConversation(_ payload: DesktopAutomationOpenConversationRequest) async throws {
    await activateMainWindowIfNeeded(
      DesktopAutomationNavigationDelivery.resolvesActivation(explicit: payload.activateApp))
    try await ensureConversationsTabVisibleForAutomation()
    await requestAutomationConversationOpen(
      conversationId: payload.conversationId,
      showTranscript: payload.showTranscript ?? false
    )
  }

  private func activateMainWindowIfNeeded(_ activateApp: Bool) async {
    guard activateApp else { return }
    await MainActor.run {
      NSApp.activate()
      if let window = NSApp.windows.first(where: { $0.title.lowercased().hasPrefix("omi") }) {
        window.makeKeyAndOrderFront(nil)
      }
    }
  }

  private func sleepForAutomationSettle(_ milliseconds: Int?) async throws {
    let clamped = max(0, min(milliseconds ?? 0, 5_000))
    guard clamped > 0 else { return }
    try await Task.sleep(for: .milliseconds(clamped))
  }

  private func exportWindow(
    _ payload: DesktopAutomationVisualExportRequest
  ) async throws -> DesktopAutomationVisualExportResult {
    try await MainActor.run {
      let fileManager = FileManager.default
      let url = URL(fileURLWithPath: payload.path).standardizedFileURL
      let captureRoot = DesktopAutomationLaunchOptions.captureRoot.resolvingSymlinksInPath()
      try fileManager.createDirectory(at: captureRoot, withIntermediateDirectories: true)
      let parent = url.deletingLastPathComponent()
      let resolvedParent = parent.resolvingSymlinksInPath()
      let resolvedURL = resolvedParent.appendingPathComponent(url.lastPathComponent)
      guard resolvedURL.path == captureRoot.path || resolvedURL.path.hasPrefix(captureRoot.path + "/") else {
        throw DesktopAutomationActionError.invalidParams(
          "visual export path must be under \(captureRoot.path)")
      }
      if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
        values.isSymbolicLink == true
      {
        throw DesktopAutomationActionError.invalidParams("visual export path must not be a symlink")
      }
      try fileManager.createDirectory(
        at: parent, withIntermediateDirectories: true)
      let postCreateParent = parent.resolvingSymlinksInPath()
      let writeURL = postCreateParent.appendingPathComponent(url.lastPathComponent)
      guard writeURL.path == captureRoot.path || writeURL.path.hasPrefix(captureRoot.path + "/") else {
        throw DesktopAutomationActionError.invalidParams(
          "visual export path must be under \(captureRoot.path)")
      }

      let window: NSWindow?
      if payload.target == "overlay" {
        window = CloudConnectorGuidanceOverlay.shared.automationWindow
      } else if payload.target == "task_thread" {
        window = NSApp.windows.first(where: { $0.title == "Omi — Task thread scenario" && $0.isVisible })
      } else {
        window = NSApp.windows.first(where: { window in
          window.title.lowercased().hasPrefix("omi") || window.isMainWindow || window.isKeyWindow
        })
      }

      guard
        let window,
        let contentView = window.contentView
      else {
        throw DesktopAutomationActionError.invalidParams("\(payload.target ?? "main") window not available")
      }

      contentView.needsLayout = true
      contentView.layoutSubtreeIfNeeded()

      let bounds = contentView.bounds
      guard !bounds.isEmpty,
        let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds)
      else {
        throw DesktopAutomationActionError.invalidParams("\(payload.target ?? "main") window has no renderable content")
      }

      contentView.cacheDisplay(in: bounds, to: bitmap)
      guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw DesktopAutomationActionError.invalidParams("failed to encode png")
      }

      try pngData.write(to: writeURL, options: [.atomic])
      return DesktopAutomationVisualExportResult(
        path: writeURL.path,
        width: bitmap.pixelsWide,
        height: bitmap.pixelsHigh
      )
    }
  }

  private func acceptsLoopbackHostAndOrigin(_ headers: [String: String]) -> Bool {
    if let host = headers["host"], !isAllowedLoopbackHost(host) {
      return false
    }
    if let origin = headers["origin"], !origin.isEmpty {
      guard let url = URL(string: origin), let host = url.host, let port = url.port else {
        return false
      }
      guard url.scheme == "http" || url.scheme == "https", port == Int(DesktopAutomationLaunchOptions.port) else {
        return false
      }
      guard host == "127.0.0.1" || host == "localhost" || host == "[::1]" || host == "::1" else {
        return false
      }
    }
    return true
  }

  private func isAllowedLoopbackHost(_ hostHeader: String) -> Bool {
    let value = hostHeader.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let allowed = [
      "127.0.0.1:\(DesktopAutomationLaunchOptions.port)",
      "localhost:\(DesktopAutomationLaunchOptions.port)",
      "[::1]:\(DesktopAutomationLaunchOptions.port)",
    ]
    return allowed.contains(value)
  }

  private func authenticate(_ authorization: String?) -> Bool {
    guard let authorization else {
      return false
    }
    let supplied: String
    if authorization.lowercased().hasPrefix("bearer ") {
      supplied = String(authorization.dropFirst(7))
    } else {
      supplied = authorization
    }
    return constantTimeEquals(supplied, DesktopAutomationLaunchOptions.token)
  }

  private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    var diff = left.count ^ right.count
    for index in 0..<max(left.count, right.count) {
      let a = index < left.count ? left[index] : 0
      let b = index < right.count ? right[index] : 0
      diff |= Int(a ^ b)
    }
    return diff == 0
  }

  private func jsonResponse<T: Codable>(
    _ payload: T,
    statusCode: Int = 200
  ) -> DesktopAutomationHTTPResponse {
    do {
      let body = try JSONEncoder.pretty.encode(payload)
      return DesktopAutomationHTTPResponse(
        statusCode: statusCode,
        headers: ["Content-Type": "application/json"],
        body: body
      )
    } catch {
      let fallback = Data("{\"ok\":false,\"error\":\"encode_failed\"}".utf8)
      return DesktopAutomationHTTPResponse(
        statusCode: 500,
        headers: ["Content-Type": "application/json"],
        body: fallback
      )
    }
  }

  private func sendError(_ message: String, statusCode: Int, on connection: NWConnection) {
    let response = jsonResponse(
      DesktopAutomationResponse<DesktopAutomationSnapshot>(ok: false, result: nil, error: message),
      statusCode: statusCode
    )
    send(response, on: connection)
  }

  private func send(_ response: DesktopAutomationHTTPResponse, on connection: NWConnection) {
    connection.send(
      content: response.serializedHTTP1Data(),
      completion: .contentProcessed { _ in
        connection.cancel()
      })
  }
}

struct DesktopAutomationHTTPRequest {
  let method: String
  let path: String
  let headers: [String: String]
  let body: Data
}

struct DesktopAutomationHTTPResponse {
  let statusCode: Int
  let headers: [String: String]
  let body: Data

  func serializedHTTP1Data() -> Data {
    var headerLines = [
      "HTTP/1.1 \(statusCode) \(Self.reasonPhrase(for: statusCode))",
      "Content-Length: \(body.count)",
      "Connection: close",
    ]
    for (key, value) in headers {
      headerLines.append("\(key): \(value)")
    }
    headerLines.append("")
    headerLines.append("")

    var data = Data(headerLines.joined(separator: "\r\n").utf8)
    data.append(body)
    return data
  }

  private static func reasonPhrase(for statusCode: Int) -> String {
    switch statusCode {
    case 200: return "OK"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 403: return "Forbidden"
    case 404: return "Not Found"
    case 409: return "Conflict"
    case 410: return "Gone"
    case 500: return "Internal Server Error"
    case 503: return "Service Unavailable"
    case 504: return "Gateway Timeout"
    default: return "Unknown Status"
    }
  }
}

extension JSONEncoder {
  fileprivate static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
