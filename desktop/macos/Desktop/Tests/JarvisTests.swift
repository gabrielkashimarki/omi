import XCTest

@testable import Omi_Computer

final class JarvisTests: XCTestCase {
  // MARK: - NDJSON do /jarvis

  func testLeCadaLinhaDoNDJSON() {
    XCTAssertEqual(JarvisCliente.ler(#"{"passo": "mcp__jarvis__listar_demandas"}"#), .passo("mcp__jarvis__listar_demandas"))
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
    XCTAssertEqual(JarvisCliente.passoLegivel("mcp__composio__COMPOSIO_SEARCH_TOOLS"), "consultando Gmail, Agenda ou Drive")
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
}
