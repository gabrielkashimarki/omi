@preconcurrency import AVFoundation
import Foundation

/// Microfone e alto-falante do Jarvis num `AVAudioEngine` só, separado da gravação do Omi. O microfone entrega PCM
/// 16 bits a 16 kHz mono; fica ligado só enquanto alguém escuta (o Hey Jarvis ou a legenda).
/// Com a legenda fora de reunião, liga o voice processing do macOS: a voz do Jarvis toca pelo mesmo engine e o
/// cancelamento de eco tira ela do microfone, então dá para interromper o Jarvis falando por cima.
final class JarvisMicrofone: @unchecked Sendable {
  static let shared = JarvisMicrofone()
  /// Formato da voz que toca (`tocar`): o PCM de 24 kHz da ElevenLabs e do Gemini.
  static let formatoVoz = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
  private static let formatoSaida = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

  private let fila = DispatchQueue(label: "jarvis.microfone")
  // tudo abaixo só na `fila`
  private var ouvintes: [String: @Sendable (Data) -> Void] = [:]
  private var comEco: Set<String> = []
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var montado: (mic: Bool, eco: Bool)?
  private var tocando = 0

  func assinar(_ nome: String, comEco eco: Bool = false, _ ouvinte: @escaping @Sendable (Data) -> Void) {
    fila.async {
      guard AudioCaptureService.checkPermission() else {
        log("Jarvis: sem permissão de microfone")
        return
      }
      self.ouvintes[nome] = ouvinte
      if eco { self.comEco.insert(nome) } else { self.comEco.remove(nome) }
      self.montar()
    }
  }

  func cancelar(_ nome: String) {
    fila.async {
      self.ouvintes[nome] = nil
      self.comEco.remove(nome)
      self.montar()
    }
  }

  /// Agenda um pedaço da voz; `tocou` vem quando ele acaba de tocar (ou é descartado por `pararVoz`).
  func tocar(_ buffer: AVAudioPCMBuffer, tocou: @escaping @Sendable () -> Void) {
    fila.async {
      self.tocando += 1
      self.montar()
      guard let player = self.player else {
        self.tocando -= 1
        return tocou()
      }
      // singleton: a captura forte não vaza
      player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
        self.fila.async {
          self.tocando -= 1
          self.montar()
        }
        tocou()
      }
      if !player.isPlaying { player.play() }
    }
  }

  /// Corta a voz na hora (interrupção, Encerrar, pedido novo).
  func pararVoz() {
    fila.async { self.player?.stop() }
  }

  /// Sobe, troca ou derruba o engine conforme quem usa. Trocar o modo (eco ou microfone) recria o engine.
  private func montar() {
    let mic = !ouvintes.isEmpty
    let eco = mic && !comEco.isEmpty
    guard mic || tocando > 0 else {
      derrubar()
      return
    }
    if let m = montado, m.mic == mic, m.eco == eco || !mic { return }
    if tocando > 0, montado != nil, !mic { return }  // a voz acaba antes: não corta por causa do microfone
    derrubar()
    let e = AVAudioEngine()
    let p = AVAudioPlayerNode()
    e.attach(p)
    e.connect(p, to: e.mainMixerNode, format: Self.formatoVoz)
    do {
      if mic {
        let entrada = e.inputNode
        if eco {
          try entrada.setVoiceProcessingEnabled(true)
          // a música e a chamada do Mac não abaixam enquanto o Jarvis ouve
          entrada.voiceProcessingOtherAudioDuckingConfiguration = .init(
            enableAdvancedDucking: false, duckingLevel: .min)
        }
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0,
          let mono = AVAudioFormat(standardFormatWithSampleRate: formato.sampleRate, channels: 1),
          let conversor = AVAudioConverter(from: mono, to: Self.formatoSaida)
        else { throw URLError(.cannotOpenFile) }
        entrada.installTap(onBus: 0, bufferSize: 1600, format: formato) { [weak self] buffer, _ in
          guard let dados = Self.converter(buffer, mono: mono, conversor: conversor) else { return }
          guard let self else { return }
          self.fila.async { for o in self.ouvintes.values { o(dados) } }
        }
      }
      try e.start()
    } catch {
      log("Jarvis: microfone não abriu (\(error.localizedDescription))")
      e.stop()
      return
    }
    engine = e
    player = p
    montado = (mic, eco)
    log("Jarvis: áudio ligado (microfone \(mic), cancelamento de eco \(eco))")
  }

  private func derrubar() {
    guard let e = engine else { return }
    player?.stop()
    if montado?.mic == true { e.inputNode.removeTap(onBus: 0) }
    e.stop()
    engine = nil
    player = nil
    montado = nil
  }

  /// Canal 0 (com voice processing o macOS pode entregar vários; o primeiro é o tratado) em PCM 16 kHz mono.
  private static func converter(_ buffer: AVAudioPCMBuffer, mono: AVAudioFormat, conversor: AVAudioConverter) -> Data? {
    guard let origem = buffer.floatChannelData?[0], buffer.frameLength > 0,
      let entrada = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength)
    else { return nil }
    entrada.frameLength = buffer.frameLength
    entrada.floatChannelData![0].update(from: origem, count: Int(buffer.frameLength))
    let capacidade = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / mono.sampleRate) + 32
    guard let saida = AVAudioPCMBuffer(pcmFormat: formatoSaida, frameCapacity: capacidade) else { return nil }
    nonisolated(unsafe) var entregue = false
    var erro: NSError?
    conversor.convert(to: saida, error: &erro) { _, status in
      if entregue {
        status.pointee = .noDataNow
        return nil
      }
      entregue = true
      status.pointee = .haveData
      return entrada
    }
    guard erro == nil, saida.frameLength > 0, let int16 = saida.int16ChannelData?[0] else { return nil }
    return Data(bytes: int16, count: Int(saida.frameLength) * 2)
  }
}

