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

  func testAtalhosEmInglesViramPortugues() {
    XCTAssertEqual(MeetingCopilotPrompt.portuguese("What did I miss?"), MeetingCopilotPrompt.catchUp)
    XCTAssertEqual(
      MeetingCopilotPrompt.portuguese("Explain what is on the shared screen."), MeetingCopilotPrompt.explainScreen)
    XCTAssertEqual(
      MeetingCopilotPrompt.portuguese("Context: a fala\nQuestion: e o prazo?"), "Contexto: a fala\nPergunta: e o prazo?")
    XCTAssertEqual(MeetingCopilotPrompt.portuguese("Quando sai?"), "Quando sai?")
    let now = Date()
    let text = MeetingCopilotPrompt.request(
      question: "Qual o preço?", brief: "",
      transcript: [.init(at: now.addingTimeInterval(-10), mine: false, text: "Qual o preço?", who: "Sofia")],
      manual: false, now: now)
    XCTAssertTrue(text.contains("[10s ago] Sofia: Qual o preço?"))
  }

  func testServidorAchaAReuniaoDaExtensaoComFalaRecente() {
    let now = MeetingCopilotServer.date("2026-11-17T14:10:00+00:00")!
    let meetings: [[String: Any]] = [
      ["id": "omi", "titulo": "Omi 17/11/2026", "estado": "em_andamento",
       "iniciada_em": "2026-11-17T14:00:00.123456+00:00", "coberto_ate_ms": 590_000],
      ["id": "velha", "titulo": "Coaching", "estado": "em_andamento",
       "iniciada_em": "2026-11-17T12:00:00+00:00", "coberto_ate_ms": 60_000],
      ["id": "agora", "titulo": "Sofia briefing", "estado": "em_andamento",
       "iniciada_em": "2026-11-17T14:06:00.5+00:00", "coberto_ate_ms": 0],
    ]
    XCTAssertEqual(MeetingCopilotServer.active(in: meetings, now: now)?.id, "agora")
    XCTAssertNil(MeetingCopilotServer.active(in: Array(meetings.prefix(2)), now: now))

    let trechos = MeetingCopilotServer.trechos(in: [
      "trechos": [
        ["seq": 0, "inicio_ms": 52, "falante": "Sofia Henriqueto", "texto": "Oi"],
        ["seq": 1, "inicio_ms": 3412, "falante": NSNull(), "texto": "tudo bem?"],
      ]
    ])
    XCTAssertEqual(trechos.map(\.speaker), ["Sofia Henriqueto", nil])
    XCTAssertEqual(trechos.last?.startMs, 3412)
    XCTAssertTrue(MeetingCopilotServer.isMine("gabriel Kashimarki", givenName: "Gabriel"))
    XCTAssertFalse(MeetingCopilotServer.isMine("Sofia Henriqueto", givenName: "Gabriel"))
    XCTAssertFalse(MeetingCopilotServer.isMine("Gabriel", givenName: ""))
    XCTAssertFalse(MeetingCopilotServer.isMine(nil, givenName: "Gabriel"))
  }
}
