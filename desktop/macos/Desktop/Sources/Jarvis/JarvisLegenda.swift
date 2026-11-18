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
    // com a voz tocando, recriar o engine corta a fala: fica o que já está montado se ele cobre o que se pede (o
    // eco que sobra não atrapalha); quando a voz acaba, montar() roda de novo
    if tocando > 0, let m = montado, m.mic || !mic, m.eco || !eco { return }
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
/// O Flux decide o fim do turno (`EndOfTurn`): com `eot_threshold` 0,7 fechava ~0,8 a 1,2 s depois da fala, contra
/// ~1,6 s do nova-3 com `endpointing` de 1,2 s (medido com o `say` em 18/11), mas cortava ditado longo na pausa entre
/// itens (Gabriel, 18/11 14h16); 0,85 pede mais certeza de que acabou. O socket segue aberto entre turnos; quem usa
/// decide quando parar.
///
/// Em teste (ajuste `jarvis_ouvido_local`): o Parakeet do Omi no Mac no lugar do Flux. Ele fecha um trecho a cada
/// 0,6 s de pausa, sem parcial; o turno fecha quando o trecho que cobre a última voz chegou e já passou
/// `pausaLocal` de silêncio. O log mostra "fim da fala → turno" dos dois motores para comparar.
@MainActor
final class JarvisLegenda {
  nonisolated static let url = URL(
    string: "wss://api.deepgram.com/v2/listen?model=flux-general-multi&language_hint=pt-BR&encoding=linear16"
      + "&sample_rate=16000&eot_threshold=0.85")!
  /// 80 ms de PCM 16 kHz por envio, como a Deepgram recomenda (em 20 ms o Flux fechava ~110 ms depois, BDR 25/10).
  nonisolated static let quadro = 2560

  /// Texto do turno a partir do `TurnInfo` do Flux (puro, testado). O `transcript` já é o turno inteiro até ali.
  struct Acumulador: Equatable {
    var textoAteAgora = ""

    /// Devolve o texto da legenda até agora e se o turno acabou. Depois do fim, o próximo turno começa vazio.
    mutating func receber(_ j: [String: Any]) -> (texto: String, terminou: Bool)? {
      guard j["type"] as? String == "TurnInfo", let evento = j["event"] as? String else { return nil }
      // o modelo multilíngue marca a troca de idioma no meio do texto ("<lang:pt>"): não é fala
      let texto = (j["transcript"] as? String ?? "").replacingOccurrences(
        of: #"\s*<lang:[A-Za-z-]+>\s*"#, with: " ", options: .regularExpression
      ).trimmingCharacters(in: .whitespacesAndNewlines)
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

  nonisolated static let ajusteLocal = "jarvis_ouvido_local"
  nonisolated static let pausaLocal: TimeInterval = 1.0
  /// RMS de um quadro com voz no microfone já tratado (ponytail: limiar fixo; sala barulhenta segura o turno aberto e
  /// quem fecha é a guarda de 4 s do painel)
  nonisolated static let limiarVoz: Float = 0.01
  /// Com o Jarvis falando, o que sobra da voz dele depois do cancelamento de eco passava de 0,01 e segurava o turno
  /// do Gabriel aberto até a guarda de 4 s (18/11 14h39); a janela com a fala dele por cima mediu 0,048 de média.
  nonisolated static let limiarVozComJarvisFalando: Float = 0.03

  nonisolated static func limiarVoz(jarvisFalando: Bool) -> Float {
    jarvisFalando ? limiarVozComJarvisFalando : limiarVoz
  }

  /// Fim do turno no Parakeet (puro, testado).
  nonisolated static func fimLocal(texto: String, agora: Date, ultimaVoz: Date, ultimoTrecho: Date) -> Bool {
    !texto.isEmpty && ultimoTrecho > ultimaVoz && agora.timeIntervalSince(ultimaVoz) >= pausaLocal
  }

  var aoOuvir: ((String) -> Void)?
  var aoTerminar: ((String) -> Void)?
  var aoFalhar: ((String) -> Void)?
  private var ws: URLSessionWebSocketTask?
  private var acumulador = Acumulador()
  private let voz = Voz()
  // Parakeet: um só, carregado na primeira escuta local e mantido (o modelo leva segundos para subir)
  private static var parakeet: LocalTranscriptionService?
  private static weak var atual: JarvisLegenda?
  private var local = false
  private var turnoLocal = ""
  private var ultimoTrecho = Date.distantPast
  private var relogioLocal: Timer?

  var ouvindo: Bool { ws != nil || local }

  /// `comEco`: liga o cancelamento de eco (fora de reunião), para ouvir enquanto o Jarvis fala.
  func comecar(comEco: Bool) {
    parar()
    if UserDefaults.standard.bool(forKey: Self.ajusteLocal) { return comecarLocal(comEco: comEco) }
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
    let voz = voz
    voz.zerar()
    JarvisMicrofone.shared.assinar("legenda", comEco: comEco) { dados in
      voz.medir(dados)
      guard let q = pendente.juntar(dados, quadro: Self.quadro) else { return }
      ws.send(.data(q)) { _ in }
    }
    Task { [weak self] in await self?.ler(ws) }
  }

  /// Fim pelo botão ou pela guarda de silêncio: entrega o que já foi dito. Falso se nada foi ouvido.
  @discardableResult
  func terminar() -> Bool {
    guard ouvindo else { return false }
    let t = local ? turnoLocal : acumulador.textoAteAgora
    parar()
    guard !t.isEmpty else { return false }
    aoTerminar?(t)
    return true
  }

  /// Esquece o turno em aberto sem fechar o socket (fala curta por cima do Jarvis que não interrompeu).
  func descartarTurno() {
    acumulador = Acumulador()
    turnoLocal = ""
  }

  func parar() {
    if local {
      local = false
      relogioLocal?.invalidate()
      relogioLocal = nil
      JarvisMicrofone.shared.cancelar("legenda")
    }
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
      if r.terminou {
        logLatencia("Flux")
        aoTerminar?(r.texto)
      }
    }
  }

