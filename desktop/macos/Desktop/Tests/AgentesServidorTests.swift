import XCTest

@testable import Omi_Computer

/// O servidor de hooks de ponta a ponta: `curl --unix-socket` manda o payload do Claude Code, como
/// faz o jarvis-hook, e lê a resposta.
@MainActor
final class AgentesServidorTests: XCTestCase {
  private var central: AgentesCentral!
  private var socket: String!

  override func setUp() async throws {
    socket = NSTemporaryDirectory() + "ag-\(UUID().uuidString.prefix(8)).sock"
    central = AgentesCentral()
    central.iniciar(caminhoSocket: socket, mostrarNotch: false)
  }

  override func tearDown() async throws {
    central.parar()
  }

  /// Roda o curl fora da main thread e devolve o que ele imprimiu.
  /// Começa o curl em segundo plano; `.value` espera ele terminar.
  private static nonisolated func curl(_ socket: String, _ json: String, espera: Int = 5) -> Task<String, Never> {
    Task.detached {
      let processo = Process()
      processo.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
      processo.arguments = [
        "-s", "--max-time", "\(espera)", "--unix-socket", socket, "-H", "Content-Type: application/json",
        "-H", "Expect:", "--data-binary", json, "http://jarvis/hook",
      ]
      let saida = Pipe()
      processo.standardOutput = saida
      try? processo.run()
      processo.waitUntilExit()
      return String(decoding: saida.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
  }

  private func esperar(_ condicao: () -> Bool) async {
    for _ in 0..<100 where !condicao() { try? await Task.sleep(for: .milliseconds(30)) }
  }

  func testEventosMontamAsSessoesSemSegurarOHook() async {
    let inicio = #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/Users/g/autoblogger","prompt":"roda os testes"}"#
    let saida = await Self.curl(socket, inicio).value
    XCTAssertEqual(saida, "", "evento comum responde vazio, o Claude segue")
    await esperar { central.quadro.sessoes["s1"] != nil }
    XCTAssertEqual(central.quadro.sessoes["s1"]?.projeto, "autoblogger")
    XCTAssertEqual(central.quadro.sessoes["s1"]?.estado, .pensando)
    XCTAssertEqual(central.estadoMascote, .trabalhando)

    _ = await Self.curl(socket, #"{"hook_event_name":"Stop","session_id":"s1","cwd":"/Users/g/autoblogger"}"#).value
    await esperar { central.quadro.sessoes["s1"]?.estado == .terminou }
    XCTAssertEqual(central.estadoMascote, .terminou)

    _ = await Self.curl(socket, #"{"hook_event_name":"SessionEnd","session_id":"s1"}"#).value
    await esperar { central.quadro.sessoes.isEmpty }
    XCTAssertTrue(central.quadro.sessoes.isEmpty)
  }

  func testPermissaoEsperaOCliqueEDevolveOFormatoDoClaude() async throws {
    let pedido = #"""
      {"hook_event_name":"PermissionRequest","session_id":"s2","cwd":"/tmp/proj","tool_name":"Bash",
       "tool_input":{"command":"rm -rf build"},
       "permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"rm -rf build"}],"behavior":"allow","destination":"localSettings"}]}
      """#
    let resposta = Self.curl(socket, pedido, espera: 10)
    await esperar { !central.pedidos.isEmpty }
    let cartao = try XCTUnwrap(central.pedidos.first)
    XCTAssertEqual(cartao.ferramenta, "Bash")
    XCTAssertEqual(cartao.resumo, "rm -rf build")
    XCTAssertEqual(central.estadoMascote, .precisaDeVoce)

    central.decidir(cartao.id, .sempre)
    let saida = await resposta.value
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(saida.utf8)) as? [String: Any])
    let decisao = try XCTUnwrap((json["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
    XCTAssertEqual(decisao["behavior"] as? String, "allow")
    XCTAssertEqual((decisao["updatedPermissions"] as? [Any])?.count, 1)
    XCTAssertTrue(central.pedidos.isEmpty)
  }

  func testNegarEOClaudeDesistindoTiramOCartao() async throws {
    let pedido = #"{"hook_event_name":"PermissionRequest","session_id":"s3","tool_name":"Write","tool_input":{"file_path":"/tmp/a"}}"#
    let negado = Self.curl(socket, pedido, espera: 10)
    await esperar { !central.pedidos.isEmpty }
    central.decidir(try XCTUnwrap(central.pedidos.first).id, .negar)
    let textoNegado = await negado.value
    XCTAssertTrue(textoNegado.contains(#""behavior":"deny""#))

    // O curl desiste em 1 s (como o Claude respondendo no terminal): o cartão some sozinho.
    let desistiu = Self.curl(socket, pedido, espera: 1)
    await esperar { !central.pedidos.isEmpty }
    XCTAssertEqual(central.pedidos.count, 1)
    _ = await desistiu.value
    await esperar { central.pedidos.isEmpty }
    XCTAssertTrue(central.pedidos.isEmpty)
  }

  func testPayloadInvalidoNaoQuebra() async {
    let saida = await Self.curl(socket, "isto não é json").value
    XCTAssertEqual(saida, "")
    XCTAssertTrue(central.quadro.sessoes.isEmpty)
  }

  func testRespostasDoClaude() {
    XCTAssertEqual(
      DecisaoPermissao.permitir.respostaClaude(sugestoes: nil),
      #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
    XCTAssertTrue(DecisaoPermissao.negar.respostaClaude(sugestoes: nil).contains("Negado pelo Jarvis"))
  }

  /// O comando de ligar os hooks num HOME temporário: preserva o que já existe, não duplica e
  /// desliga limpo.
  func testScriptDeLigarHooks() throws {
    let casa = FileManager.default.temporaryDirectory.appendingPathComponent("casa-\(UUID().uuidString)")
    let claude = casa.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
    let cfg = claude.appendingPathComponent("settings.json")
    let original = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"meu-hook"}]}]}}"#
    try original.write(to: cfg, atomically: true, encoding: .utf8)
    let script = casa.appendingPathComponent("ligar.sh")
    try AgentesHooks.scriptLigar.write(to: script, atomically: true, encoding: .utf8)

    func rodar(_ args: [String]) throws -> [String: Any] {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/bin/sh")
      p.arguments = [script.path] + args
      p.environment = ["HOME": casa.path, "PATH": "/usr/bin:/bin"]
      p.standardOutput = Pipe()
      try p.run()
      p.waitUntilExit()
      XCTAssertEqual(p.terminationStatus, 0)
      return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cfg)) as? [String: Any])
    }

    _ = try rodar([])
    let ligado = try rodar([])
    let hooks = try XCTUnwrap(ligado["hooks"] as? [String: Any])
    XCTAssertEqual(ligado["model"] as? String, "opus")
    XCTAssertEqual((hooks["Stop"] as? [Any])?.count, 2, "o hook do usuário fica e o nosso entra uma vez só")
    let permissao = try XCTUnwrap((hooks["PermissionRequest"] as? [[String: Any]])?.first)
    let entrada = try XCTUnwrap((permissao["hooks"] as? [[String: Any]])?.first)
    XCTAssertEqual(entrada["timeout"] as? Int, 120)
    XCTAssertTrue((entrada["command"] as? String)?.hasSuffix("jarvis-hook\" --permissao") == true)

    let desligado = try rodar(["--desligar"])
    XCTAssertEqual(
      (desligado["hooks"] as? [String: Any])?.keys.sorted(), ["Stop"])
    let backups = try FileManager.default.contentsOfDirectory(atPath: claude.path).filter { $0.contains("antes-jarvis") }
    XCTAssertFalse(backups.isEmpty)
  }
}
