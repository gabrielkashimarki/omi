import Foundation

/// WebSocket `/jarvis/mac` aberto o tempo todo: o Fly manda `{id, pedido}` quando o Jarvis usa o `mexer_no_mac`
/// e o Mac devolve `{id, resultado}`. Cai, espera (1 s dobrando até 60 s) e reconecta.
@MainActor
final class JarvisMac {
  static let shared = JarvisMac()
  private(set) var conectado = false
  private var laco: Task<Void, Never>?

  func ligar() {
    guard laco == nil else { return }
    laco = Task { [weak self] in await self?.manter() }
  }

  /// Espera da próxima tentativa (puro, testado).
  nonisolated static func espera(depois tentativas: Int) -> TimeInterval {
    min(60, pow(2, Double(max(0, tentativas - 1))))
  }

  private func manter() async {
    var falhas = 0
    while !Task.isCancelled {
      if JarvisCliente.chave == nil {
        // sem chave não há o que tentar; o Gabriel grava a chave e o laço acha sozinho
        try? await Task.sleep(for: .seconds(60))
        continue
      }
      let conectou = await sessao()
      conectado = false
      falhas = conectou ? 1 : falhas + 1
      try? await Task.sleep(for: .seconds(Self.espera(depois: falhas)))
    }
  }

  /// Uma conexão, do início até cair. Devolve se chegou a conectar.
  private func sessao() async -> Bool {
    guard var r = try? JarvisCliente.requisicao("/jarvis/mac") else { return false }
    var c = URLComponents(url: r.url!, resolvingAgainstBaseURL: true)!
    c.scheme = "wss"
    r.url = c.url
    // a conexão fica parada entre pedidos; quem derruba conexão morta é o ping de 25 s
    r.timeoutInterval = 300
    let ws = URLSession.shared.webSocketTask(with: r)
    ws.resume()
    defer { ws.cancel(with: .goingAway, reason: nil) }
    guard await ping(ws) else { return false }
    conectado = true
    log("Jarvis: conectado ao /jarvis/mac")
    // o Fly manda ping a cada 30 s; o nosso pega a conexão morta do lado de cá (Wi-Fi trocado, Mac acordando)
    let vigia = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(25))
        guard let self, await self.ping(ws) else {
          ws.cancel(with: .goingAway, reason: nil)
          return
        }
      }
    }
    defer { vigia.cancel() }
    while !Task.isCancelled {
      guard let m = try? await ws.receive() else { break }
      let texto: String
      switch m {
      case .string(let s): texto = s
      case .data(let d): texto = String(decoding: d, as: UTF8.self)
      @unknown default: continue
      }
      guard let j = (try? JSONSerialization.jsonObject(with: Data(texto.utf8))) as? [String: Any],
        let id = j["id"] as? String
      else { continue }
      let resultado = await JarvisMaos.executar(j["pedido"] as? [String: Any] ?? [:])
      guard let dados = try? JSONSerialization.data(withJSONObject: ["id": id, "resultado": resultado]) else {
        continue
      }
      try? await ws.send(.string(String(decoding: dados, as: UTF8.self)))
    }
    log("Jarvis: /jarvis/mac caiu")
    return true
  }

  private func ping(_ ws: URLSessionWebSocketTask) async -> Bool {
    await withCheckedContinuation { c in
      ws.sendPing { erro in c.resume(returning: erro == nil) }
    }
  }
}