  private func logLatencia(_ motor: String) {
    let ms = voz.ultima.map { Int(Date().timeIntervalSince($0) * 1000) }
    log("Jarvis: fim da fala → turno fechado \(ms.map(String.init) ?? "?") ms (\(motor))")
  }

  // MARK: - Parakeet (teste)

  private func comecarLocal(comEco: Bool) {
    if Self.parakeet == nil {
      let p = LocalTranscriptionService(
        language: AssistantSettings.shared.transcriptionLanguageSelection, isUser: true)
      p.start(
        onSegments: { segmentos in JarvisLegenda.atual?.trechoLocal(segmentos.map(\.text).joined(separator: " ")) },
        onModelLoadFailed: { JarvisLegenda.atual?.aoFalhar?("O Parakeet não carregou: desligue o ouvido local") })
      Self.parakeet = p
    }
    guard let p = Self.parakeet else { return }
    Self.atual = self
    local = true
    turnoLocal = ""
    ultimoTrecho = .distantPast
    let voz = voz
    voz.zerar()
    JarvisMicrofone.shared.assinar("legenda", comEco: comEco) { dados in
      voz.medir(dados)
      p.appendAudio(dados)
    }
    relogioLocal = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
      MainActor.assumeIsolated { JarvisLegenda.atual?.conferirFimLocal() }
    }
  }

  private func trechoLocal(_ texto: String) {
    let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
    guard local, !t.isEmpty else { return }
    turnoLocal = turnoLocal.isEmpty ? t : turnoLocal + " " + t
    ultimoTrecho = Date()
    aoOuvir?(turnoLocal)
  }

  private func conferirFimLocal() {
    voz.limiar = Self.limiarVoz(jarvisFalando: JarvisVoz.shared.falando)
    guard local, let ultima = voz.ultima,
      Self.fimLocal(texto: turnoLocal, agora: Date(), ultimaVoz: ultima, ultimoTrecho: ultimoTrecho)
    else { return }
    let t = turnoLocal
    turnoLocal = ""
    logLatencia("Parakeet")
    aoTerminar?(t)
  }

  /// Último quadro com voz no microfone (medido na fila do microfone, lido no main).
  final class Voz: @unchecked Sendable {
    private let trava = NSLock()
    private var _ultima: Date?
    private var _limiar = JarvisLegenda.limiarVoz
    var ultima: Date? { trava.withLock { _ultima } }
    var limiar: Float {
      get { trava.withLock { _limiar } }
      set { trava.withLock { _limiar = newValue } }
    }
    func zerar() { trava.withLock { _ultima = nil } }
    func medir(_ dados: Data) {
      let n = dados.count / 2
      guard n > 0 else { return }
      let soma = dados.withUnsafeBytes { b in
        b.bindMemory(to: Int16.self).reduce(Float(0)) { $0 + Float($1) * Float($1) }
      }
      let rms = (soma / Float(n)).squareRoot() / 32768
      trava.withLock { if rms > _limiar { _ultima = Date() } }
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
