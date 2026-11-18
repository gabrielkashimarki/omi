import AVFoundation
import Foundation

/// Fala no fone a primeira linha da resposta do copiloto.
/// Usa o TTS do Gemini direto no Google com a voz Charon e a chave própria do Gemini; sem chave, fica
/// em silêncio (a voz do Omi saiu do app).
@MainActor
final class MeetingCopilotVoice {
  static let shared = MeetingCopilotVoice()
  private static let mutedKey = "meetingCopilotMuted"
  private nonisolated static let model = "gemini-3.8-flash-tts"
  private var player: AVAudioPlayer?
  private var speaking: Task<Void, Never>?

  var muted: Bool {
    get { UserDefaults.standard.bool(forKey: Self.mutedKey) }
    set {
      UserDefaults.standard.set(newValue, forKey: Self.mutedKey)
      if newValue { stop() }
    }
  }

  /// Enquanto o TTS sintetiza ou toca: o microfone do Jarvis não abre (não pode ouvir a própria voz).
  var falando: Bool { speaking != nil }

  /// `aoTerminar` vem depois do fim do áudio, ou logo se não houver voz (mudo, sem chave, TTS falhou);
  /// nunca quando a fala é interrompida por `stop()`.
  func speak(_ text: String, aoTerminar: (@MainActor () -> Void)? = nil) {
    let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let semVoz = { DispatchQueue.main.async { MainActor.assumeIsolated { aoTerminar?() } } }
    guard !muted, !line.isEmpty else { return semVoz() }
    guard let key = APIKeyService.shared.effectiveGeminiKey else {
      log("MeetingCopilotVoice: sem chave do Gemini, resposta não falada")
      return semVoz()
    }
    stop()
    speaking = Task { [weak self] in
      do {
        let audio = try await Self.synthesize(line, key: key)
        guard let self, !Task.isCancelled, !self.muted else { return }
        let player = try AVAudioPlayer(data: audio)
        self.player = player
        player.play()
        // folga de 0,4 s: o fim do som no alto-falante não entra no microfone
        try await Task.sleep(for: .seconds(player.duration + 0.4))
        guard !Task.isCancelled, self.player === player else { return }
        self.player = nil
        self.speaking = nil
        aoTerminar?()
      } catch is CancellationError {
      } catch {
        log("MeetingCopilotVoice: TTS do Gemini falhou (\(type(of: error)))")
        guard let self, !Task.isCancelled else { return }
        self.speaking = nil
        aoTerminar?()
      }
    }
  }

  func stop() {
    speaking?.cancel()
    speaking = nil
    player?.stop()
    player = nil
  }

  /// Corpo do pedido de TTS (puro, testado). O texto vai sozinho: o 3.8 lê o campo `text` ao pé da letra, e a
  /// instrução de estilo no texto saía falada. O estilo vai na anotação `speech_metadata` (Interactions API); o
  /// `systemInstruction` o modelo recusa ("Developer instruction is not enabled", testado em 18/11). O idioma ele detecta.
  nonisolated static func corpo(_ text: String) -> [String: Any] {
    [
      "model": model,
      "input": [
        [
          "type": "user_input",
          "content": [
            [
              "type": "text", "text": text,
              "annotations": [["type": "speech_metadata", "style": "natural, conversational Brazilian Portuguese"]],
            ]
          ],
        ]
      ],
      "response_format": ["type": "audio"],
      "generation_config": ["speech_config": [["voice": "Charon"]]],
    ]
  }

  /// Áudio pronto para tocar (WAV).
  nonisolated static func synthesize(_ text: String, key: String) async throws -> Data {
    var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
    request.httpBody = try JSONSerialization.data(withJSONObject: corpo(text))
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let steps = json["steps"] as? [[String: Any]],
      let audio = steps.flatMap({ $0["content"] as? [[String: Any]] ?? [] }).first(where: { $0["type"] as? String == "audio" }),
      let base64 = audio["data"] as? String, let pcm = Data(base64Encoded: base64), !pcm.isEmpty
    else { throw URLError(.badServerResponse) }
    // O padrão é WAV; PCM cru (audio/l16) ganha o cabeçalho.
    return (audio["mime_type"] as? String)?.contains("wav") != false ? pcm : wav(pcm)
  }

  private nonisolated static func wav(_ pcm: Data, rate: UInt32 = 24_000) -> Data {
    func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    var header = Data("RIFF".utf8) + le(UInt32(36 + pcm.count)) + Data("WAVEfmt ".utf8)
    header += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1)) + le(rate) + le(rate * 2) + le(UInt16(2)) + le(UInt16(16))
    header += Data("data".utf8) + le(UInt32(pcm.count))
    return header + pcm
  }
}
