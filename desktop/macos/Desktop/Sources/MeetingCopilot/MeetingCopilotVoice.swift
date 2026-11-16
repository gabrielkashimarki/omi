import AVFoundation
import Foundation

/// Fala no fone a primeira linha da resposta do copiloto.
/// Com a chave própria do Gemini, usa o TTS do Gemini direto no Google com a voz Charon (a mesma da voz
/// ao vivo do Omi); sem chave, cai na voz escolhida do Omi (`speakOneShot`, pelo servidor do Omi).
@MainActor
final class MeetingCopilotVoice {
  static let shared = MeetingCopilotVoice()
  private static let mutedKey = "meetingCopilotMuted"
  private static let model = "gemini-3.8-flash-tts"
  private var player: AVAudioPlayer?
  private var speaking: Task<Void, Never>?

  var muted: Bool {
    get { UserDefaults.standard.bool(forKey: Self.mutedKey) }
    set {
      UserDefaults.standard.set(newValue, forKey: Self.mutedKey)
      if newValue { stop() }
    }
  }

  func speak(_ text: String) {
    let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !muted, !line.isEmpty else { return }
    guard let key = APIKeyService.shared.effectiveGeminiKey else {
      FloatingBarVoicePlaybackService.shared.speakOneShot(line)
      return
    }
    stop()
    speaking = Task { [weak self] in
      do {
        let audio = try await Self.synthesize(line, key: key)
        guard let self, !Task.isCancelled, !self.muted else { return }
        let player = try AVAudioPlayer(data: audio)
        self.player = player
        player.play()
      } catch is CancellationError {
      } catch {
        log("MeetingCopilotVoice: TTS do Gemini falhou (\(type(of: error))), usando a voz do Omi")
        guard let self, !self.muted else { return }
        FloatingBarVoicePlaybackService.shared.speakOneShot(line)
      }
    }
  }

  func stop() {
    speaking?.cancel()
    speaking = nil
    player?.stop()
    player = nil
  }

  /// Áudio pronto para tocar (WAV).
  private nonisolated static func synthesize(_ text: String, key: String) async throws -> Data {
    var request = URLRequest(url: URL(string: "\(GeminiClient.directBaseURL)\(model):generateContent")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
    let body: [String: Any] = [
      "contents": [["parts": [["text": "Diga em português do Brasil, com naturalidade: \(text)"]]]],
      "generationConfig": [
        "responseModalities": ["AUDIO"],
        "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": "Charon"]]],
      ],
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let candidates = json["candidates"] as? [[String: Any]],
      let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]],
      let inline = parts.compactMap({ $0["inlineData"] as? [String: Any] }).first,
      let base64 = inline["data"] as? String, let pcm = Data(base64Encoded: base64), !pcm.isEmpty
    else { throw URLError(.badServerResponse) }
    // O TTS 3.8 já devolve WAV; o 2.5 devolvia PCM cru.
    return (inline["mimeType"] as? String)?.contains("wav") == true ? pcm : wav(pcm)
  }

  private nonisolated static func wav(_ pcm: Data, rate: UInt32 = 24_000) -> Data {
    func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    var header = Data("RIFF".utf8) + le(UInt32(36 + pcm.count)) + Data("WAVEfmt ".utf8)
    header += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1)) + le(rate) + le(rate * 2) + le(UInt16(2)) + le(UInt16(16))
    header += Data("data".utf8) + le(UInt32(pcm.count))
    return header + pcm
  }
}
