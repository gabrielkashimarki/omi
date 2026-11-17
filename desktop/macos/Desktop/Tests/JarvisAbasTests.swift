import XCTest

@testable import Omi_Computer

/// A lógica pura das abas Tarefas e Cérebro (Jarvis único, fase 4).
final class JarvisAbasTests: XCTestCase {
  private func demanda(
    _ id: Int, q: String?, prazo: String? = nil, venceu: Bool = false, situacao: String = "aberta",
    cliente: String? = "PACINI"
  ) -> JarvisDemanda {
    JarvisDemanda(
      id: id, titulo: "D\(id)", resumo: nil, situacao: situacao, responsavel: "gabriel", prazo: prazo, quadrante: q,
      venceu: venceu, parada: false, cliente: cliente)
  }

  func testQuadrantesSeguemARegraDoComando() {
    let grupos = JarvisMatriz.agrupar([
      demanda(1, q: "Q1"), demanda(2, q: "Q2"), demanda(3, q: "Q3"), demanda(4, q: "Q4"), demanda(5, q: nil),
      demanda(6, q: "Q1", situacao: "concluida"), demanda(7, q: "Q2", situacao: "cancelada"),
      demanda(8, q: "Q1", situacao: "esperando_voce"),
    ])
    XCTAssertEqual(grupos[.q1]?.map(\.id), [1, 8], "concluída e cancelada saem; esperando você fica")
    XCTAssertEqual(grupos[.q2]?.map(\.id), [2])
    XCTAssertEqual(grupos[.q3]?.map(\.id), [3])
    XCTAssertEqual(grupos[.q4]?.map(\.id), [4])
    XCTAssertEqual(grupos[.sem]?.map(\.id), [5], "sem importante/urgente vai para Sem classificar")
    XCTAssertEqual(JarvisQuadrante.matriz.map(\.titulo), ["Faça agora", "Agende", "Delegue", "Depois"])
  }

  func testDentroDoQuadranteVencidaPrimeiroDepoisPrazo() {
    let grupos = JarvisMatriz.agrupar([
      demanda(10, q: "Q1"), demanda(11, q: "Q1", prazo: "2026-11-30"), demanda(12, q: "Q1", prazo: "2026-11-20"),
      demanda(13, q: "Q1", prazo: "2026-12-01", venceu: true),
    ])
    XCTAssertEqual(grupos[.q1]?.map(\.id), [13, 12, 11, 10])
  }

  func testFiltroDeClienteEListaDeClientes() {
    let lista = [demanda(1, q: "Q1", cliente: "Zago"), demanda(2, q: "Q1", cliente: "Ópera Arte"), demanda(3, q: "Q2")]
    XCTAssertEqual(JarvisMatriz.agrupar(lista, cliente: "Zago")[.q1]?.map(\.id), [1])
    XCTAssertNil(JarvisMatriz.agrupar(lista, cliente: "Zago")[.q2])
    XCTAssertEqual(JarvisMatriz.clientes(lista), ["Ópera Arte", "PACINI", "Zago"])
  }

  func testArrastarViraOCorpoDoPost() {
    XCTAssertEqual(JarvisMatriz.corpoMover(para: .q2)?["quadrante"] as? String, "Q2")
    XCTAssertEqual(JarvisMatriz.corpoMover(para: .q3)?["acao"] as? String, "quadrante")
    XCTAssertNil(JarvisMatriz.corpoMover(para: .sem), "Sem classificar não é destino")
  }

