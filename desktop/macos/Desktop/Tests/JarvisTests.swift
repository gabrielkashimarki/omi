import XCTest

@testable import Omi_Computer

final class JarvisTests: XCTestCase {
  // MARK: - NDJSON do /jarvis

  func testLeCadaLinhaDoNDJSON() {
    XCTAssertEqual(
      JarvisCliente.ler(#"{"passo": "mcp__jarvis__listar_demandas"}"#), .passo("mcp__jarvis__listar_demandas"))
    XCTAssertEqual(
      JarvisCliente.ler(#"{"confirmar": {"id": "a1", "resumo": "Mandar WhatsApp", "fala": "Posso mandar?"}}"#),
      .confirmar(id: "a1", resumo: "Mandar WhatsApp", fala: "Posso mandar?"))
    XCTAssertEqual(
      JarvisCliente.ler(#"{"fala": "Você tem 3 demandas.", "detalhe_md": "**3**"}"#),
      .fim(fala: "Você tem 3 demandas.", detalhe: "**3**"))
    XCTAssertEqual(JarvisCliente.ler(#"{"fala": "Oi"}"#), .fim(fala: "Oi", detalhe: ""))
    XCTAssertNil(JarvisCliente.ler(""))
    XCTAssertNil(JarvisCliente.ler("não é json"))
    XCTAssertNil(JarvisCliente.ler(#"{"outra": 1}"#))
  }

  func testHistoricoDeixaFerramentaDeFora() {
    let dados = Data(
      #"""
      [{"origem":"mac","papel":"gabriel","texto":"quantas demandas","criado_em":"2026-11-17T00:56:21.903286+00:00","extra":{}},
       {"origem":"mac","papel":"ferramenta","texto":"listar_demandas","criado_em":"2026-11-17T00:56:30+00:00","extra":{}},
       {"origem":"whatsapp","papel":"jarvis","texto":"São 420.","criado_em":"2026-11-17T00:56:52+00:00","extra":{"detalhe_md":"**420**"}}]
      """#.utf8)
    let h = JarvisCliente.historico(de: dados)
    XCTAssertEqual(h.map(\.papel), ["gabriel", "jarvis"])
    XCTAssertEqual(h.last?.detalhe, "**420**")
    XCTAssertNotNil(h.first?.quando)
    XCTAssertTrue(JarvisCliente.historico(de: Data("{}".utf8)).isEmpty)
  }

  func testPassoLegivel() {
    XCTAssertEqual(JarvisCliente.passoLegivel("mcp__cerebro__buscar_contexto"), "buscando no Cérebro")
    XCTAssertEqual(
      JarvisCliente.passoLegivel("mcp__composio__COMPOSIO_SEARCH_TOOLS"), "consultando Gmail, Agenda ou Drive")
    XCTAssertEqual(JarvisCliente.passoLegivel("nova_ferramenta"), "nova ferramenta")
  }

  // MARK: - Pedido do mexer_no_mac

  func testLeOsFormatosDoMexerNoMac() {
    XCTAssertEqual(JarvisMaos.ler(["acao": "abrir_app", "app": "Calculadora"]), .abrirApp("Calculadora"))
    XCTAssertEqual(JarvisMaos.ler(["action": "open_app", "name": "Calculator"]), .abrirApp("Calculator"))
    XCTAssertEqual(JarvisMaos.ler(["acao": "Abrir App", "nome": "Kommo"]), .abrirApp("Kommo"))
    XCTAssertEqual(JarvisMaos.ler(["app": "Safari"]), .abrirApp("Safari"))
    XCTAssertEqual(
      JarvisMaos.ler(["acao": "abrir", "url": "https://kommo.com"]), .abrirURL(URL(string: "https://kommo.com")!))
    XCTAssertEqual(JarvisMaos.ler(["acao": "abrir_url", "url": "https://a.b"]), .abrirURL(URL(string: "https://a.b")!))
    XCTAssertEqual(JarvisMaos.ler(["acao": "digitar", "texto": "olá"]), .digitar("olá"))
    XCTAssertEqual(JarvisMaos.ler(["args": ["click", "Enviar"]]), .hands(["click", "Enviar"]))
    XCTAssertEqual(JarvisMaos.ler(["acao": "apagar_tudo"]), .desconhecida)
    XCTAssertEqual(JarvisMaos.ler(["acao": "abrir_app"]), .desconhecida)
    XCTAssertEqual(JarvisMaos.ler([:]), .desconhecida)
  }

  func testNomeDoAppIgnoraCaixaAcentoEExtensao() {
    XCTAssertTrue(JarvisMaos.mesmoNome("Calculator.app", "calculator"))
    XCTAssertTrue(JarvisMaos.mesmoNome("Calendário", "calendario"))
    XCTAssertFalse(JarvisMaos.mesmoNome("Calculator.app", "Calendar"))
  }

  func testReconexaoDobraAte60s() {
    XCTAssertEqual(JarvisMac.espera(depois: 1), 1)
    XCTAssertEqual(JarvisMac.espera(depois: 3), 4)
    XCTAssertEqual(JarvisMac.espera(depois: 20), 60)
  }

  func testSemPongCaiEAgendaReconexao() async {
    // conexão meio aberta: o callback do ping nunca vem, e o prazo tem de dar falha em vez de travar
    let semPong = await JarvisMac.comPrazo(.milliseconds(50)) { _ in }
    XCTAssertFalse(semPong)
    // pong e depois cancelamento no mesmo callback: vale o primeiro e não derruba o app
    let duplo = await JarvisMac.comPrazo(.seconds(5)) { responder in
      responder(true)
      responder(false)
    }
    XCTAssertTrue(duplo)

    var l = JarvisLigacao()
    l.conectou()
    XCTAssertTrue(l.conectado)
    XCTAssertEqual(l.caiu(), 1, "caiu depois de conectado: tenta de novo em 1 s")
    XCTAssertFalse(l.conectado)
    XCTAssertEqual(l.caiu(), 2, "tentativa que não conectou dobra a espera")
    XCTAssertEqual(l.caiu(), 4)
    l.cutucado()
    XCTAssertEqual(l.caiu(), 1, "Mac acordou ou rede voltou: sem espera acumulada")
  }

  // MARK: - Legenda do Deepgram (Flux)

  private func turno(_ evento: String, _ texto: String) -> [String: Any] {
    ["type": "TurnInfo", "event": evento, "transcript": texto]
  }

  func testAcumuladorDoFluxFechaNoEndOfTurn() {
    var a = JarvisLegenda.Acumulador()
    XCTAssertNil(a.receber(turno("StartOfTurn", "")))
    XCTAssertEqual(a.receber(turno("Update", "quantas"))?.terminou, false)
    XCTAssertEqual(a.receber(turno("Update", "quantas demandas abertas"))?.texto, "quantas demandas abertas")
    let fim = a.receber(turno("EndOfTurn", "quantas demandas abertas eu tenho?"))
    XCTAssertEqual(fim?.texto, "quantas demandas abertas eu tenho?")
    XCTAssertEqual(fim?.terminou, true)
    XCTAssertEqual(a.textoAteAgora, "", "o turno seguinte começa vazio")
    XCTAssertNil(a.receber(turno("EndOfTurn", "")), "fim de turno sem nada dito não vira pedido")
    XCTAssertNil(a.receber(["type": "Connected"]))
    XCTAssertNil(a.receber(["type": "Results", "is_final": true]), "formato do nova-3 não conta")
  }

  func testFimDoTurnoVazioUsaOQueJaFoiOuvido() {
    var a = JarvisLegenda.Acumulador()
    _ = a.receber(turno("Update", "abre a conta do Facebook"))
    XCTAssertEqual(a.textoAteAgora, "abre a conta do Facebook")
    XCTAssertEqual(a.receber(turno("EndOfTurn", ""))?.texto, "abre a conta do Facebook")
  }

  func testFalaLongaComAspasEAcentosChegaInteira() throws {
    let trechos = [
      "Jarvis, abre o gerenciador de anúncios do Facebook na conta da Ópera Arte,",
      "procura a campanha \"Réveillon 2027\" e me diz quanto gastou ontem,",
      "quantos leads entraram e qual foi o custo por lead comparado à semana passada,",
      "e depois anota isso no Cérebro com a data de hoje — sem pausar a campanha.",
    ]
    var a = JarvisLegenda.Acumulador()
    var ate = ""
    for t in trechos {
      ate = ate.isEmpty ? t : ate + " " + t
      _ = a.receber(turno("Update", ate))
    }
    let fim = try XCTUnwrap(a.receber(turno("EndOfTurn", ate)))
    let esperado = trechos.joined(separator: " ")
    XCTAssertGreaterThan(esperado.count, 200)
    XCTAssertEqual(fim.texto, esperado)
    XCTAssertTrue(fim.terminou)
    let url = JarvisLegenda.url.absoluteString
    XCTAssertTrue(url.contains("/v2/listen") && url.contains("flux-general-multi") && url.contains("pt-BR"))
    XCTAssertEqual(JarvisLegenda.quadro, 16_000 * 2 * 80 / 1000, "80 ms de PCM 16 kHz por envio")

    // a ponte para o JS leva o texto inteiro, escapado
    let js = try XCTUnwrap(JarvisPainel.chamadaJS("legenda", esperado + "\nlinha 2"))
    XCTAssertTrue(js.hasPrefix("window.jarvis?.legenda(...["))
    let json = String(js.dropFirst("window.jarvis?.legenda(...".count).dropLast())
    let volta = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String])
    XCTAssertEqual(volta, [esperado + "\nlinha 2"])

    // e o corpo do POST /jarvis também
    let corpo = try JSONSerialization.data(withJSONObject: ["texto": esperado, "origem": "mac"])
    XCTAssertEqual((try JSONSerialization.jsonObject(with: corpo) as? [String: String])?["texto"], esperado)
  }

  func testPreencherLoginNuncaLevaSenha() {
    XCTAssertEqual(JarvisMaos.ler(["acao": "preencher_login"]), .preencherLogin)
    XCTAssertEqual(JarvisMaos.ler(["action": "autofill"]), .preencherLogin)
    XCTAssertTrue(JarvisMaos.formatos.contains("preencher_login"))
  }

  // MARK: - Painel e ícone

  func testPainelSomeVinteSegundosDepoisDaUltimaAtividade() {
    let t0 = Date()
    var e = JarvisPainelEstado()
    e.ir(.respondeu, agora: t0)
    XCTAssertFalse(e.deveSumir(agora: t0.addingTimeInterval(19)))
    XCTAssertTrue(e.deveSumir(agora: t0.addingTimeInterval(20)))
    e.atividade(agora: t0.addingTimeInterval(15))
    XCTAssertFalse(e.deveSumir(agora: t0.addingTimeInterval(30)))
    for fase in [JarvisPainelEstado.Fase.ouvindo, .pensando, .confirmando] {
      e.ir(fase, agora: t0)
      XCTAssertFalse(e.deveSumir(agora: t0.addingTimeInterval(600)), "\(fase) não some")
    }
  }

  // MARK: - Conversa contínua

  func testJanelaDaConversaAbreDepoisDaRespostaSoComTudoLivre() {
    func abre(
      _ fase: JarvisPainelEstado.Fase, reuniao: Bool = false, aberto: Bool = true, falando: Bool = false,
      encerrada: Bool = false
    ) -> Bool {
      JarvisConversa.abreJanela(
        fase: fase, reuniao: reuniao, painelAberto: aberto, falando: falando, encerrada: encerrada)
    }
    XCTAssertTrue(abre(.respondeu))
    XCTAssertTrue(abre(.confirmando), "confirmação pendente também ouve o confirmo falado")
    XCTAssertFalse(abre(.respondeu, falando: true), "TTS tocando: o microfone ouviria a própria voz")
    XCTAssertFalse(abre(.respondeu, reuniao: true), "na reunião fica mudo")
    XCTAssertFalse(abre(.respondeu, aberto: false), "painel fechado não reabre sozinho")
    XCTAssertFalse(abre(.respondeu, encerrada: true), "Encerrar vale até o próximo pedido")
    for fase in [JarvisPainelEstado.Fase.pronto, .ouvindo, .pensando] {
      XCTAssertFalse(abre(fase), "\(fase) não abre a janela")
    }
    XCTAssertEqual(JarvisConversa.janela, 20)
  }

  func testJanelaQueFechaEmSilencioSegueARegraDeSumir() {
    let t0 = Date()
    var e = JarvisPainelEstado()
    e.ir(.ouvindo, agora: t0)
    XCTAssertFalse(e.deveSumir(agora: t0.addingTimeInterval(60)), "ouvindo na janela não some")
    e.ir(.respondeu, agora: t0.addingTimeInterval(20))
    XCTAssertFalse(e.deveSumir(agora: t0.addingTimeInterval(39)))
    XCTAssertTrue(e.deveSumir(agora: t0.addingTimeInterval(40)))
  }

  func testConfirmacaoFalada() {
    for t in ["Confirmo.", "sim", "Sim, pode", "pode sim", "CONFIRMA!"] {
      XCTAssertEqual(JarvisConversa.respostaFalada(t), true, t)
    }
    for t in ["Não.", "nao", "recuso", "Não, cancela", "cancela"] {
      XCTAssertEqual(JarvisConversa.respostaFalada(t), false, t)
    }
    for t in ["", "  ", "manda para o Pedro", "sim, e manda também para a Carla", "pode abrir o Gmail"] {
      XCTAssertNil(JarvisConversa.respostaFalada(t), t)
    }
  }

  func testDespedidaEncerraAConversa() {
    for t in ["Valeu, Jarvis.", "valeu", "obrigado, Jarvis", "Obrigada, era só isso.", "tchau jarvis"] {
      XCTAssertTrue(JarvisConversa.despedida(t), t)
    }
    for t in ["", "Jarvis", "valeu, manda o relatório para a Lélia", "obrigado por mandar, agora abre o Gmail"] {
      XCTAssertFalse(JarvisConversa.despedida(t), t)
    }
  }

  func testInterrupcaoPedeDuasPalavras() {
    XCTAssertEqual(JarvisConversa.palavrasParaInterromper, 2)
    XCTAssertEqual(JarvisConversa.palavras("hum"), 1)
    XCTAssertEqual(JarvisConversa.palavras(" espera aí "), 2)
  }

  // MARK: - Voz

  func testFalaDivididaPorFrase() {
    XCTAssertEqual(
      JarvisVoz.frases("Você tem três demandas vencidas. A mais antiga é da PACINI! Quer que eu cobre?"),
      ["Você tem três demandas vencidas.", "A mais antiga é da PACINI!", "Quer que eu cobre?"])
    XCTAssertEqual(JarvisVoz.frases("Ok. Mandei o relatório."), ["Ok. Mandei o relatório."], "pedaço curto vai junto")
    XCTAssertEqual(JarvisVoz.frases("Custa R$ 1.500,00 por mês"), ["Custa R$ 1.500,00 por mês"], "ponto no número não corta")
    XCTAssertEqual(JarvisVoz.frases("  "), [])
    XCTAssertEqual(
      JarvisVoz.frases(
        "Hoje você tem três reuniões marcadas, a primeira é com a PACINI às dez e a segunda com a Zago. Quer o resumo?"),
      [
        "Hoje você tem três reuniões marcadas,", "a primeira é com a PACINI às dez e a segunda com a Zago.",
        "Quer o resumo?",
      ], "primeira frase longa quebra na vírgula")
    XCTAssertNil(JarvisVoz.quebraNaVirgula("Custa R$ 1.500,00 por mês e o resto do plano fica igual ao de antes"))
  }

  func testWavDoGeminiViraBufferDe24kHz() throws {
    let amostras: [Int16] = [0, 16384, -16384, 32767]
    var pcm = Data()
    for a in amostras { withUnsafeBytes(of: a.littleEndian) { pcm.append(contentsOf: $0) } }
    func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    var wav = Data("RIFF".utf8) + le(UInt32(36 + pcm.count)) + Data("WAVEfmt ".utf8)
    wav += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1)) + le(UInt32(24_000)) + le(UInt32(48_000)) + le(UInt16(2))
    wav += le(UInt16(16)) + Data("data".utf8) + le(UInt32(pcm.count)) + pcm
    let b = try XCTUnwrap(JarvisVoz.buffer(wav: wav))
    XCTAssertEqual(b.frameLength, 4)
    XCTAssertEqual(b.format.sampleRate, 24_000)
    XCTAssertEqual(b.floatChannelData![0][1], 0.5, accuracy: 0.001)
    XCTAssertEqual(b.floatChannelData![0][2], -0.5, accuracy: 0.001)
  }

  /// A instrução de estilo saía falada ("Diga em português do Brasil..."): o texto vai sozinho e o estilo na anotação.
  func testTTSDoGeminiMandaSoOTexto() throws {
    let corpo = MeetingCopilotVoice.corpo("Pronto, mandei.")
    let input = try XCTUnwrap(corpo["input"] as? [[String: Any]])
    let item = try XCTUnwrap((input.first?["content"] as? [[String: Any]])?.first)
    XCTAssertEqual(item["text"] as? String, "Pronto, mandei.")
    let nota = try XCTUnwrap((item["annotations"] as? [[String: Any]])?.first)
    XCTAssertEqual(nota["type"] as? String, "speech_metadata")
    XCTAssertNil(corpo["systemInstruction"], "o 3.8 TTS recusa systemInstruction")
    XCTAssertTrue(JSONSerialization.isValidJSONObject(corpo))
  }

  func testAvisoDeDiscoAbaixoDe3GB() {
    XCTAssertTrue(JarvisDisco.quaseCheio(livres: 962_000_000), "os 962 MB de 18/11")
    XCTAssertTrue(JarvisDisco.quaseCheio(livres: 2_999_999_999))
    XCTAssertFalse(JarvisDisco.quaseCheio(livres: 3_000_000_000))
    XCTAssertFalse(JarvisDisco.quaseCheio(livres: nil), "sem leitura do disco não avisa")
  }

  func testIconeMostraOQueOJarvisFazAntesDaReuniao() {
    XCTAssertEqual(JarvisMenu.icone(fase: .pronto, reuniao: false), .pronto)
    XCTAssertEqual(JarvisMenu.icone(fase: .respondeu, reuniao: true), .gravando)
    XCTAssertEqual(JarvisMenu.icone(fase: .ouvindo, reuniao: true), .ouvindo)
    XCTAssertEqual(JarvisMenu.icone(fase: .confirmando, reuniao: false), .pensando)
  }

  // MARK: - Hey Jarvis

  func testHeyJarvisFicaMudoNaReuniao() {
    XCTAssertFalse(JarvisHeyJarvis.mudo(ligado: true, reuniao: false, painelOuvindo: false))
    XCTAssertTrue(JarvisHeyJarvis.mudo(ligado: true, reuniao: true, painelOuvindo: false))
    XCTAssertTrue(JarvisHeyJarvis.mudo(ligado: true, reuniao: false, painelOuvindo: true))
    XCTAssertTrue(JarvisHeyJarvis.mudo(ligado: false, reuniao: false, painelOuvindo: false))
  }

  /// "hey jarvis" falado pelo `say` dispara; uma frase comum não. Referência do openwakeword em Python com o
  /// mesmo áudio: Daniel 0,995, frase comum 0,0.
  func testDetectorOuveHeyJarvisNoAudioDoSay() throws {
    let modelos = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Sources/Resources")
    let detector = try XCTUnwrap(JarvisDetectorPalavra(pasta: modelos))
    let positivo = try falar("hey jarvis", voz: "Daniel")
    let negativo = try falar("bom dia, tudo bem com você? vamos falar da reunião de amanhã", voz: "Luciana")
    let silencio = [Int16](repeating: 0, count: 16_000)

    detector.reset()
    let nota = detector.processar(silencio + positivo + silencio)
    XCTAssertGreaterThanOrEqual(nota, JarvisDetectorPalavra.limiar, "nota \(nota)")

    detector.reset()
    let falso = detector.processar(silencio + negativo + silencio)
    XCTAssertLessThan(falso, JarvisDetectorPalavra.limiar, "nota \(falso)")

    // a palavra seguida em blocos de 80 ms não falha (o erro do onnxruntime só aparecia no fechamento do app)
    detector.reset()
    var maior: Float = 0
    let tudo = silencio + positivo + silencio + negativo + silencio
    for i in stride(from: 0, to: tudo.count, by: 1280) { maior = max(maior, detector.processar(Array(tudo[i..<min(i + 1280, tudo.count)]))) }
    XCTAssertGreaterThanOrEqual(maior, JarvisDetectorPalavra.limiar)

    // fechando o app: nenhum bloco chega mais ao onnxruntime
    detector.reset()
    detector.desligado = true
    XCTAssertEqual(detector.processar(silencio + positivo + silencio), 0)
  }

  /// Áudio do `say` em PCM 16 bits a 16 kHz.
  private func falar(_ texto: String, voz: String) throws -> [Int16] {
    let pasta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: pasta) }
    let aiff = pasta.appendingPathComponent("a.aiff")
    let wav = pasta.appendingPathComponent("a.wav")
    for (bin, args) in [
      ("/usr/bin/say", ["-v", voz, texto, "-o", aiff.path]),
      ("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path]),
    ] {
      let p = try Process.run(URL(fileURLWithPath: bin), arguments: args)
      p.waitUntilExit()
      guard p.terminationStatus == 0 else { throw XCTSkip("\(bin) falhou neste Mac") }
    }
    let dados = try Data(contentsOf: wav)
    guard let marca = dados.range(of: Data("data".utf8)), marca.upperBound + 4 < dados.count else {
      throw XCTSkip("WAV sem bloco de dados")
    }
    let pcm = dados[(marca.upperBound + 4)...]
    guard pcm.count > 3200 else { throw XCTSkip("say gerou áudio vazio") }
    return Data(pcm).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
  }
}
