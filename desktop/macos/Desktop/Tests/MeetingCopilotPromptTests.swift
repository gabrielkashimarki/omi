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

  @MainActor
  func testReunioesDaExtensaoViramConversaComParticipantes() {
    let now = MeetingCopilotServer.date("2026-11-18T20:00:00+00:00")!
    let meetings: [[String: Any]] = [
      ["id": "b", "titulo": "Monduá", "estado": "encerrada",
       "iniciada_em": "2026-11-18T15:00:00+00:00", "encerrada_em": "2026-11-18T16:00:00+00:00"],
      ["id": "a", "titulo": "SPPIC", "estado": "encerrada", "iniciada_em": "2026-11-18T12:00:00.5+00:00"],
      ["id": "omi", "titulo": "Omi 18/11/2026", "estado": "encerrada", "iniciada_em": "2026-11-18T12:00:00+00:00"],
      ["id": "viva", "titulo": "Agora", "estado": "em_andamento", "iniciada_em": "2026-11-18T19:00:00+00:00"],
      ["id": "velha", "titulo": "Outubro", "estado": "encerrada", "iniciada_em": "2026-10-01T12:00:00+00:00"],
      ["id": "feita", "titulo": "Já foi", "estado": "encerrada", "iniciada_em": "2026-11-18T10:00:00+00:00"],
    ]
    let pendentes = ReunioesImportador.pendentes(in: meetings, enviadas: ["feita"], now: now)
    XCTAssertEqual(pendentes.map(\.id), ["a", "b"])
    XCTAssertEqual(pendentes[0].fim, pendentes[0].inicio)

    let trechos: [MeetingCopilotServer.Trecho] = [
      .init(seq: 0, startMs: 0, speaker: "Gabriel Kashimarki", text: "Oi"),
      .init(seq: 1, startMs: 1000, speaker: "Sofia Henriqueto", text: "Oi,"),
      .init(seq: 2, startMs: 2000, speaker: "Sofia Henriqueto", text: "tudo bem?"),
      .init(seq: 3, startMs: 4000, speaker: nil, text: "ruído"),
      .init(seq: 4, startMs: 5000, speaker: "Júlio", text: "Bom dia"),
    ]
    XCTAssertEqual(ReunioesImportador.participantes(trechos, givenName: "Gabriel"), ["Sofia Henriqueto", "Júlio"])
    let pedido = ReunioesImportador.pedido(
      pendentes[1], trechos: trechos, pessoas: [ReunioesImportador.chave("julio"): "p-julio"], pasta: "pasta",
      givenName: "Gabriel")
    let s = pedido.transcript_segments
    XCTAssertEqual(s.map(\.text), ["Oi", "Oi, tudo bem?", "ruído", "Bom dia"])
    XCTAssertEqual(s.map(\.speaker_id), [0, 1, 3, 2])
    XCTAssertEqual(s.map(\.is_user), [true, false, false, false])
    XCTAssertEqual(s.map(\.person_id), [nil, nil, nil, "p-julio"])
    XCTAssertEqual(s[1].end, 4)
    XCTAssertEqual(pedido.client_conversation_id, "cerebro-b")
    XCTAssertEqual(pedido.calendar_meeting_context?.participants.map(\.name), ["Sofia Henriqueto", "Júlio"])
    XCTAssertEqual(pedido.calendar_meeting_context?.duration_minutes, 60)
    XCTAssertEqual(pedido.folder_id, "pasta")

    let muitos = (0..<1200).map {
      MeetingCopilotServer.Trecho(seq: $0, startMs: $0 * 1000, speaker: $0 % 2 == 0 ? "Gabriel" : "Sofia", text: "x")
    }
    XCTAssertLessThanOrEqual(
      ReunioesImportador.segmentos(muitos, pessoas: [:], nomes: ["Sofia"], givenName: "Gabriel").count, 500)
  }
}
