@preconcurrency import AVFoundation
import Foundation

/// Voz do Jarvis em pedaços: a fala é dividida por frase e a primeira já começa a tocar enquanto as outras sintetizam.
/// Padrão: TTS do Gemini (voz Charon) com todas as frases sintetizando em paralelo e tocando na ordem. A ElevenLabs
/// `eleven_v4_turbo` em streaming (primeiro byte ~0,4 s em 18/11, mas cara) só entra com o ajuste ligado nos Ajustes
/// e a chave no cofre de segredos do app. Toca pelo engine do `JarvisMicrofone`, para o cancelamento de eco tirar a
/// voz do microfone.
@MainActor
final class JarvisVoz {
  static let shared = JarvisVoz()
  static let servicoChave = "com.omi.desktop.elevenlabs"
  static let contaChave = "chave"
  /// Ajuste (UserDefaults) que liga a ElevenLabs; desligado, a voz é a do Gemini.
  nonisolated static let ajusteElevenLabs = "jarvis_voz_elevenlabs"
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
    let eleven =
      UserDefaults.standard.bool(forKey: Self.ajusteElevenLabs)
      ? DesktopKeychainStore.string(service: Self.servicoChave, account: Self.contaChave) : nil
    let gemini = APIKeyService.shared.effectiveGeminiKey
    guard !MeetingCopilotVoice.shared.muted, !frases.isEmpty, eleven != nil || gemini != nil else {
      if eleven == nil, gemini == nil { log("Jarvis: sem chave da ElevenLabs nem do Gemini, resposta não falada") }
      DispatchQueue.main.async { MainActor.assumeIsolated { aoTerminar() } }
      return
    }
    let relogio = Relogio(desde: desde)
    tarefa = Task { [weak self] in
      if let eleven {
        for frase in frases {
          guard !Task.isCancelled else { return }
          do {
            try await Self.elevenLabs(frase, chave: eleven) { relogio.marcar("ElevenLabs", $0) }
            continue
          } catch is CancellationError {
            return
          } catch {
            log("Jarvis: ElevenLabs falhou (\(error.localizedDescription)), frase vai pelo Gemini")
          }
          guard let gemini, let wav = await Self.gemini(frase, chave: gemini), let b = Self.buffer(wav: wav) else {
            continue
          }
          relogio.marcar("Gemini", b)
        }
      } else if let gemini {
        // o Gemini não tem streaming: todas as frases saem para síntese já, e cada uma toca assim que ela e as de
        // antes ficam prontas
        let sinteses = frases.map { f in Task { await Self.gemini(f, chave: gemini) } }
        defer { sinteses.forEach { $0.cancel() } }
        for s in sinteses {
          let wav = await s.value
          guard !Task.isCancelled else { return }
          if let wav, let b = Self.buffer(wav: wav) { relogio.marcar("Gemini", b) }
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

  /// WAV de uma frase pelo Gemini; falha vira `nil` (a frase fica sem voz, as outras seguem).
  private nonisolated static func gemini(_ frase: String, chave: String) async -> Data? {
    do {
      return try await MeetingCopilotVoice.synthesize(frase, key: chave)
    } catch {
      if !Task.isCancelled { log("Jarvis: TTS do Gemini falhou (\(type(of: error)))") }
      return nil
    }
  }

  // MARK: - Puro (testado)

  /// Frases para sintetizar uma a uma. Pedaço muito curto ("Ok.") vai junto com o seguinte, para não picotar.
  /// A primeira frase longa (mais de 12 palavras) quebra na vírgula, para o primeiro áudio sair mais cedo.
  nonisolated static func frases(_ texto: String) -> [String] {
    var saida = frasesInteiras(texto)
    if let primeira = saida.first, let (a, b) = quebraNaVirgula(primeira) {
      saida.replaceSubrange(0...0, with: [a, b])
    }
    return saida
  }

  /// Corta na primeira vírgula seguida de espaço que já deixa umas 4 palavras antes; nada se a frase for curta.
  nonisolated static func quebraNaVirgula(_ frase: String) -> (String, String)? {
    guard JarvisConversa.palavras(frase) > 12 else { return nil }
    var i = frase.startIndex
    while let v = frase[i...].firstIndex(of: ",") {
      let depois = frase.index(after: v)
      if depois < frase.endIndex, frase[depois].isWhitespace,
        JarvisConversa.palavras(String(frase[...v])) >= 4
      {
        let resto = frase[depois...].trimmingCharacters(in: .whitespaces)
        return resto.isEmpty ? nil : (String(frase[...v]), resto)
      }
      i = depois
    }
    return nil
  }

  private nonisolated static func frasesInteiras(_ texto: String) -> [String] {
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
