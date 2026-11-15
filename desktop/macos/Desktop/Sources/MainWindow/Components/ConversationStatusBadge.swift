import OmiTheme
import SwiftUI

/// Small inline pill that surfaces *why* a conversation has no real title
/// (processing, locked, failed) instead of letting "Untitled" lie about all
/// three cases. Returns nil-equivalent (EmptyView) when the conversation is
/// in its normal titled state.
struct ConversationStatusBadge: View {
  let state: ConversationDisplayState
  /// Only read for `.processing`; the row derives it from the clock.
  var phase: ConversationProcessingPhase = .summarizing

  var body: some View {
    switch state {
    case .processing:
      ProcessingPill(phase: phase)
    case .awaitingFirstOpen:
      Pill(
        icon: "sparkles",
        text: "Toque para resumir",
        color: Ink.accent,
        help: "A transcrição está salva. Abra a conversa para gerar o título e o resumo."
      )
    case .locked:
      Pill(
        icon: "hourglass",
        text: "Salva e aguardando",
        color: PageGlass.warning,
        help: "Esta conversa está salva. Veja seu plano e uso para saber quando o processamento estará disponível."
      )
    case .failed:
      Pill(
        icon: "exclamationmark.triangle.fill",
        text: "Falhou",
        color: Ink.errorRed,
        help: "O processamento falhou. Use Reprocessar para gerar o título e o resumo de novo."
      )
    case .untitledRecoverable:
      Pill(
        icon: "wand.and.stars",
        text: ConversationProcessingProgress.untitledRecoverableBadgeText,
        color: Ink.accent,
        help: ConversationProcessingProgress.untitledRecoverableBadgeHelp
      )
    case .titled, .untitledEmpty:
      // Titled state — no badge needed. Empty-state untitled also stays
      // quiet (probably ambient capture, no value in surfacing a pill).
      EmptyView()
    }
  }
}

/// Generic capsule pill with leading icon + label.
private struct Pill: View {
  let icon: String
  let text: String
  let color: Color
  let help: String

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .scaledFont(size: 9, weight: .semibold)
      Text(text)
        .scaledFont(size: 10, weight: .semibold)
    }
    .foregroundColor(color)
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(
      Capsule(style: .continuous)
        .fill(color.opacity(0.16))
    )
    .help(help)
  }
}

/// Pill for a live pipeline. The wording and colour track how long the wait
/// has lasted, so the row never promises "shortly" without a bound.
private struct ProcessingPill: View {
  let phase: ConversationProcessingPhase
  @State private var pulse = false

  static func label(for phase: ConversationProcessingPhase) -> String {
    switch phase {
    case .summarizing: return "Resumindo"
    case .slow: return "Demorando mais que o normal"
    case .stalled: return "Travada"
    }
  }

  static func help(for phase: ConversationProcessingPhase) -> String {
    switch phase {
    case .summarizing:
      return "O Omi está escrevendo o título e o resumo. Isso costuma levar menos de dois minutos."
    case .slow:
      return "Ainda processando. Conversas longas e horários de pico podem levar alguns minutos."
    case .stalled:
      return "Está processando há mais de dez minutos. Reprocese para tentar de novo."
    }
  }

  private var color: Color {
    switch phase {
    case .summarizing: return Ink.accent
    case .slow: return PageGlass.warning
    case .stalled: return Ink.errorRed
    }
  }

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
        .opacity(pulse && phase != .stalled ? 0.4 : 1.0)
        .animation(
          phase == .stalled ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
          value: pulse
        )
      Text(Self.label(for: phase))
        .scaledFont(size: 10, weight: .semibold)
        .foregroundColor(color)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(
      Capsule(style: .continuous)
        .fill(color.opacity(0.16))
    )
    .onAppear { pulse = true }
    .help(Self.help(for: phase))
    .accessibilityLabel(Self.label(for: phase))
  }
}
