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

  // MARK: - Legenda do Deepgram

  func testAcumuladorJuntaFinaisEParciais() {
    var a = JarvisLegenda.Acumulador()
    func r(_ texto: String, final: Bool = false, fala: Bool = false) -> [String: Any] {
      [
        "type": "Results", "is_final": final, "speech_final": fala,
        "channel": ["alternatives": [["transcript": texto]]],
      ]
    }
    XCTAssertEqual(a.receber(r("quantas"))?.texto, "quantas")
    XCTAssertEqual(a.receber(r("quantas demandas", final: true))?.terminou, false)
    XCTAssertEqual(a.receber(r("abertas"))?.texto, "quantas demandas abertas")
    let fim = a.receber(r("abertas eu tenho", final: true, fala: true))
    XCTAssertEqual(fim?.texto, "quantas demandas abertas eu tenho")
    XCTAssertEqual(fim?.terminou, true)
    XCTAssertNil(a.receber(r("")))

    var b = JarvisLegenda.Acumulador()
    XCTAssertNil(b.receber(["type": "UtteranceEnd"]), "fim de fala sem nada dito não vira pedido")
    _ = b.receber(r("abre a calculadora", final: true))
    XCTAssertEqual(b.receber(["type": "UtteranceEnd"])?.terminou, true)
  }

  func testFimDeFalaUsaOParcialQuandoOFinalNaoChegou() {
    func r(_ texto: String, final: Bool = false) -> [String: Any] {
      ["type": "Results", "is_final": final, "channel": ["alternatives": [["transcript": texto]]]]
    }
    var a = JarvisLegenda.Acumulador()
    XCTAssertEqual(a.textoAteAgora, "", "nada ouvido: aí sim é \"Não ouvi nada\"")
    _ = a.receber(r("abre a conta das no gerenciador de anúncio do Facebook"))
    XCTAssertEqual(a.textoAteAgora, "abre a conta das no gerenciador de anúncio do Facebook")
    XCTAssertEqual(a.receber(["type": "UtteranceEnd"])?.texto, "abre a conta das no gerenciador de anúncio do Facebook")

    var b = JarvisLegenda.Acumulador()
    _ = b.receber(r("abre a conta", final: true))
    _ = b.receber(r("do Facebook"))
    XCTAssertEqual(b.textoAteAgora, "abre a conta do Facebook", "finais primeiro, depois o parcial em aberto")
    _ = b.receber(r("do Facebook Ads", final: true))
    XCTAssertEqual(b.textoAteAgora, "abre a conta do Facebook Ads", "o final substitui o parcial")
  }

  func testFalaLongaComAspasEAcentosChegaInteira() throws {
    let trechos = [
      "Jarvis, abre o gerenciador de anúncios do Facebook na conta da Ópera Arte,",
      "procura a campanha \"Réveillon 2027\" e me diz quanto gastou ontem,",
      "quantos leads entraram e qual foi o custo por lead comparado à semana passada,",
      "e depois anota isso no Cérebro com a data de hoje — sem pausar a campanha.",
    ]
    var a = JarvisLegenda.Acumulador()
    for t in trechos {
      _ = a.receber(["type": "Results", "is_final": false, "channel": ["alternatives": [["transcript": t]]]])
      _ = a.receber(["type": "Results", "is_final": true, "channel": ["alternatives": [["transcript": t]]]])
    }
    let fim = try XCTUnwrap(a.receber(["type": "UtteranceEnd"]))
    let esperado = trechos.joined(separator: " ")
    XCTAssertGreaterThan(esperado.count, 200)
    XCTAssertEqual(fim.texto, esperado)
    XCTAssertTrue(fim.terminou)
    XCTAssertTrue(JarvisLegenda.url.absoluteString.contains("endpointing=1200"), "fim por silêncio de 1,2 s")

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
