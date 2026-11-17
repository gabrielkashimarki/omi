import XCTest

@testable import Omi_Computer

final class JarvisEstatisticasTests: XCTestCase {
  private var calendario: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return c
  }

  private func data(_ dia: Int, _ hora: Int, _ minuto: Int = 0) -> Date {
    calendario.date(from: DateComponents(year: 2026, month: 11, day: dia, hour: hora, minute: minuto))!
  }

  func testAgregaSemanaComMinutosReunioesPedidosEOrigens() {
    let hoje = data(17, 18)
    let gravacoes = [
      JarvisGravacao(inicio: data(17, 9), fim: data(17, 9, 30), origem: "desktop", reuniao: true),
      JarvisGravacao(inicio: data(16, 14), fim: data(16, 14, 10), origem: "desktop", reuniao: false),
      // Ainda gravando: conta como conversa, sem minutos.
      JarvisGravacao(inicio: data(17, 17), fim: nil, origem: "omi", reuniao: false),
      // Fora da semana.
      JarvisGravacao(inicio: data(1, 10), fim: data(1, 11), origem: "desktop", reuniao: true),
    ]
    let pedidos = [
      JarvisPedido(criadoEm: data(17, 8), origem: "mac"),
      JarvisPedido(criadoEm: data(15, 8), origem: "whatsapp"),
      JarvisPedido(criadoEm: data(2, 8), origem: "mac"),
    ]

    let r = JarvisResumo.agregar(
      gravacoes: gravacoes, pedidos: pedidos, periodo: .semana, hoje: hoje, calendario: calendario)

    XCTAssertEqual(r.conversas, 3)
    XCTAssertEqual(r.reunioes, 1)
    XCTAssertEqual(r.minutos, 40)
    XCTAssertEqual(r.pedidos, 2)
    XCTAssertEqual(r.porDia.count, 7)
    XCTAssertEqual(r.porDia.last?.minutos, 30)
    XCTAssertEqual(r.porDia.last?.data, calendario.startOfDay(for: hoje))
    XCTAssertEqual(r.porDia[5].minutos, 10)
    XCTAssertEqual(r.onde.first?.rotulo, "Gravação no Mac")
    XCTAssertEqual(r.onde.first?.quantidade, 2)
    XCTAssertEqual(Set(r.onde.map(\.rotulo)), ["Gravação no Mac", "Colar Omi", "Jarvis (Mac)", "Jarvis (WhatsApp)"])
  }

  func testSemChaveOsPedidosFicamVazios() {
    let r = JarvisResumo.agregar(gravacoes: [], pedidos: nil, periodo: .tudo, hoje: data(17, 12), calendario: calendario)
    XCTAssertNil(r.pedidos)
    XCTAssertEqual(r.porDia.count, 30)
    XCTAssertTrue(r.onde.isEmpty)
  }

  func testLeHistoricoDoServidorContandoSoOsPedidosDoGabriel() {
    let json = """
      [{"origem": "mac", "papel": "gabriel", "texto": "a", "criado_em": "2026-11-17T00:56:21.903286+00:00", "extra": {}},
       {"origem": "mac", "papel": "jarvis", "texto": "b", "criado_em": "2026-11-17T00:56:52.636697+00:00", "extra": {}},
       {"origem": "whatsapp", "papel": "gabriel", "texto": "c", "criado_em": "2026-11-16T10:00:00+00:00", "extra": {}}]
      """
    let pedidos = JarvisResumo.pedidos(doHistorico: Data(json.utf8))
    XCTAssertEqual(pedidos?.count, 2)
    XCTAssertEqual(pedidos?.first?.criadoEm, Date(timeIntervalSince1970: 1_794_876_981))
    XCTAssertEqual(pedidos?.last?.origem, "whatsapp")
    XCTAssertNil(JarvisResumo.pedidos(doHistorico: Data("{\"erro\":1}".utf8)))
  }

  func testDuracao() {
    XCTAssertEqual(JarvisEstatisticasPagina.duracao(minutos: 18), "18 min")
    XCTAssertEqual(JarvisEstatisticasPagina.duracao(minutos: 232), "3 h 52")
  }
}
