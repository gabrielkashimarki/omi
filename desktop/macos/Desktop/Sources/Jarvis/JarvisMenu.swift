import Foundation

/// Estado mostrado no ícone da barra de menus e o "Gravar reunião / Parar" manual.
@MainActor
enum JarvisMenu {
  enum Icone: Equatable { case pronto, ouvindo, pensando, gravando }

  /// Reunião ligada à mão pelo menu (o `MeetingDetector` não percebeu a chamada).
  private(set) static var reuniaoManual = false

  static var reuniaoAtiva: Bool {
    reuniaoManual || MeetingCopilot.shared.gravando || AppState.current?.meetingDetector?.isMeetingConfirmed == true
  }

  /// Qual ícone mostrar (puro, testado): o que o Jarvis faz agora vale mais que a reunião.
  nonisolated static func icone(fase: JarvisPainelEstado.Fase, reuniao: Bool) -> Icone {
    switch fase {
    case .ouvindo: return .ouvindo
    case .pensando, .confirmando: return .pensando
    case .pronto, .respondeu: return reuniao ? .gravando : .pronto
    }
  }

  static var icone: Icone { icone(fase: JarvisPainel.shared.fase, reuniao: reuniaoAtiva) }

  static var textoEstado: String {
    let fase: String
    switch icone {
    case .pronto: fase = "pronto"
    case .ouvindo: fase = "ouvindo"
    case .pensando: fase = "pensando"
    case .gravando: fase = "gravando reunião"
    }
    let estado = "Jarvis \(fase) · " + (JarvisMac.shared.conectado ? "Mac conectado" : "Mac sem conexão")
    return JarvisDisco.cheio ? estado + " · ⚠︎ " + JarvisDisco.aviso : estado
  }

  /// Liga: abre o copiloto e gira a conversa do Omi como reunião. Para: desfaz.
  static func alternarReuniao() {
    let ligar = !reuniaoAtiva
    reuniaoManual = ligar
    if ligar, AssistantSettings.shared.audioRecordingMode == .off {
      AssistantSettings.shared.audioRecordingMode = .always
    }
    MeetingCopilot.shared.meetingChanged(ligar)
    Task { await AppState.current?.handleMeetingObservation(active: ligar) }
    NotificationCenter.default.post(name: .jarvisMudou, object: nil)
  }

  /// O copiloto parou de ouvir (Parar, Concluir ou fim da chamada): a reunião manual acaba junto.
  static func reuniaoAcabou() {
    reuniaoManual = false
    NotificationCenter.default.post(name: .jarvisMudou, object: nil)
  }
}

/// Aviso de disco quase cheio no menu e no painel. Em 18/11, com o disco cheio, o Parakeet levou de 400 a 977 s para
/// carregar, a memória passou de 3 GB e o `ResourceMonitor` reiniciou o app em loop. Confere ao abrir e a cada 10 min.
@MainActor
enum JarvisDisco {
  nonisolated static let limite: Int64 = 3_000_000_000
  static let aviso = "Disco quase cheio: a transcrição local pode travar"
  private(set) static var cheio = false
  private static var relogio: Timer?

  /// Puro, testado. Sem leitura do disco não avisa.
  nonisolated static func quaseCheio(livres: Int64?) -> Bool { (livres ?? .max) < limite }

  static func comecar() {
    guard relogio == nil else { return }
    conferir()
    relogio = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
      MainActor.assumeIsolated { JarvisDisco.conferir() }
    }
  }

  static func conferir() {
    // o mesmo número do `df` (sem o espaço "purgável" que o macOS só promete liberar)
    let livres = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityKey]))?
      .volumeAvailableCapacity.map(Int64.init)
    let novo = quaseCheio(livres: livres)
    guard novo != cheio else { return }
    cheio = novo
    log("Jarvis: disco \(novo ? "quase cheio" : "com espaço de novo") (\((livres ?? 0) / 1_000_000) MB livres)")
    JarvisPainel.shared.avisarDisco()
    NotificationCenter.default.post(name: .jarvisMudou, object: nil)
  }
}
