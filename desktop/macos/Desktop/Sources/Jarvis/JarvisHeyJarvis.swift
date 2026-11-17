import AppKit
import Foundation

#if canImport(OnnxRuntimeBindings)
  import OnnxRuntimeBindings
#elseif canImport(onnxruntime)
  import onnxruntime
#endif

/// "Hey Jarvis" local, sem nuvem: o openWakeWord (modelo pronto `hey_jarvis_v0.1`) em cima do onnxruntime que o
/// app já usa no Silero VAD. Mesmo caminho do `openwakeword` em Python: a cada 80 ms (1280 amostras) o
/// melspectrograma das últimas 1760 amostras vira 8 quadros, os últimos 76 quadros viram um embedding e os
/// últimos 16 embeddings dão a pontuação. Modelos: Apache 2.0 o código, CC BY-NC-SA 4.0 os pesos (uso pessoal).
final class JarvisDetectorPalavra: @unchecked Sendable {
  static let limiar: Float = 0.35  // o mesmo do Jarvis de 11/10 (`comando-central/jarvis/escuta.py`)
  static let bloco = 1280

  #if canImport(OnnxRuntimeBindings) || canImport(onnxruntime)
    private let env: ORTEnv
    private let mel: ORTSession
    private let emb: ORTSession
    private let palavra: ORTSession
    private let entradas: (mel: String, emb: String, palavra: String)
  #endif
  private var cru: [Float] = []
  private var sobra: [Float] = []
  private var quadros: [[Float]] = []
  private var embeddings: [[Float]] = []
  private var previsoes = 0
  var ultimoDisparo = Date.distantPast

  /// `pasta` com os três .onnx; sem ela, o bundle de recursos do app.
  init?(pasta: URL? = nil) {
    #if canImport(OnnxRuntimeBindings) || canImport(onnxruntime)
      let base =
        pasta
        ?? Bundle.main.url(forResource: "Omi Computer_Omi Computer", withExtension: "bundle")
        ?? Bundle.main.resourceURL
      guard let base else { return nil }
      do {
        let e = try ORTEnv(loggingLevel: .warning)
        env = e
        let opcoes = try ORTSessionOptions()
        try opcoes.setIntraOpNumThreads(1)
        let abrir = { (nome: String) in
          try ORTSession(env: e, modelPath: base.appendingPathComponent(nome).path, sessionOptions: opcoes)
        }
        mel = try abrir("oww_melspectrogram.onnx")
        emb = try abrir("oww_embedding_model.onnx")
        palavra = try abrir("hey_jarvis_v0.1.onnx")
        entradas = (
          try mel.inputNames().first ?? "input", try emb.inputNames().first ?? "input_1",
          try palavra.inputNames().first ?? "input"
        )
      } catch {
        logError("Jarvis: modelos do Hey Jarvis não abriram", error: error)
        return nil
      }
      reset()
    #else
      return nil
    #endif
  }

  func reset() {
    cru = []
    sobra = []
    quadros = Array(repeating: Array(repeating: 1, count: 32), count: 76)
    embeddings = []
    previsoes = 0
  }

  /// PCM 16 bits; devolve a maior pontuação dos blocos de 80 ms completados por estas amostras.
  func processar(_ amostras: [Int16]) -> Float {
    sobra += amostras.map(Float.init)
    var maior: Float = 0
    while sobra.count >= Self.bloco {
      maior = max(maior, bloco(Array(sobra.prefix(Self.bloco))))
      sobra.removeFirst(Self.bloco)
    }
    return maior
  }

