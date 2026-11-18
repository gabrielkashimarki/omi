@preconcurrency import GRDB
import XCTest

@testable import Omi_Computer

/// One event recorded by several devices renders as one row (#3244), without
/// ever hiding a conversation whose group has no other loaded member.
final class CaptureGroupPresentationTests: XCTestCase {
  private static func group(primary: String, members: [(String, String)]) -> [String: Any] {
    [
      "id": "event-1", "primary_id": primary, "revision": 2,
      "members": members.map { id, source in
        [
          "id": id, "source": source, "started_at": "2026-09-23T03:17:00Z",
          "finished_at": "2026-09-23T04:19:00Z",
        ]
      },
    ]
  }

  private static func conversation(
    _ id: String, source: String = "omi", group: [String: Any]? = nil
  ) throws -> ServerConversation {
    try ProjectionRenderingFixture.decode {
      $0["id"] = id
      $0["source"] = source
      $0.removeValue(forKey: "client_processing")
      if let group { $0["capture_group"] = group }
    }
  }

  private static var meeting: [String: Any] {
    group(primary: "desktop", members: [("desktop", "desktop"), ("pendant-1", "omi"), ("pendant-2", "omi")])
  }

  func testWireGroupDecodesMembersSourcesAndDates() throws {
    let decoded = try Self.conversation("desktop", source: "desktop", group: Self.meeting)
    let group = try XCTUnwrap(decoded.captureGroup)
    XCTAssertEqual(group.id, "event-1")
    XCTAssertEqual(group.primaryId, "desktop")
    XCTAssertEqual(group.revision, 2)
    XCTAssertEqual(group.members.map(\.source), [.desktop, .omi, .omi])
    XCTAssertEqual(group.members.first?.startedAt, ISO8601DateFormatter().date(from: "2026-09-23T03:17:00Z"))
    XCTAssertNil(try Self.conversation("solo").captureGroup)
  }

  func testGroupCollapsesToPrimaryInListOrder() throws {
    let list = [
      try Self.conversation("pendant-2", group: Self.meeting),
      try Self.conversation("other"),
      try Self.conversation("desktop", source: "desktop", group: Self.meeting),
      try Self.conversation("pendant-1", group: Self.meeting),
    ]
    XCTAssertEqual(CaptureGroupPresentation.collapse(list).map(\.id), ["other", "desktop"])
  }

  func testUnloadedPrimaryFallsBackToFirstLoadedMember() throws {
    let list = [
      try Self.conversation("pendant-1", group: Self.meeting),
      try Self.conversation("pendant-2", group: Self.meeting),
    ]
    XCTAssertEqual(CaptureGroupPresentation.collapse(list).map(\.id), ["pendant-1"])
  }

  func testLoneLoadedMemberIsNeverHidden() throws {
    let list = [try Self.conversation("pendant-1", group: Self.meeting), try Self.conversation("other")]
    XCTAssertEqual(CaptureGroupPresentation.collapse(list).map(\.id), ["pendant-1", "other"])
  }

  func testCacheRoundTripsAndClearsMembership() throws {
    let grouped = try Self.conversation("desktop", source: "desktop", group: Self.meeting)
    var record = TranscriptionSessionRecord.from(grouped)
    XCTAssertEqual(record.toServerConversation(segments: [])?.captureGroup, grouped.captureGroup)

    record.updateFrom(try Self.conversation("desktop", source: "desktop"))
    XCTAssertNil(record.captureGroupJson)
    XCTAssertNil(record.toServerConversation(segments: [])?.captureGroup)
  }

  func testOptimisticMutationKeepsMembership() throws {
    let grouped = try Self.conversation("desktop", source: "desktop", group: Self.meeting)
    var mutation = ConversationPendingMutation()
    mutation.setTitle("Renamed")
    let mutated = ConversationReconciliationPolicy.apply(mutation: mutation, to: grouped)
    XCTAssertEqual(mutated.title, "Renamed")
    XCTAssertEqual(mutated.captureGroup, grouped.captureGroup)
  }

  func testMigrationAddsNullableColumnToLegacyRows() throws {
    let queue = try DatabaseQueue()
    try queue.write { db in
      try db.execute(sql: "CREATE TABLE transcription_sessions (id INTEGER PRIMARY KEY, title TEXT)")
      try db.execute(sql: "INSERT INTO transcription_sessions (id, title) VALUES (1, 'Legacy title')")
    }
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationCaptureGroupMigration(on: &migrator)
    try migrator.migrate(queue)
    try queue.read { db in
      XCTAssertEqual(try String.fetchOne(db, sql: "SELECT title FROM transcription_sessions"), "Legacy title")
      XCTAssertNil(try String.fetchOne(db, sql: "SELECT captureGroupJson FROM transcription_sessions"))
    }
  }

  func testReuniaoDoMeetEscondeAGravacaoDoMacDaMesmaChamada() throws {
    func conversa(_ id: String, _ source: String, _ inicio: String, _ fim: String) throws -> ServerConversation {
      try ProjectionRenderingFixture.decode {
        $0["id"] = id
        $0["source"] = source
        $0["started_at"] = inicio
        $0["finished_at"] = fim
        $0.removeValue(forKey: "client_processing")
      }
    }
    let meet = try conversa("meet", "external_integration", "2026-11-18T12:00:00Z", "2026-11-18T13:00:00Z")
    let mac = try conversa("mac", "desktop", "2026-11-18T12:02:00Z", "2026-11-18T13:01:00Z")
    let maisLonga = try conversa("almoco", "desktop", "2026-11-18T12:30:00Z", "2026-11-18T14:30:00Z")
    let outra = try conversa("tarde", "omi", "2026-11-18T15:00:00Z", "2026-11-18T15:30:00Z")
    XCTAssertEqual(
      CaptureGroupPresentation.collapse([meet, mac, maisLonga, outra]).map(\.id), ["meet", "almoco", "tarde"])
    XCTAssertEqual(CaptureGroupPresentation.collapse([mac, outra]).map(\.id), ["mac", "tarde"])
  }
}
