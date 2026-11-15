import SwiftUI

/// Fail-closed force-upgrade / migration-maintenance overlays for account cutover.
///
/// LIFECYCLE: permanent
struct AccountCutoverBlockingOverlay: View {
  let decision: AccountCutoverGateDecision
  let strandedNewData: Bool
  let onOpenDownload: (DesktopUpdatePolicyResponse) -> Void

  static func host(onOpenDownload: @escaping (DesktopUpdatePolicyResponse) -> Void) -> some View {
    AccountCutoverBlockingOverlayHost(onOpenDownload: onOpenDownload)
  }

  var body: some View {
    switch decision {
    case .allowProductTraffic:
      EmptyView()
    case .forceUpgrade:
      let policy = DesktopUpdatePolicyResponse(
        id: "account-cutover-force-upgrade",
        active: true,
        severity: .required,
        maximumBuildNumber: nil,
        latestBuildNumber: nil,
        title: "Atualização necessária",
        message: "Instale a versão mais recente do app Omi para desktop para continuar após a migração da conta.",
        ctaText: "Baixar a mais recente",
        downloadURL: DesktopUpdatePolicyResponse.stableManualDownloadURL.absoluteString,
        canDismiss: false
      )
      overlay(policy: policy, onDownload: { onOpenDownload(policy) })
    case .migrationMaintenance:
      let policy = DesktopUpdatePolicyResponse(
        id: "account-cutover-migration-maintenance",
        active: true,
        severity: .required,
        maximumBuildNumber: nil,
        latestBuildNumber: nil,
        title: "Migração em andamento",
        message: strandedNewData
          ? "Sua conta está em manutenção. Alguns dados recentes podem não aparecer até terminar."
          : "Sua conta está sendo migrada. Os recursos do produto ficam pausados até a migração terminar.",
        ctaText: "OK",
        downloadURL: DesktopUpdatePolicyResponse.stableManualDownloadURL.absoluteString,
        canDismiss: false
      )
      overlay(policy: policy, onDownload: {})
    }
  }

  @ViewBuilder
  private func overlay(
    policy: DesktopUpdatePolicyResponse,
    onDownload: @escaping () -> Void
  ) -> some View {
    ShellModalScrim(opacity: ShellModalScrimLayout.blocking)
      .zIndex(20)
    DesktopRequiredUpdatePrompt(policy: policy, onDownload: onDownload)
      .zIndex(21)
  }
}

private struct AccountCutoverBlockingOverlayHost: View {
  @ObservedObject private var manager = AccountCutoverControlManager.shared
  let onOpenDownload: (DesktopUpdatePolicyResponse) -> Void

  var body: some View {
    if let decision = manager.overlayDecision {
      AccountCutoverBlockingOverlay(
        decision: decision,
        strandedNewData: manager.control.strandedNewData,
        onOpenDownload: onOpenDownload
      )
    }
  }
}