  private func bloco(_ x: [Float]) -> Float {
    #if canImport(OnnxRuntimeBindings) || canImport(onnxruntime)
      cru += x
      if cru.count > Self.bloco + 480 { cru.removeFirst(cru.count - Self.bloco - 480) }
      do {
        let espectro = try rodar(mel, entradas.mel, cru, [1, cru.count])
        let n = espectro.count / 32
        for i in 0..<n { quadros.append(espectro[(i * 32)..<((i + 1) * 32)].map { $0 / 10 + 2 }) }
        if quadros.count > 76 { quadros.removeFirst(quadros.count - 76) }
        embeddings.append(try rodar(emb, entradas.emb, quadros.flatMap { $0 }, [1, 76, 32, 1]))
        if embeddings.count > 16 { embeddings.removeFirst(embeddings.count - 16) }
        guard embeddings.count == 16 else { return 0 }
        previsoes += 1
        let nota = try rodar(palavra, entradas.palavra, embeddings.flatMap { $0 }, [1, 16, 96]).first ?? 0
        // como o openwakeword: as primeiras previsões ainda não têm contexto
        return previsoes <= 5 ? 0 : nota
      } catch {
        logError("Jarvis: Hey Jarvis falhou num bloco", error: error)
        return 0
      }
    #else
      return 0
    #endif
  }

  #if canImport(OnnxRuntimeBindings) || canImport(onnxruntime)
    private func rodar(_ s: ORTSession, _ entrada: String, _ dados: [Float], _ forma: [Int]) throws -> [Float] {
      let bruto = NSMutableData(bytes: dados, length: dados.count * MemoryLayout<Float>.size)
      let tensor = try ORTValue(tensorData: bruto, elementType: .float, shape: forma.map { NSNumber(value: $0) })
      let nomes = try s.outputNames()
      let saidas = try s.run(withInputs: [entrada: tensor], outputNames: Set(nomes), runOptions: nil)
      guard let nome = nomes.first, let saida = saidas[nome] else { return [] }
      let d = try saida.tensorData() as Data
      return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
  #endif
}

/// Liga o detector ao microfone do Jarvis, fica mudo na reunião e abre o painel ouvindo quando ouve a palavra.
@MainActor
final class JarvisHeyJarvis {
  static let shared = JarvisHeyJarvis()
  private static let chaveLigado = "jarvisHeyJarvisLigado"
  private let fila = DispatchQueue(label: "jarvis.heyjarvis")
  private var detector: JarvisDetectorPalavra?
  private var escutando = false
  private var relogio: Timer?

  var ligado: Bool {
    get { UserDefaults.standard.object(forKey: Self.chaveLigado) as? Bool ?? true }
    set {
      UserDefaults.standard.set(newValue, forKey: Self.chaveLigado)
      atualizar()
    }
  }

  /// Regra de mudo (pura, testada): com reunião não dispara com a fala dos outros, e com o painel já
  /// ouvindo a palavra não abre de novo.
  nonisolated static func mudo(ligado: Bool, reuniao: Bool, painelOuvindo: Bool) -> Bool {
    !ligado || reuniao || painelOuvindo
  }

  func comecar() {
    guard relogio == nil else { return }
    // ponytail: confere a cada 2 s em vez de observar cada fonte de reunião; observar se o atraso incomodar
    relogio = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
      MainActor.assumeIsolated { JarvisHeyJarvis.shared.atualizar() }
    }
    atualizar()
  }

  func atualizar() {
    let mudo = Self.mudo(
      ligado: ligado, reuniao: JarvisMenu.reuniaoAtiva, painelOuvindo: JarvisPainel.shared.ouvindo)
    if mudo, escutando {
      escutando = false
      JarvisMicrofone.shared.cancelar("heyjarvis")
    } else if !mudo, !escutando {
      if detector == nil { detector = JarvisDetectorPalavra() }
      guard let detector else { return }
      escutando = true
      let fila = self.fila
      fila.async { detector.reset() }
      JarvisMicrofone.shared.assinar("heyjarvis") { dados in
        let amostras = dados.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        fila.async {
          guard detector.processar(amostras) >= JarvisDetectorPalavra.limiar,
            Date().timeIntervalSince(detector.ultimoDisparo) > 2
          else { return }
          detector.ultimoDisparo = Date()
          detector.reset()
          Task { @MainActor in JarvisHeyJarvis.shared.ouviu() }
        }
      }
    }
  }

  private func ouviu() {
    guard escutando else { return }
    log("Jarvis: ouvi Hey Jarvis")
    NSSound(named: "Tink")?.play()
    JarvisPainel.shared.abrir(ouvindo: true)
  }
}
