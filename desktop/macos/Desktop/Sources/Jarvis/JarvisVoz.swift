@preconcurrency import AVFoundation
import Foundation

/// Voz do Jarvis em pedaços: a fala é dividida por frase e a primeira já começa a tocar enquanto as outras sintetizam.
/// ElevenLabs `eleven_v4_turbo` em streaming (PCM 24 kHz, primeiro byte ~0,4 s em 18/11) com a chave no cofre de
/// segredos do app; sem ela, o TTS do Gemini por frase (~3,6 s por frase). Toca pelo engine do `JarvisMicrofone`, para
/// o cancelamento de eco tirar a voz do microfone.
@MainActor
final class JarvisVoz {
  static let shared = JarvisVoz()
  static let servicoChave = "com.omi.desktop.elevenlabs"
  static let contaChave = "chave"
  /// Voz "Dani" do `config/voz.php` da BDR (`voz_padrao_elevenlabs`) e o mesmo modelo do agente de ligação.
  nonisolated static let vozElevenLabs = "PznTnBc8X6pvixs9UkQm"
  nonisolated static let modeloElevenLabs = "eleven_v4_turbo"
  /// 100 ms de PCM 24 kHz: o pedaço que vai tocando enquanto o resto chega.
  private nonisolated static let pedaco = 4800

  private var tarefa: Task<Void, Never>?
  var falando: Bool { tarefa != nil }

