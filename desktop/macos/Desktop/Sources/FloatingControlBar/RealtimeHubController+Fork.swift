import Foundation

// Fork: ferramentas de voz que o upstream não tem.
// perguntar_cerebro chama o MCP "brain" do ~/.omi/mcp.json (o mesmo que o chat digitado usa).
extension RealtimeHubController {
  static let cerebroServidor = "brain"
  static let cerebroFerramenta = "buscar_contexto"
  // ponytail: corte fixo para caber no contexto da voz; resumir no servidor se 4 mil cortar demais.
  static let cerebroLimiteCaracteres = 4000

  func perguntarCerebro(pergunta: String, cliente: String?) async -> AuthorizedRealtimeToolExecutionResult {
    await LocalMcpStore.refreshExpiredTokens()
    guard
      let entrada = LocalMcpStore.readAllServers()[Self.cerebroServidor] as? [String: Any],
      let urlTexto = entrada["url"] as? String, let url = URL(string: urlTexto),
      let token = (entrada["auth"] as? [String: Any])?["access_token"] as? String
        ?? entrada["token"] as? String
    else {
      return .succeeded("O Cérebro não está conectado neste Mac (servidor 'brain' ausente em ~/.omi/mcp.json).")
    }
    var argumentos: [String: Any] = ["pergunta": pergunta]
    if let cliente, !cliente.isEmpty { argumentos["cliente"] = cliente }
    let corpo: [String: Any] = [
      "jsonrpc": "2.0", "id": 1, "method": "tools/call",
      "params": ["name": Self.cerebroFerramenta, "arguments": argumentos],
    ]
    var pedido = URLRequest(url: url, timeoutInterval: 25)
    pedido.httpMethod = "POST"
    pedido.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
    pedido.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    pedido.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
    let t0 = Date()
    do {
      let (dados, resposta) = try await URLSession.shared.data(for: pedido)
      let ms = Int(Date().timeIntervalSince(t0) * 1000)
      let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
      guard status == 200 else {
        log("RealtimeHub: perguntar_cerebro HTTP \(status) em \(ms)ms")
        return .succeeded("A busca no Cérebro falhou (HTTP \(status)).")
      }
      let texto = Self.textoDoResultadoMcp(dados)
      log("RealtimeHub: perguntar_cerebro OK em \(ms)ms (\(texto.count) chars)")
      if texto.isEmpty { return .succeeded("O Cérebro não achou nada sobre isso.") }
      return .succeeded(String(texto.prefix(Self.cerebroLimiteCaracteres)))
    } catch {
      log("RealtimeHub: perguntar_cerebro falhou: \(error.localizedDescription)")
      return .succeeded("A busca no Cérebro falhou. Tente de novo.")
    }
  }

  /// Aceita resposta JSON direta ou em SSE (`data: {...}`), como o transporte HTTP do MCP permite.
  nonisolated static func textoDoResultadoMcp(_ dados: Data) -> String {
    var bruto = dados
    if let s = String(data: dados, encoding: .utf8), !s.hasPrefix("{"),
      let linha = s.split(separator: "\n").last(where: { $0.hasPrefix("data:") })
    {
      bruto = Data(linha.dropFirst(5).utf8)
    }
    guard
      let json = try? JSONSerialization.jsonObject(with: bruto) as? [String: Any],
      let conteudo = (json["result"] as? [String: Any])?["content"] as? [[String: Any]]
    else { return "" }
    return conteudo.compactMap { $0["text"] as? String }.joined(separator: "\n")
  }
}
