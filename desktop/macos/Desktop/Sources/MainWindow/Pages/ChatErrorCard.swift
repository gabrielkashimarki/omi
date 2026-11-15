import OmiTheme
import SwiftUI

// MARK: - ChatErrorCard
//
// Renders a single `ChatErrorState` as an inline, message-level card with
// a primary recovery CTA. Visual conventions follow the existing chat
// banners (tinted backdrop + SF Symbol + tinted border) so the surfaces
// feel like siblings.

struct ChatErrorCard: View {
  let state: ChatErrorState
  let onRecover: () -> Void
  let onDismiss: (() -> Void)?

  @State private var showDetails: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      HStack(alignment: .top, spacing: OmiSpacing.sm) {
        Image(systemName: iconName)
          .scaledFont(size: OmiType.body)
          .foregroundColor(accentColor)
          .frame(width: 16, alignment: .center)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(headline)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(Ink.primary)
          Text(detail)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 8)

        if let onDismiss = onDismiss {
          DismissButton(action: onDismiss, accessibilityLabel: "Dispensar", size: .compact)
        }
      }

      HStack(spacing: OmiSpacing.sm) {
        Button(action: onRecover) {
          Text(primaryCTATitle)
            .scaledFont(size: OmiType.caption, weight: .medium)
            // The label ladder inverted on the filled pill, and a full stadium.
            .foregroundColor(Ink.surface)
            .padding(.horizontal, OmiSpacing.md)
            .padding(.vertical, OmiSpacing.xxs)
            .background(accentColor)
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)

        if !detailsBody.isEmpty {
          Button(action: { showDetails.toggle() }) {
            HStack(spacing: OmiSpacing.hairline) {
              Text(showDetails ? "Ocultar detalhes" : "Mostrar detalhes")
                .scaledFont(size: OmiType.caption)
              Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                .scaledFont(size: OmiType.micro)
            }
            .foregroundColor(Ink.secondary)
          }
          .buttonStyle(.plain)
        }

        Spacer()
      }

      if showDetails, !detailsBody.isEmpty {
        Text(detailsBody)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, OmiSpacing.hairline)
      }
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    // A wash on the panel, tinted only enough to name the state. A saturated fill
    // here is a second ground, and on glass it is the loudest thing on screen.
    .background(Ink.rowFill)
    .overlay(
      RoundedRectangle(cornerRadius: PageGlass.rowRadius, style: .continuous)
        .strokeBorder(accentColor.opacity(0.35), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: PageGlass.rowRadius, style: .continuous))
  }

  // MARK: - State-specific copy

  private var iconName: String {
    switch state {
    case .authRequired:
      return "person.badge.key.fill"
    case .timeout:
      return "clock.badge.exclamationmark.fill"
    case .bridgeUnavailable:
      return "bolt.horizontal.circle.fill"
    case .interrupted:
      return "stop.circle.fill"
    case .noDataFound:
      return "magnifyingglass"
    }
  }

  /// The state's voice. Named system colours off the shared palette: `Ink.accent` for the one thing
  /// that is actionable and is not already a button, `PageGlass.warning` for a state with something
  /// to do about it, and `Ink.errorRed` — the only place this app raises its voice — for a failure.
  private var accentColor: Color {
    switch state {
    case .authRequired:
      return Ink.accent
    case .timeout, .interrupted:
      return PageGlass.warning
    case .bridgeUnavailable:
      return Ink.errorRed
    case .noDataFound:
      return Ink.secondary
    }
  }

  private var headline: String {
    switch state {
    case .authRequired:
      return "Entre para continuar"
    case .timeout(let toolName):
      if let toolName = toolName {
        return "\(toolName) timed out"
      }
      return "A IA demorou demais para responder"
    case .bridgeUnavailable(let reason):
      switch reason {
      case .nodeMissing:
        return "Ambiente de execução da IA ausente"
      case .runtimeMissing:
        return "Componentes da IA ausentes"
      case .crashed:
        return "A IA parou inesperadamente"
      case .failedToStart:
        return "A IA não conseguiu iniciar"
      case .unknown:
        return "A IA não está em execução"
      }
    case .interrupted:
      return "Resposta interrompida"
    case .noDataFound:
      return "Não encontrei nada"
    }
  }

  private var detail: String {
    switch state {
    case .authRequired:
      return "Sua sessão expirou. Entre de novo para continuar conversando."
    case .timeout:
      return "Tente de novo ou reformule a pergunta."
    case .bridgeUnavailable(let reason):
      switch reason {
      case .nodeMissing:
        return "Node.js não foi encontrado. Instale o ambiente de execução para continuar usando o chat com IA."
      case .runtimeMissing:
        return "Os componentes da IA não estão instalados. Instale-os para continuar conversando."
      case .crashed:
        return "A IA parou no meio da resposta. Tente de novo para começar uma resposta nova."
      case .failedToStart(let failure):
        switch failure {
        case .handshakeTimedOut:
          return "A IA demorou demais para iniciar. Tente de novo para começar uma resposta nova."
        case .incompatibleHandshake:
          return "A IA precisa reiniciar antes de responder. Tente de novo."
        case .exitedDuringStartup, .launchFailed:
          return "A IA não conseguiu iniciar. Tente de novo para começar uma resposta nova."
        }
      case .unknown:
        return "A IA não está respondendo. Tente de novo para começar uma resposta nova."
      }
    case .interrupted:
      return "Pergunte algo novo quando quiser."
    case .noDataFound:
      return "Tente outra pergunta ou seja mais específico."
    }
  }

  private var primaryCTATitle: String {
    switch state.primaryRecovery {
    case .retry:
      return "Tentar de novo"
    case .signIn:
      return "Entrar"
    case .installRuntime:
      return "Instalar ambiente"
    case .dismiss:
      return "Tentar outra pergunta"
    }
  }

  /// Optional disclosure body. Empty string = hide the disclosure button
  /// entirely. Kept generic — surfaces only a redacted, user-safe
  /// description of the failure class, never raw error text.
  private var detailsBody: String {
    switch state {
    case .timeout(let toolName):
      if let toolName = toolName {
        return "Ferramenta: \(toolName)"
      }
      return ""
    case .bridgeUnavailable(let reason):
      switch reason {
      case .nodeMissing:
        return "Causa: binário do node não encontrado no PATH."
      case .runtimeMissing:
        // Covers both a missing bridge script and a bundle whose agent runtime
        // payload (e.g. pi-mono-extension) never made it into the install.
        return "Causa: o ambiente local da IA está sem arquivos no disco."
      case .crashed:
        return "Causa: o processo bridge foi encerrado."
      case .failedToStart(let failure):
        return "Causa: falha ao iniciar o bridge (\(failure.rawValue))."
      case .unknown:
        return ""
      }
    case .authRequired, .interrupted, .noDataFound:
      return ""
    }
  }
}
