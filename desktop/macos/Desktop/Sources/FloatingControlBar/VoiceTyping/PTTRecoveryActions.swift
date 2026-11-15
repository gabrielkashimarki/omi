import OmiTheme
import SwiftUI
import VoiceTurnDomain

enum PTTStatusBannerPresentation {
  static func showsRecovery(hint: String, hasQuestion: Bool) -> Bool {
    hasQuestion && hint == VoiceTurnUICopy.terminalHint(for: .noNetwork)
  }

  static func text(hint: String, hasQuestion: Bool) -> String {
    showsRecovery(hint: hint, hasQuestion: hasQuestion) ? "Pergunta guardada" : hint
  }
}

/// Recovery stays on the failure surface; editing and sending remain in main Chat.
struct PTTStatusBannerContent: View {
  let hint: String
  @ObservedObject private var recovery = OfflinePTTQuestionRecovery.shared

  private var showsRecovery: Bool {
    PTTStatusBannerPresentation.showsRecovery(hint: hint, hasQuestion: recovery.isAvailable)
  }

  var body: some View {
    HStack(spacing: OmiSpacing.xs) {
      Image(systemName: showsRecovery ? "wifi.slash" : "mic.fill")
        .scaledFont(size: OmiType.caption, weight: .semibold)
        .foregroundColor(.white.opacity(0.9))
      Text(PTTStatusBannerPresentation.text(hint: hint, hasQuestion: recovery.isAvailable))
        .scaledFont(size: 12, weight: .medium)
        .foregroundColor(.white)
        .lineLimit(1)
      Spacer(minLength: 0)
      if showsRecovery {
        Button("Revisar") { recovery.reviewInMainChat() }
          .help("Revise sua pergunta offline no Chat sem enviá-la")
          .accessibilityIdentifier("ptt_recover_question_review")
        Button {
          recovery.copyToClipboard()
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .help("Copiar sua pergunta offline")
        .accessibilityLabel("Copiar pergunta offline")
        .accessibilityIdentifier("ptt_recover_question_copy")
      }
    }
    .buttonStyle(.plain)
    .foregroundColor(.white)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Remains available after the brief failure banner disappears.
struct PTTRecoveryMenuItems: View {
  @ObservedObject private var manager = PushToTalkManager.shared
  @ObservedObject private var recovery = OfflinePTTQuestionRecovery.shared

  var body: some View {
    Button("Desfazer último ditado") { manager.undoLastDictationAfterMenuTracking() }
      .disabled(!manager.canUndoLastDictation)
      .help("Desfaz um ditado recente enquanto o texto e o cursor não mudaram")
    if recovery.isAvailable {
      Button("Revisar pergunta offline") { recovery.reviewInMainChat() }
      Button("Copiar pergunta offline") { recovery.copyToClipboard() }
      Button("Dispensar pergunta offline") { recovery.clear() }
      Divider()
    }
  }
}