  /// `desde`: quando o turno do Gabriel acabou; o log mostra quanto levou até o primeiro áudio.
  /// `aoTerminar` vem depois do fim do áudio, ou logo se não houver voz; nunca quando a fala é cortada por `parar()`.
  func falar(_ texto: String, desde: Date? = nil, aoTerminar: @escaping @MainActor () -> Void) {
    parar()
    let frases = Self.frases(texto)
    let eleven = DesktopKeychainStore.string(service: Self.servicoChave, account: Self.contaChave)
    let gemini = APIKeyService.shared.effectiveGeminiKey
    guard !MeetingCopilotVoice.shared.muted, !frases.isEmpty, eleven != nil || gemini != nil else {
      if eleven == nil, gemini == nil { log("Jarvis: sem chave da ElevenLabs nem do Gemini, resposta não falada") }
      DispatchQueue.main.async { MainActor.assumeIsolated { aoTerminar() } }
      return
    }
    let relogio = Relogio(desde: desde)
    tarefa = Task { [weak self] in
      for frase in frases {
        guard !Task.isCancelled else { return }
        if let eleven {
          do {
            try await Self.elevenLabs(frase, chave: eleven) { relogio.marcar("ElevenLabs", $0) }
            continue
          } catch is CancellationError {
            return
          } catch {
            log("Jarvis: ElevenLabs falhou (\(error.localizedDescription)), frase vai pelo Gemini")
          }
        }
        guard let gemini else { continue }
        do {
          let wav = try await MeetingCopilotVoice.synthesize(frase, key: gemini)
          guard !Task.isCancelled else { return }
          if let b = Self.buffer(wav: wav) { relogio.marcar("Gemini", b) }
        } catch {
          log("Jarvis: TTS do Gemini falhou (\(type(of: error)))")
        }
      }
      // marca de fim: toca depois de tudo o que foi agendado (ou volta na hora se a voz for cortada)
      await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        JarvisMicrofone.shared.tocar(Self.silencio) { c.resume() }
      }
      guard let self, !Task.isCancelled else { return }
      self.tarefa = nil
      aoTerminar()
    }
  }

  func parar() {
    tarefa?.cancel()
    tarefa = nil
    JarvisMicrofone.shared.pararVoz()
  }

  /// Agenda cada pedaço e registra no log o tempo até o primeiro.
  private final class Relogio: @unchecked Sendable {
    private let desde: Date?
    private var primeiro = true
    init(desde: Date?) { self.desde = desde }

    /// Chamado de dentro da tarefa da fala: cortada a fala, o pedaço que ainda chega não toca.
    func marcar(_ motor: String, _ buffer: AVAudioPCMBuffer) {
      guard !Task.isCancelled else { return }
      if primeiro {
        primeiro = false
        if let desde {
          log("Jarvis: latência fim do turno → primeiro áudio \(Int(Date().timeIntervalSince(desde) * 1000)) ms (\(motor))")
        }
      }
      JarvisMicrofone.shared.tocar(buffer) {}
    }
  }

  // MARK: - Puro (testado)

  /// Frases para sintetizar uma a uma. Pedaço muito curto ("Ok.") vai junto com o seguinte, para não picotar.
  nonisolated static func frases(_ texto: String) -> [String] {
    var saida: [String] = []
    var atual = ""
    let fim: Set<Character> = [".", "!", "?", "…"]
    let chars = Array(texto)
    for (i, c) in chars.enumerated() {
      atual.append(c)
      let proximoEspaco = i + 1 < chars.count && chars[i + 1].isWhitespace
      if fim.contains(c), proximoEspaco {
        let t = atual.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 12 {
          saida.append(t)
          atual = ""
        }
      }
    }
    let resto = atual.trimmingCharacters(in: .whitespacesAndNewlines)
    if !resto.isEmpty { saida.append(resto) }
    return saida
  }

  /// PCM 16 bits little-endian em buffer de float para o `AVAudioPlayerNode` (24 kHz mono).
  nonisolated static func buffer(pcm: Data) -> AVAudioPCMBuffer? {
    let n = pcm.count / 2
    guard n > 0, let b = AVAudioPCMBuffer(pcmFormat: JarvisMicrofone.formatoVoz, frameCapacity: AVAudioFrameCount(n))
    else { return nil }
    b.frameLength = AVAudioFrameCount(n)
    let destino = b.floatChannelData![0]
    pcm.withUnsafeBytes { (bruto: UnsafeRawBufferPointer) in
      for i in 0..<n {
        let v = Int16(littleEndian: bruto.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
        destino[i] = Float(v) / 32768
      }
    }
    return b
  }

  /// WAV do Gemini (24 kHz, 16 bits, mono): acha o bloco `data` e converte.
  nonisolated static func buffer(wav: Data) -> AVAudioPCMBuffer? {
    let bytes = [UInt8](wav)
    var i = 12
    while i + 8 <= bytes.count {
      let id = String(decoding: bytes[i..<i + 4], as: UTF8.self)
      let tamanho = Int(bytes[i + 4]) | Int(bytes[i + 5]) << 8 | Int(bytes[i + 6]) << 16 | Int(bytes[i + 7]) << 24
      if id == "fmt ", i + 16 <= bytes.count {
        let taxa = Int(bytes[i + 12]) | Int(bytes[i + 13]) << 8 | Int(bytes[i + 14]) << 16
        guard taxa == 24_000 else {
          log("Jarvis: WAV do Gemini em \(taxa) Hz, esperado 24 kHz")
          return nil
        }
      }
      if id == "data" {
        let fimDados = min(bytes.count, i + 8 + tamanho)
        return buffer(pcm: wav.subdata(in: (i + 8)..<fimDados))
      }
      i += 8 + tamanho + (tamanho & 1)
    }
    return nil
  }

  nonisolated(unsafe) private static let silencio: AVAudioPCMBuffer = {
    let b = AVAudioPCMBuffer(pcmFormat: JarvisMicrofone.formatoVoz, frameCapacity: 2400)!
    b.frameLength = 2400  // 0,1 s: o fim do som sai do alto-falante antes de a escuta voltar ao normal
    return b
  }()

  // MARK: - ElevenLabs

  /// Streaming HTTP da ElevenLabs: entrega pedaços de 100 ms conforme chegam.
  nonisolated static func elevenLabs(
    _ texto: String, chave: String, pedacoPronto: @Sendable (AVAudioPCMBuffer) -> Void
  ) async throws {
    var r = URLRequest(
      url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(vozElevenLabs)/stream?output_format=pcm_24000")!)
    r.httpMethod = "POST"
    r.timeoutInterval = 15
    r.setValue(chave, forHTTPHeaderField: "xi-api-key")
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.httpBody = try JSONSerialization.data(withJSONObject: ["text": texto, "model_id": modeloElevenLabs])
    let (bytes, resposta) = try await URLSession.shared.bytes(for: r)
    guard (resposta as? HTTPURLResponse)?.statusCode == 200 else {
      throw URLError(.badServerResponse, userInfo: ["status": (resposta as? HTTPURLResponse)?.statusCode ?? 0])
    }
    var acumulado = Data()
    acumulado.reserveCapacity(pedaco)
    for try await byte in bytes {
      acumulado.append(byte)
      if acumulado.count >= pedaco {
        try Task.checkCancellation()
        if let b = buffer(pcm: acumulado) { pedacoPronto(b) }
        acumulado.removeAll(keepingCapacity: true)
      }
    }
    try Task.checkCancellation()
    if let b = buffer(pcm: acumulado) { pedacoPronto(b) }
  }
}