  func testRotuloDoPrazo() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    let hoje = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 15))!
    XCTAssertEqual(JarvisMatriz.rotuloPrazo("2026-11-17", hoje: hoje, calendario: cal), "Hoje")
    XCTAssertEqual(JarvisMatriz.rotuloPrazo("2026-11-18", hoje: hoje, calendario: cal), "Amanhã")
    XCTAssertEqual(JarvisMatriz.rotuloPrazo("2026-11-16", hoje: hoje, calendario: cal), "Ontem")
    XCTAssertEqual(JarvisMatriz.rotuloPrazo("2026-11-20", hoje: hoje, calendario: cal), "sex., 20/11")
    XCTAssertEqual(JarvisMatriz.rotuloPrazo(nil, hoje: hoje, calendario: cal), "Sem prazo")
    XCTAssertEqual(JarvisMatriz.textoPrazo(hoje, calendario: cal), "2026-11-17")
  }

  func testDecodificaATarefaDoServidor() throws {
    let json = """
      [{"id": 91, "tipo": "compromisso", "prazo": "2026-10-16", "parada": true, "resumo": "r",
        "titulo": "Enviar vídeos", "venceu": true, "cliente": "Pacini Odontologia", "situacao": "aberta",
        "criada_em": "2026-10-14T15:45:48+00:00", "quadrante": "Q1", "quem_pediu": "Lelia", "responsavel": "lelia",
        "motivo_matriz": "x"},
       {"id": 92, "titulo": "Sem nada", "situacao": "aberta", "venceu": false, "parada": false,
        "prazo": null, "quadrante": null, "cliente": null, "responsavel": null}]
      """
    let d = try JSONDecoder().decode([JarvisDemanda].self, from: Data(json.utf8))
    XCTAssertEqual(d.map(\.id), [91, 92])
    XCTAssertEqual(JarvisQuadrante(da: d[0]), .q1)
    XCTAssertEqual(JarvisQuadrante(da: d[1]), .sem)
  }

  func testListasDoCerebro() throws {
    let json = """
      {"itens": [
        {"id": "a", "enunciado": "Foto de banco não", "estado": "contestada", "camada": "L1_politica", "tipo": "regra",
         "cliente": "Zago", "project_id": "p", "criado_em": "x", "fonte_trecho": "t",
         "motivo": "Lélia disse que pode.", "motivo_tipo": "contradicao"},
        {"id": "b", "enunciado": "BF dia 20", "estado": "arquivada", "camada": null, "tipo": "fato", "cliente": "PACINI",
         "project_id": "p", "criado_em": "x", "fonte_trecho": null, "motivo": null, "motivo_tipo": null},
        {"id": "c", "enunciado": "PDF até dia 5", "estado": "rascunho", "camada": "L3_estado", "tipo": "fato",
         "cliente": "GoGenetic", "project_id": "p", "criado_em": "x", "fonte_trecho": "e-mail",
         "motivo": null, "motivo_tipo": null}],
       "clientes": [{"id": "p", "nome": "Zago"}]}
      """
    let r = try JSONDecoder().decode(
      JarvisCerebroMontagem.Resposta<JarvisAssercao>.self, from: Data(json.utf8))
    XCTAssertEqual(r.itens.count, 3)
    XCTAssertEqual(r.clientes.first?.nome, "Zago")
    XCTAssertEqual(
      JarvisCerebroMontagem.motivo(r.itens[0]), "Contestada (contradiz outra asserção): Lélia disse que pode.")
    XCTAssertEqual(JarvisCerebroMontagem.motivo(r.itens[1]), "Recusada: sem motivo registrado.")
    XCTAssertNil(JarvisCerebroMontagem.motivo(r.itens[2]), "rascunho não tem motivo")
    XCTAssertEqual(JarvisCerebroMontagem.selo("arquivada").texto, "Recusada")
    XCTAssertEqual(JarvisCerebroMontagem.origem(r.itens[0]), "Regra, política")

    let p = try JSONDecoder().decode(
      JarvisCerebroMontagem.Resposta<JarvisPergunta>.self,
      from: Data(#"{"itens":[{"id":"q","pergunta":"Vale?","enunciado":"e","cliente":"Zago"}],"clientes":[]}"#.utf8))
    XCTAssertEqual(p.itens.first?.pergunta, "Vale?")
  }

  func testCaminhoDoCerebroEscapaABusca() {
    XCTAssertEqual(JarvisCerebroMontagem.caminho("ativas", cliente: nil, busca: "  "), "/jarvis/cerebro?lista=ativas")
    let c = JarvisCerebroMontagem.caminho("perguntas", cliente: "u-1", busca: "sinal & 30%")
    XCTAssertTrue(c.hasPrefix("/jarvis/cerebro?lista=perguntas&cliente=u-1&q="))
    let volta = URLComponents(string: c)?.queryItems?.first { $0.name == "q" }?.value
    XCTAssertEqual(volta, "sinal & 30%", "o & da busca não vira outro parâmetro")
  }

  func testPainelDosAgentesFicaNoCantoENaoSaiDaTela() {
    let tela = NSRect(x: 0, y: 0, width: 1512, height: 944)
    let canto = AgentesPainelPosicao.cantoPadrao(tela)
    let pilula = AgentesPainelPosicao.tamanho(expandido: false, sessoes: 4, comPedido: false)
    let q = AgentesPainelPosicao.quadro(canto: canto, tamanho: pilula, tela: tela)
    XCTAssertEqual(q.maxX, tela.maxX - 16)
    XCTAssertEqual(q.minY, 16, "começa embaixo, longe do topo das janelas")
    let aberto = AgentesPainelPosicao.tamanho(expandido: true, sessoes: 4, comPedido: false)
    XCTAssertGreaterThan(aberto.width, pilula.width)
    let q2 = AgentesPainelPosicao.quadro(canto: canto, tamanho: aberto, tela: tela)
    XCTAssertEqual(q2.maxX, q.maxX, "abre para a esquerda e para cima, com o mesmo canto")
    XCTAssertEqual(q2.minY, q.minY)
    let fora = AgentesPainelPosicao.quadro(canto: NSPoint(x: 5000, y: 5000), tamanho: aberto, tela: tela)
    XCTAssertTrue(tela.contains(fora), "solto fora da tela, volta para dentro")

    let d = UserDefaults(suiteName: "teste-agentes-painel")!
    d.removePersistentDomain(forName: "teste-agentes-painel")
    XCTAssertNil(AgentesPainelPosicao.ler(d))
    AgentesPainelPosicao.gravar(NSPoint(x: 300, y: 200), d)
    XCTAssertEqual(AgentesPainelPosicao.ler(d), NSPoint(x: 300, y: 200), "lembra onde foi solto")
    d.removePersistentDomain(forName: "teste-agentes-painel")
  }
}
