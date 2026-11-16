import XCTest

@testable import Omi_Computer

final class MeetingCopilotPromptTests: XCTestCase {
  func testParseSegueOFiltroDoAtticus() {
    XCTAssertEqual(MeetingCopilotPrompt.parse("SKIP")?.kind, "SKIP")
    XCTAssertEqual(MeetingCopilotPrompt.parse("UNSURE\nFalta o preço")?.reason, "Falta o preço")
    let answer = MeetingCopilotPrompt.parse("ANSWER\n**Sai em março.**\nBrief: prazo combinado\nterceira\nquarta")
    XCTAssertEqual(answer?.kind, "answer")
    XCTAssertEqual(answer?.lines, ["Sai em março.", "Brief: prazo combinado", "terceira"])
    XCTAssertEqual(MeetingCopilotPrompt.parse("GENERAL\nÉ 42.")?.general, true)
    XCTAssertNil(MeetingCopilotPrompt.parse("  \n"))
  }

  func testRequestUsaSoOsUltimosTresMinutos() {
    let now = Date()
    let lines = [
      MeetingCopilotPrompt.Line(at: now.addingTimeInterval(-400), mine: false, text: "antigo"),
      MeetingCopilotPrompt.Line(at: now.addingTimeInterval(-30), mine: true, text: "recente"),
    ]
    let text = MeetingCopilotPrompt.request(
      question: "Quando sai?", brief: "b", transcript: lines, manual: false, now: now)
    XCTAssertFalse(text.contains("antigo"))
    XCTAssertTrue(text.contains("[30s ago] You: recente"))
    XCTAssertTrue(text.hasSuffix("Mode: automatic candidate."))
    XCTAssertTrue(MeetingCopilotPrompt.isCandidate("Qual é o prazo?"))
    XCTAssertFalse(MeetingCopilotPrompt.isCandidate("Tudo bem."))
  }
}
