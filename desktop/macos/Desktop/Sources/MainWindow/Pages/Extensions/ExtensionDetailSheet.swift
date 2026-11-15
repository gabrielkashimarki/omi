import OmiTheme
import SwiftUI

/// Preview the publisher's literal configuration, then keep one sheet open
/// for the existing connection controls. A saved config is not a signed-in server.
@MainActor
struct ExtensionDetailSheet: View {
  let entry: ExtensionCatalog.Entry
  @ObservedObject var appProvider: AppProvider
  let onDismiss: () -> Void

  @StateObject private var installation: ExtensionInstallSession
  @State private var values: [String: String] = [:]
  @State private var installTask: Task<Void, Never>?

  init(
    entry: ExtensionCatalog.Entry,
    appProvider: AppProvider,
    onDismiss: @escaping () -> Void,
    installation: ExtensionInstallSession? = nil
  ) {
    self.entry = entry
    self.appProvider = appProvider
    self.onDismiss = onDismiss
    _installation = StateObject(
      wrappedValue: installation
        ?? ExtensionInstallSession(refresh: { await appProvider.fetchUserExtensions() }))
  }

  static func preferredHeight(for install: ExtensionCatalog.Install) -> CGFloat {
    if case .skill = install { return 340 }
    return 420
  }

  var body: some View {
    ZStack {
      if let server = installation.installedServer {
        LocalMcpDetailSheet(server: server, appProvider: appProvider, onDismiss: dismiss)
          .accessibilityIdentifier("apps-marketplace-connection-setup")
      } else {
        catalogDetails
      }
    }
    .onAppear {
      if entry.id == MarketplaceSetupQA.fixtureID, MarketplaceSetupQA.isEnabled {
        MarketplaceSetupQA.installActions(session: installation, performInstall: install)
      }
    }
    .onChange(of: installation.phase) { _, phase in
      if case .serverSetup = phase { values.removeAll() }
      if phase == .skillInstalled { values.removeAll() }
    }
    .onEscapeKey(priority: .modal) {
      dismiss()
      return true
    }
    .onDisappear {
      if entry.id == MarketplaceSetupQA.fixtureID, MarketplaceSetupQA.isEnabled {
        MarketplaceSetupQA.removeInstallActions()
      }
      installTask?.cancel()
      installation.close()
      values.removeAll()
    }
  }

  private var requiredFields: [String] {
    switch entry.install {
    case .mcpRemote(_, _, let header): return header.map { [$0] } ?? []
    case .mcpStdio(_, _, let env): return env
    case .skill: return []
    }
  }

  private var installSummary: String {
    switch entry.install {
    case .mcpRemote(let url, let transport, _): return "\(transport.uppercased())  \(url)"
    case .mcpStdio(let command, let args, _): return ([command] + args).joined(separator: " ")
    case .skill(let source):
      let folder = "\(source.repo)/skills/\(source.slug)"
      guard source.files.count > 1 else { return "\(folder)  ·  SKILL.md" }
      return "\(folder)  ·  SKILL.md e \(source.files.count - 1) arquivos incluídos"
    }
  }

  private var installSummaryLabel: String {
    if case .skill = entry.install { return "Fonte" }
    if case .mcpStdio = entry.install { return "Executa no seu Mac" }
    return "Endpoint"
  }

  private var catalogDetails: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      HStack(spacing: OmiSpacing.md) {
        ExtensionLogo(imageUrl: entry.iconURL, fallbackSymbol: fallbackSymbol, size: 44)
        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(entry.name)
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(Ink.primary)
          Text(entry.publisher.isEmpty ? entry.subtitle : "\(entry.subtitle) · \(entry.publisher)")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
            .lineLimit(1)
        }
        Spacer()
      }

      ScrollView {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          if !entry.detail.isEmpty {
            Text(entry.detail)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          labelled(installSummaryLabel) {
            Text(installSummary)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.primary)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
          ForEach(requiredFields, id: \.self) { field in
            labelled(field) {
              SecureField("Obrigatório", text: binding(for: field))
                .textFieldStyle(.roundedBorder)
            }
          }
          if let website = entry.websiteURL, let url = URL(string: website) {
            Link("Abrir página do publicador", destination: url)
              .scaledFont(size: OmiType.caption)
          }
          if case .mcpRemote = entry.install {
            Text("Depois de adicionar este servidor, conclua o login necessário na próxima etapa")
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if let errorText = installation.errorText {
        Text(errorText)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.errorRed)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Spacer()
        Button(installation.phase == .skillInstalled ? "OK" : "Cancelar", action: dismiss)
          .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
        Button(action: install) {
          ConnectionModalActionButton(title: installation.isInstalling ? "Instalando…" : "Instalar")
        }
        .buttonStyle(.plain)
        .disabled(!installation.canInstall)
        .accessibilityIdentifier("apps-marketplace-install")
      }
    }
    .padding(OmiSpacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var fallbackSymbol: String {
    switch entry.install {
    case .skill: return "graduationcap"
    case .mcpStdio: return "terminal"
    case .mcpRemote: return "server.rack"
    }
  }

  @ViewBuilder
  private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      Text(label)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(Ink.secondary)
      content()
    }
  }

  private func binding(for field: String) -> Binding<String> {
    Binding(get: { values[field] ?? "" }, set: { values[field] = $0 })
  }

  private func install() {
    guard installation.canInstall, installTask == nil else { return }
    let submittedValues = values
    installTask = Task {
      await installation.install(entry, secrets: submittedValues)
      if !Task.isCancelled, installation.phase == .skillInstalled { dismiss() }
      installTask = nil
    }
  }

  private func dismiss() {
    guard installation.phase != .closed else { return }
    installTask?.cancel()
    installation.close()
    values.removeAll()
    onDismiss()
  }
}
