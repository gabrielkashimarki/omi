import AppKit
import os

/// Estado da conexão com o `/jarvis/mac` (puro, testado): quem cai ou não conecta ganha a espera da próxima tentativa.
struct JarvisLigacao {
  private(set) var conectado = false
  private(set) var falhas = 0

  mutating func conectou() {
    conectado = true
    falhas = 0
  }

  /// Sem pong no prazo, erro no receive, no send ou no sendPing, ou tentativa que não conectou.
  /// Devolve a espera até a próxima tentativa.
  mutating func caiu() -> TimeInterval {
    falhas = conectado ? 1 : falhas + 1
    conectado = false
    return JarvisMac.espera(depois: falhas)
  }

  /// Mac acordou ou a rede voltou: a próxima tentativa sai sem a espera acumulada.
  mutating func cutucado() { falhas = 0 }
}

/// WebSocket `/jarvis/mac` aberto o tempo todo: o Fly manda `{id, pedido}` quando o Jarvis usa o `mexer_no_mac`
/// e o Mac devolve `{id, resultado}`. Cai, espera (1 s dobrando até 60 s) e reconecta.
@MainActor
final class JarvisMac {
  static let shared = JarvisMac()
  private var ligacao = JarvisLigacao()
  var conectado: Bool { ligacao.conectado }
  private var laco: Task<Void, Never>?
  private var atual: URLSessionWebSocketTask?
  private var dormindo: Task<Void, Never>?
  private var observadores: [NSObjectProtocol] = []

  func ligar() {
    guard laco == nil else { return }
    laco = Task { [weak self] in await self?.manter() }
    // conexão de antes do sono ou da queda de rede está morta mesmo que o TCP não tenha avisado
    observadores = [
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.cutucar("Mac acordou") } },
      NotificationCenter.default.addObserver(forName: .redeVoltou, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.cutucar("rede voltou") }
      },
    ]
  }

  /// Espera da próxima tentativa (puro, testado).
  nonisolated static func espera(depois tentativas: Int) -> TimeInterval {
    min(60, pow(2, Double(max(0, tentativas - 1))))
  }

  /// Derruba a conexão atual (ou acorda a espera) e reconecta já.
  private func cutucar(_ motivo: String) {
    log("Jarvis: \(motivo), reconectando o /jarvis/mac")
    ligacao.cutucado()
    atual?.cancel(with: .goingAway, reason: nil)
    dormindo?.cancel()
  }

  private func manter() async {
    while !Task.isCancelled {
      if JarvisCliente.chave == nil {
        // sem chave não há o que tentar; o Gabriel grava a chave e o laço acha sozinho
        try? await Task.sleep(for: .seconds(60))
        continue
      }
      await sessao()
      let segundos = ligacao.caiu()
      let t = Task { _ = try? await Task.sleep(for: .seconds(segundos)) }
      dormindo = t
      await t.value
      dormindo = nil
    }
  }

  /// Uma conexão, do início até cair.
  private func sessao() async {
    guard var r = try? JarvisCliente.requisicao("/jarvis/mac") else { return }
    var c = URLComponents(url: r.url!, resolvingAgainstBaseURL: true)!
    c.scheme = "wss"
    r.url = c.url
    // a conexão fica parada entre pedidos; quem derruba conexão morta é o ping de 25 s
    r.timeoutInterval = 300
    let ws = URLSession.shared.webSocketTask(with: r)
    ws.resume()
    atual = ws
    defer {
      ws.cancel(with: .goingAway, reason: nil)
      atual = nil
    }
    guard await ping(ws) else {
      log("Jarvis: /jarvis/mac não conectou")
      return
    }
    ligacao.conectou()
    log("Jarvis: conectado ao /jarvis/mac")
    // conexão meio aberta (máquina do Fly reiniciada, Wi-Fi trocado) não dá erro no receive: só o ping sem pong
    // denuncia. Cancelar a task faz o receive lançar e o laço abaixo sai.
    let vigia = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(25))
        guard !Task.isCancelled, let self else { return }
        if await !self.ping(ws) {
          log("Jarvis: /jarvis/mac sem pong em \(Self.prazoPong) s")
          ws.cancel(with: .goingAway, reason: nil)
          return
        }
      }
    }
    defer { vigia.cancel() }
    while !Task.isCancelled {
      let m: URLSessionWebSocketTask.Message
      do {
        m = try await ws.receive()
      } catch {
        log("Jarvis: receive do /jarvis/mac falhou: \(error.localizedDescription)")
        break
      }
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
      do {
        try await ws.send(.string(String(decoding: dados, as: UTF8.self)))
      } catch {
        log("Jarvis: send do /jarvis/mac falhou: \(error.localizedDescription)")
        break
      }
    }
    log("Jarvis: /jarvis/mac caiu")
  }

  static let prazoPong = 10

  private func ping(_ ws: URLSessionWebSocketTask) async -> Bool {
    await Self.comPrazo(.seconds(Self.prazoPong)) { responder in
      ws.sendPing { erro in responder(erro == nil) }
    }
  }

  /// Espera a primeira resposta de `registrar` até `prazo`; sem resposta no prazo vale `false` (puro, testado).
  /// O URLSession pode chamar o callback do ping duas vezes (pong e depois cancelamento) e um segundo resume da
  /// continuation derruba o app, então só a primeira resposta vale.
  nonisolated static func comPrazo(
    _ prazo: Duration, _ registrar: @Sendable (@escaping @Sendable (Bool) -> Void) -> Void
  ) async -> Bool {
    let respondido = OSAllocatedUnfairLock(initialState: false)
    return await withCheckedContinuation { c in
      let responder: @Sendable (Bool) -> Void = { ok in
        let primeiro = respondido.withLock { ja in
          defer { ja = true }
          return !ja
        }
        if primeiro { c.resume(returning: ok) }
      }
      registrar(responder)
      Task {
        try? await Task.sleep(for: prazo)
        responder(false)
      }
    }
  }
}