/// Legenda ao vivo da fala do Gabriel: Deepgram Flux (`flux-general-multi` com dica pt-BR, o mesmo da URA da BDR).
/// O Flux decide o fim do turno (`EndOfTurn`, `eot_threshold` 0,7): ~0,8 a 1,2 s depois da fala, contra ~1,6 s do
/// nova-3 com `endpointing` de 1,2 s (medido com o `say` em 18/11). O socket segue aberto entre turnos; quem usa
/// decide quando parar.
@MainActor
final class JarvisLegenda {
  nonisolated static let url = URL(
    string: "wss://api.deepgram.com/v2/listen?model=flux-general-multi&language_hint=pt-BR&encoding=linear16"
      + "&sample_rate=16000&eot_threshold=0.7")!
  /// 80 ms de PCM 16 kHz por envio, como a Deepgram recomenda (em 20 ms o Flux fechava ~110 ms depois, BDR 25/10).
  nonisolated static let quadro = 2560

  /// Texto do turno a partir do `TurnInfo` do Flux (puro, testado). O `transcript` já é o turno inteiro até ali.
  struct Acumulador: Equatable {
    var textoAteAgora = ""

    /// Devolve o texto da legenda até agora e se o turno acabou. Depois do fim, o próximo turno começa vazio.
    mutating func receber(_ j: [String: Any]) -> (texto: String, terminou: Bool)? {
      guard j["type"] as? String == "TurnInfo", let evento = j["event"] as? String else { return nil }
      let texto = (j["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if evento == "EndOfTurn" {
        let t = texto.isEmpty ? textoAteAgora : texto
        textoAteAgora = ""
        return t.isEmpty ? nil : (t, true)
      }
      guard !texto.isEmpty else { return nil }
      textoAteAgora = texto
      return (texto, false)
    }
  }

  var aoOuvir: ((String) -> Void)?
  var aoTerminar: ((String) -> Void)?
  var aoFalhar: ((String) -> Void)?
  private var ws: URLSessionWebSocketTask?
  private var acumulador = Acumulador()

  var ouvindo: Bool { ws != nil }

  /// `comEco`: liga o cancelamento de eco (fora de reunião), para ouvir enquanto o Jarvis fala.
  func comecar(comEco: Bool) {
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
    let pendente = Pendente()
    JarvisMicrofone.shared.assinar("legenda", comEco: comEco) { dados in
      guard let q = pendente.juntar(dados, quadro: Self.quadro) else { return }
      ws.send(.data(q)) { _ in }
    }
    Task { [weak self] in await self?.ler(ws) }
  }

  /// Fim pelo botão ou pela guarda de silêncio: entrega o que já foi dito. Falso se nada foi ouvido.
  @discardableResult
  func terminar() -> Bool {
    guard ws != nil else { return false }
    let t = acumulador.textoAteAgora
    parar()
    guard !t.isEmpty else { return false }
    aoTerminar?(t)
    return true
  }

  /// Esquece o turno em aberto sem fechar o socket (fala curta por cima do Jarvis que não interrompeu).
  func descartarTurno() { acumulador = Acumulador() }

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
        // o Deepgram fechou: o que já foi dito vai para o Jarvis em vez de se perder
        if self.ws === ws, !terminar() {
          aoFalhar?("Sem legenda: o Deepgram não respondeu")
        }
        return
      }
      guard case .string(let s) = m, self.ws === ws,
        let j = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
      else { continue }
      if j["type"] as? String == "Error" { log("Jarvis: Flux devolveu erro \(j["code"] ?? "")") }
      guard let r = acumulador.receber(j) else { continue }
      aoOuvir?(r.texto)
      if r.terminou { aoTerminar?(r.texto) }
    }
  }

  /// Junta o PCM do microfone em quadros de 80 ms (chamado só na fila do microfone).
  final class Pendente: @unchecked Sendable {
    private var dados = Data()
    func juntar(_ novo: Data, quadro: Int) -> Data? {
      dados.append(novo)
      guard dados.count >= quadro else { return nil }
      defer { dados = Data() }
      return dados
    }
  }
}
