import Foundation

/// Microfone do Jarvis: uma segunda `AudioCaptureService` (CoreAudio, PCM 16 bits a 16 kHz), separada da gravação
/// do Omi. Fica ligada só enquanto alguém escuta (o Hey Jarvis ou a legenda).
final class JarvisMicrofone: @unchecked Sendable {
  static let shared = JarvisMicrofone()
  private let fila = DispatchQueue(label: "jarvis.microfone")
  private var captura: AudioCaptureService?
  private var ouvintes: [String: @Sendable (Data) -> Void] = [:]  // só na `fila`

  func assinar(_ nome: String, _ ouvinte: @escaping @Sendable (Data) -> Void) {
    fila.async {
      self.ouvintes[nome] = ouvinte
      guard self.captura == nil else { return }
      guard AudioCaptureService.checkPermission() else {
        log("Jarvis: sem permissão de microfone")
        return
      }
      let c = AudioCaptureService()
      self.captura = c
      Task {
        do {
          try await c.startCapture(onAudioChunk: { [weak self] dados in self?.entregar(dados) })
        } catch {
          log("Jarvis: microfone não abriu (\(type(of: error)))")
          self.fila.async { if self.captura === c { self.captura = nil } }
        }
      }
    }
  }

  func cancelar(_ nome: String) {
    fila.async {
      self.ouvintes[nome] = nil
      guard self.ouvintes.isEmpty, let c = self.captura else { return }
      self.captura = nil
      c.stopCapture()
    }
  }

  private func entregar(_ dados: Data) {
    fila.async { for o in self.ouvintes.values { o(dados) } }
  }
}

/// Legenda ao vivo da fala do Gabriel: Deepgram nova-3 pt-BR em streaming, com parciais, a mesma de 11/10.
/// A frase termina no `speech_final` (pausa de 0,8 s) ou no `UtteranceEnd`.
@MainActor
final class JarvisLegenda {
  // sem smart_format: ele troca "sexta" por "6º"
  static let url = URL(
    string: "wss://api.deepgram.com/v1/listen?model=nova-3&language=pt-BR&interim_results=true&punctuate=true"
      + "&encoding=linear16&sample_rate=16000&channels=1&endpointing=800&utterance_end_ms=1500&vad_events=true")!

  /// Junta finais e parciais de um turno (puro, testado).
  struct Acumulador: Equatable {
    var finais = ""

    /// Devolve o texto da legenda até agora e se a frase acabou.
    mutating func receber(_ j: [String: Any]) -> (texto: String, terminou: Bool)? {
      if j["type"] as? String == "UtteranceEnd" {
        return finais.isEmpty ? nil : (finais, true)
      }
      guard j["type"] as? String == "Results",
        let alt = ((j["channel"] as? [String: Any])?["alternatives"] as? [[String: Any]])?.first
      else { return nil }
      let texto = (alt["transcript"] as? String ?? "").trimmingCharacters(in: .whitespaces)
      if j["is_final"] as? Bool == true {
        if !texto.isEmpty { finais = finais.isEmpty ? texto : finais + " " + texto }
        if finais.isEmpty { return nil }
        return (finais, j["speech_final"] as? Bool == true)
      }
      guard !texto.isEmpty else { return nil }
      return (finais.isEmpty ? texto : finais + " " + texto, false)
    }
  }

  var aoOuvir: ((String) -> Void)?
  var aoTerminar: ((String) -> Void)?
  var aoFalhar: ((String) -> Void)?
  private var ws: URLSessionWebSocketTask?
  private var acumulador = Acumulador()

  var ouvindo: Bool { ws != nil }

  func comecar() {
    parar()
    guard let chave = APIKeyService.byokKey(.deepgram) else {
      aoFalhar?("Sem chave do Deepgram: digite o pedido")
      return
    }
    var r = URLRequest(url: Self.url)
    r.setValue("Token \(chave)", forHTTPHeaderField: "Authorization")
    let ws = URLSession.shared.webSocketTask(with: r)
    self.ws = ws
    acumulador = Acumulador()
    ws.resume()
    JarvisMicrofone.shared.assinar("legenda") { dados in ws.send(.data(dados)) { _ in } }
    Task { [weak self] in await self?.ler(ws) }
  }

  func parar() {
    guard let ws else { return }
    self.ws = nil
    JarvisMicrofone.shared.cancelar("legenda")
    ws.send(.string(#"{"type":"CloseStream"}"#)) { _ in }
    ws.cancel(with: .normalClosure, reason: nil)
  }

  private func ler(_ ws: URLSessionWebSocketTask) async {
    while self.ws === ws {
      guard let m = try? await ws.receive() else {
        if self.ws === ws {
          parar()
          aoFalhar?("Sem legenda: o Deepgram não respondeu")
        }
        return
      }
      guard case .string(let s) = m, self.ws === ws,
        let j = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any],
        let r = acumulador.receber(j)
      else { continue }
      aoOuvir?(r.texto)
      if r.terminou {
        parar()
        aoTerminar?(r.texto)
      }
    }
  }
}
