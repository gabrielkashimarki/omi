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
    return "Jarvis \(fase) · " + (JarvisMac.shared.conectado ? "Mac conectado" : "Mac sem conexão")
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
