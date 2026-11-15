import AppKit
import Combine
import OmiTheme
import SwiftUI

struct MemoryExportCatalogEntry: Identifiable {
  let destination: MemoryExportDestination
  let title: String?
  let subtitle: String?
  let description: String?

  var id: String { destination.id }
  var resolvedTitle: String { title ?? destination.title }
  var resolvedSubtitle: String { subtitle ?? destination.subtitle }
  var resolvedDescription: String { description ?? destination.description }
}

enum MemoryExportCatalog {
  static let entries: [MemoryExportCatalogEntry] =
    MemoryExportDestination.allCases.compactMap { destination in
      switch destination {
      case .claudeCode, .codex:
        return nil
      case .claude:
        return MemoryExportCatalogEntry(
          destination: .claude,
          title: "Claude / Claude Code",
          subtitle: nil,
          description: "Claude Code (CLI) ou Claude na nuvem. Escolha na configuração."
        )
      case .chatgpt:
        return MemoryExportCatalogEntry(
          destination: .chatgpt,
          title: "ChatGPT / Codex",
          subtitle: "App do ChatGPT ou Codex CLI",
          description: "Adicione o Omi no ChatGPT ou conecte o Codex localmente. Escolha na configuração."
        )
      default:
        return MemoryExportCatalogEntry(
          destination: destination, title: nil, subtitle: nil, description: nil)
      }
    }

  static func matching(_ searchText: String) -> [MemoryExportCatalogEntry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return entries }

    return
      entries
      .filter { entry in
        [entry.resolvedTitle, entry.resolvedSubtitle, entry.resolvedDescription]
          .contains { $0.localizedCaseInsensitiveContains(query) }
      }
      .sorted { matchRank($0, query: query) < matchRank($1, query: query) }
  }

  private static func matchRank(_ entry: MemoryExportCatalogEntry, query: String) -> Int {
    if entry.resolvedTitle.localizedCaseInsensitiveCompare(query) == .orderedSame { return 0 }
    if entry.resolvedTitle.range(
      of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    {
      return 1
    }
    return 2
  }
}

struct ExportsSection: View {
  let statuses: [MemoryExportDestination: MemoryExportStatus]
  var searchText = ""
  var title = "Exportações"
  var entriesOverride: [MemoryExportCatalogEntry]? = nil
  let onSelectDestination: (MemoryExportDestination) -> Void

  private var entries: [MemoryExportCatalogEntry] {
    entriesOverride ?? MemoryExportCatalog.matching(searchText)
  }

  private func status(for destination: MemoryExportDestination) -> MemoryExportStatus {
    let fallback = MemoryExportStatus(
      exportedCount: 0,
      lastExportedAt: nil,
      detailText: nil,
      isConfigured: false,
      hasConnection: false,
      needsUpdate: false)

    switch destination {
    case .claude:
      return aggregateStatus(for: [.claude, .claudeCode], fallback: fallback)
    case .chatgpt:
      return aggregateStatus(for: [.chatgpt, .codex], fallback: fallback)
    default:
      return statuses[destination] ?? fallback
    }
  }

  private func aggregateStatus(
    for destinations: [MemoryExportDestination],
    fallback: MemoryExportStatus
  ) -> MemoryExportStatus {
    let values = destinations.map { statuses[$0] ?? fallback }
    return MemoryExportStatus(
      exportedCount: values.map(\.exportedCount).max() ?? 0,
      lastExportedAt: values.compactMap(\.lastExportedAt).max(),
      detailText: values.compactMap(\.detailText).first,
      isConfigured: values.contains(where: \.hasConnection),
      hasConnection: values.contains(where: \.hasConnection),
      needsUpdate: values.contains(where: \.needsUpdate)
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      Text(title)
        .scaledFont(size: OmiType.subheading, weight: .semibold)
        .foregroundColor(Ink.primary)

      if entries.isEmpty {
        Text("Nenhuma exportação corresponde a “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))”.")
          .scaledFont(size: OmiType.body)
          .foregroundStyle(Ink.secondary)
          .padding(.vertical, OmiSpacing.md)
      } else {
        VStack(spacing: 0) {
          ForEach(entries) { entry in
            MemoryExportRow(
              destination: entry.destination,
              titleOverride: entry.title,
              subtitleOverride: entry.subtitle,
              descriptionOverride: entry.description,
              status: status(for: entry.destination)
            ) {
              onSelectDestination(entry.destination)
            }
          }
        }
      }
    }
  }
}

struct MemoryExportRow: View {
  let destination: MemoryExportDestination
  var titleOverride: String? = nil
  var subtitleOverride: String? = nil
  var descriptionOverride: String? = nil
  let status: MemoryExportStatus
  let action: () -> Void

  @State private var isHovering = false

  private var actionTitle: String {
    if destination.supportsAgentSetup {
      return showsConnectedState ? "Conectado" : "Conectar"
    }
    if destination.supportsMCP {
      if status.needsUpdate { return "Atualizar" }
      return showsConnectedState ? "Conectado" : "Conectar"
    }
    switch destination {
    case .obsidian:
      return status.isConfigured ? "Sincronizar" : "Conectar"
    case .notion, .chatgpt, .claude, .gemini, .agents, .claudeCode, .codex, .openclaw, .hermes:
      return status.hasConnection ? "Abrir" : "Conectar"
    }
  }

  private var showsConnectedState: Bool {
    guard destination.supportsMCP || destination.supportsAgentSetup else { return false }
    return status.hasConnection
  }

  private var statusPrimaryText: String {
    if status.exportedCount > 0 {
      return "\(status.exportedCount.formatted()) memórias exportadas"
    }
    if status.needsUpdate {
      return "Precisa de atualização"
    }
    return status.hasConnection ? "Conectado" : "Não conectado"
  }

  private var rowSecondaryText: String {
    if status.needsUpdate, status.exportedCount == 0, !status.hasConnection {
      return "Usando o endpoint antigo. Atualize para a nova URL"
    }
    if status.exportedCount > 0 || status.hasConnection {
      if let lastExportedAt = status.lastExportedAt {
        let relative = RelativeDateTimeFormatter().localizedString(for: lastExportedAt, relativeTo: Date())
        return "Exportado \(relative)"
      }
      if let detailText = status.detailText, !detailText.isEmpty {
        return detailText
      }
      return statusPrimaryText
    }
    if let descriptionOverride {
      return descriptionOverride
    }
    if let subtitleOverride {
      return subtitleOverride
    }
    let subtitle = destination.subtitle
    return subtitle.isEmpty ? destination.description : subtitle
  }

  // Mirrors ImportConnectorRow: one horizontal row with the integration name,
  // a single status line, and the action pill — no stacked description block that
  // wraps "Claude / Claude Code" away from its Connect control.
  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.md) {
        ConnectorBrandIcon(brand: destination.brand, size: 34, cornerRadius: 9)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(titleOverride ?? destination.title)
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(Ink.primary)
            .lineLimit(1)
            .truncationMode(.tail)

          Text(rowSecondaryText)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        Spacer(minLength: 12)

        ImportConnectorActionButton(title: actionTitle, isConnected: showsConnectedState)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.md)
      .background(isHovering ? Ink.wash : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}

@MainActor
struct MemoryExportWorkspace {
  var installedApplicationURL: (ConnectorBrand) -> URL?
  var defaultApplicationURL: (URL) -> URL?
  var openWithApplication: ([URL], URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (Error?) -> Void) -> Void
  var open: (URL) -> Void

  static let live = Self(
    installedApplicationURL: { $0.installedApplicationURL },
    defaultApplicationURL: { NSWorkspace.shared.urlForApplication(toOpen: $0) },
    openWithApplication: { urls, applicationURL, configuration, completion in
      NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, error in
        completion(error)
      }
    },
    open: { NSWorkspace.shared.open($0) })
}

@MainActor
final class MemoryExportDestinationSheetModel: ObservableObject {
  private let workspace: MemoryExportWorkspace
  @Published var isRunning = false
  @Published var statusMessage: String?
  @Published var errorMessage: String?
  @Published var notionToken = ""
  @Published var notionParentPageID = ""
  @Published var obsidianVaultPath = ""
  @Published var mcpKey: String?
  @Published var isLoadingMCPKey = false
  @Published var isTestingAgentConnection = false

  init(workspace: MemoryExportWorkspace = .live) {
    self.workspace = workspace
  }

  func loadConfiguration() async {
    obsidianVaultPath = await MemoryExportService.shared.obsidianVaultPath()
    mcpKey = await MemoryExportService.shared.storedMCPKey()
  }

  func generateMCPKey() async {
    errorMessage = nil
    isLoadingMCPKey = true
    defer { isLoadingMCPKey = false }
    do {
      mcpKey = try await MemoryExportService.shared.ensureMCPKey()
    } catch {
      errorMessage = "Não foi possível criar uma chave MCP: \(error.localizedDescription)"
    }
  }

  func createNewAgentConnectionKey() async {
    errorMessage = nil
    statusMessage = nil
    isLoadingMCPKey = true
    defer { isLoadingMCPKey = false }

    do {
      let key = try await MemoryExportService.shared.createNewMCPKey()
      _ = try LocalAgentAPISettings.createNewToken()
      mcpKey = key
      statusMessage = "Nova chave criada. Copie o prompt de novo quando quiser."
    } catch {
      errorMessage = "Não foi possível criar uma nova chave de conexão: \(error.localizedDescription)"
    }
  }

  func testAgentConnection() async {
    errorMessage = nil
    statusMessage = nil
    isTestingAgentConnection = true
    defer { isTestingAgentConnection = false }

    do {
      guard let key = await MemoryExportService.shared.storedMCPKey() else {
        throw MemoryExportError.requestFailed("Copie o prompt de configuração antes de testar a conexão.")
      }
      let localToken = try LocalAgentAPISettings.enable()
      mcpKey = key
      let result = try await MemoryExportService.shared.testAgentConnections(
        hostedKey: key,
        localToken: localToken)
      statusMessage = result.summary
    } catch {
      errorMessage = "O Omi não conseguiu testar a conexão: \(error.localizedDescription)"
    }
  }

  func copyToPasteboard(_ text: String, label: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    statusMessage = "\(label) copiado."
  }

  func copyAgentSetupPrompt() async -> MemoryExportStatus? {
    errorMessage = nil
    statusMessage = nil
    isLoadingMCPKey = true
    defer { isLoadingMCPKey = false }

    do {
      let key = try await MemoryExportService.shared.ensureMCPKey()
      let localToken = try LocalAgentAPISettings.enable()
      mcpKey = key
      copyToPasteboard(
        MemoryExportService.omiAgentSetupPrompt(
          hostedKey: key,
          localURL: LocalAgentAPISettings.serverURL,
          localToken: localToken),
        label: "Prompt do agente")
      statusMessage =
        "Prompt copiado. Compartilhe só com um agente de confiança: ele inclui chaves de acesso do Omi."
      return await MemoryExportService.shared.status(for: .agents)
    } catch {
      errorMessage = "Não foi possível criar o prompt: \(error.localizedDescription)"
      return nil
    }
  }

  func open(_ url: URL) {
    NSWorkspace.shared.open(url)
  }

  @Published var isExecuting = false

  /// Hand the whole setup to Omi: create a task and run it through the standard
  /// execute flow (TasksStore.createTask + AgentPillsManager.spawn) — the same path
  /// the floating-bar "Execute" button uses. No new execution flow.
  func executeWithOmi(destination: MemoryExportDestination) async {
    errorMessage = nil
    isExecuting = true
    defer { isExecuting = false }

    do {
      let outcome = try await MemoryExportExecutor.run(destination)
      mcpKey = await MemoryExportService.shared.storedMCPKey()
      switch outcome.mode {
      case .autonomous:
        statusMessage = "O Omi está configurando isso. Acompanhe na barra flutuante."
      case .assisted:
        statusMessage = outcome.taskTitle
      case .completed:
        // Deterministic local write — show the result directly.
        statusMessage = outcome.taskTitle
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func run(destination: MemoryExportDestination) async -> MemoryExportStatus? {
    errorMessage = nil
    statusMessage = nil
    isRunning = true
    defer { isRunning = false }

    do {
      switch destination {
      case .notion:
        if !NotionMCPConnector.shared.isConnected {
          statusMessage = "Aprove o Omi no seu navegador…"
          try await NotionMCPConnector.shared.connect()
        }
        let result = try await MemoryExportService.shared.exportToNotion()
        await MainActor.run {
          openDestination(for: destination, url: result.destinationURL)
        }
        statusMessage = "\(result.memoryCount.formatted()) memórias gravadas no Notion."

      case .obsidian:
        let vaultURL: URL
        if obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          guard let pickedURL = selectObsidianVault() else {
            return nil
          }
          obsidianVaultPath = pickedURL.path
          vaultURL = pickedURL
        } else {
          vaultURL = URL(fileURLWithPath: obsidianVaultPath)
        }

        let result = try await MemoryExportService.shared.exportToObsidian(vaultURL: vaultURL)
        await MainActor.run {
          revealExportFile(from: result)
          openDestination(for: destination, url: result.destinationURL)
        }
        statusMessage = "\(result.memoryCount.formatted()) memórias gravadas no Obsidian."

      case .chatgpt, .claude, .gemini:
        let result = try await MemoryExportService.shared.prepareManualExport(for: destination)
        await MainActor.run {
          applyClipboard(from: result)
          revealExportFile(from: result)
          openDestination(for: destination, url: result.destinationURL)
        }
        statusMessage = "Pacote de memórias pronto para \(destination.title). Prompt e exportação copiados."

      case .agents, .claudeCode, .codex, .openclaw, .hermes:
        // MCP-only destinations have no memory-pack run step.
        return nil
      }

      return await MemoryExportService.shared.status(for: destination)
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  func pickObsidianVault() {
    if let selectedURL = selectObsidianVault() {
      obsidianVaultPath = selectedURL.path
    }
  }

  private func selectObsidianVault() -> URL? {
    let panel = NSOpenPanel()
    panel.message = "Selecione seu cofre do Obsidian."
    panel.prompt = "Abrir"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url : nil
  }

  private func applyClipboard(from result: MemoryExportResult) {
    guard let clipboardText = result.clipboardText, !clipboardText.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(clipboardText, forType: .string)
  }

  private func revealExportFile(from result: MemoryExportResult) {
    guard let fileURL = result.fileURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
  }

  func openDestination(for destination: MemoryExportDestination, url: URL?) {
    guard let url else { return }

    if let appURL = workspace.installedApplicationURL(destination.brand) {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true

      workspace.openWithApplication([url], appURL, configuration) { [self] error in
        if let error {
          log(
            "MemoryExportDestinationSheetModel: Failed opening \(destination.title) with installed app: \(error.localizedDescription)"
          )
          Self.performOnMainActor { [self] in
            self.openInDefaultHandler(url)
          }
        }
      }
      return
    }

    openInDefaultHandler(url)
  }

  func openInDefaultHandler(_ url: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true

    if let appURL = workspace.defaultApplicationURL(url) {
      workspace.openWithApplication([url], appURL, configuration) { [workspace] error in
        if let error {
          log(
            "MemoryExportDestinationSheetModel: Failed opening \(url.absoluteString): \(error.localizedDescription)"
          )
          Self.performOnMainActor {
            workspace.open(url)
          }
        }
      }
      return
    }

    workspace.open(url)
  }

  nonisolated static func performOnMainActor(_ operation: @escaping @MainActor @Sendable () -> Void) {
    Task { @MainActor in
      operation()
    }
  }
}

struct MemoryExportDestinationSheet: View {
  let destination: MemoryExportDestination
  @Binding var statuses: [MemoryExportDestination: MemoryExportStatus]
  let onDismiss: () -> Void

  @StateObject private var model = MemoryExportDestinationSheetModel()
  @State private var showManualSetup = false
  @State private var permissionRefreshID = 0
  @State private var isDisconnecting = false

  private let permissionRefreshTimer = Timer.publish(every: 1.0, on: .main, in: .common)
    .autoconnect()

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      HStack(alignment: .top, spacing: OmiSpacing.md) {
        ConnectorBrandIcon(brand: destination.brand, size: 56, cornerRadius: OmiChrome.controlRadius)

        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text(destination.title)
            .scaledFont(size: OmiType.heading, weight: .semibold)
            .foregroundColor(Ink.primary)

          Text(destination.subtitle)
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)

          Text(destination.description)
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)
            .padding(.top, OmiSpacing.xxs)
        }

        Spacer()

        DismissButton(action: onDismiss)
      }

      // Scrollable so the full connector flow (Execute + live-connection steps +
      // memory pack) never clips inside the fixed-height sheet.
      ScrollView {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          if let entry = IntegrationNudgeCatalog.exportEntry(destinationID: destination.rawValue) {
            IntegrationValueSection(entry: entry)
          }

          content

          DeveloperHomeLink()

          if let statusMessage = model.statusMessage {
            Text(statusMessage)
              .scaledFont(size: OmiType.caption, weight: .medium)
              .foregroundColor(Ink.listeningGreen)
          }

          if let errorMessage = model.errorMessage {
            Text(errorMessage)
              .scaledFont(size: OmiType.caption, weight: .medium)
              .foregroundColor(PageGlass.warning)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(OmiSpacing.xxl)
    .background(Ink.surface)
    .glassContent()
    .task {
      await model.loadConfiguration()
      statuses[destination] = await MemoryExportService.shared.refreshCloudGrantConnectionStatus(for: destination)
    }
    .onReceive(permissionRefreshTimer) { _ in
      refreshPermissionStateIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refreshPermissionStateIfNeeded()
      refreshCloudGrantConnectionIfNeeded()
    }
  }

  private func refreshPermissionStateIfNeeded() {
    guard MemoryExportExecutor.requiresAccessibilityPreflight(destination) else { return }
    permissionRefreshID += 1
  }

  private func refreshCloudGrantConnectionIfNeeded() {
    guard destination.cloudOAuthClientID != nil else { return }
    Task {
      statuses[destination] = await MemoryExportService.shared.refreshCloudGrantConnectionStatus(for: destination)
    }
  }

  @ViewBuilder
  private var content: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      if destination.supportsAgentSetup {
        agentSetupSection
      } else if destination.supportsMCP {
        // Lead with the one action — "Do it for me". Everything manual (live
        // MCP fields, memory pack) is tucked behind a collapsed disclosure so
        // the default view stays simple.
        executeBlock
        manualSetupDisclosure
      } else if destination.supportsMemoryPack {
        methodHeader(
          icon: "doc.on.clipboard.fill",
          title: "Pacote de memórias",
          tag: "MANUAL",
          tagColor: Ink.secondary,
          subtitle: "Copie um retrato único e cole você mesmo. Não se atualiza sozinho."
        )
        packSection
        packActionButton
      }
    }
  }

  @ViewBuilder
  private var manualSetupDisclosure: some View {
    ManualInstallationDisclosure(
      isExpanded: $showManualSetup,
      title: destination == .chatgpt ? "Alternativa do modo desenvolvedor" : "Instalação manual",
      fontSize: 13
    ) {
      VStack(alignment: .leading, spacing: OmiSpacing.lg) {
        methodHeader(
          icon: "bolt.fill",
          title: destination == .chatgpt ? "App personalizado do ChatGPT" : "Conexão ao vivo",
          tag: destination == .chatgpt ? "AVANÇADO" : "AUTOMÁTICO",
          tagColor: destination == .chatgpt ? Ink.secondary : Ink.listeningGreen,
          subtitle: destination == .chatgpt
            ? "Use só quando seu workspace exigir um app personalizado em modo desenvolvedor."
            : "Configure uma vez e \(destination.title) lê suas memórias ao vivo e fica sincronizado."
        )
        mcpSection

        if destination.supportsMemoryPack {
          Divider()
            .background(Ink.rowFillHover)
            .padding(.vertical, OmiSpacing.hairline)
          methodHeader(
            icon: "doc.on.clipboard.fill",
            title: "Pacote de memórias",
            tag: "MANUAL",
            tagColor: Ink.secondary,
            subtitle: "Copie um retrato único e cole você mesmo. Não se atualiza sozinho."
          )
          packSection
          packActionButton
        }
      }
      .padding(.top, OmiSpacing.sm)
    }
  }

  private var agentSetupSection: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      agentSetupHeader

      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        agentSetupBullet("O Omi cria chaves de conexão novas para este prompt.")
        agentSetupBullet(
          "Seu agente pode ler memórias e conversas sincronizadas e usar este Mac para histórico de tela, capturas de tela, resumos, arquivos e tarefas."
        )
        agentSetupBullet(
          "O guia do Omi incluído ajuda o agente a escolher o contexto certo e a perguntar antes de alterar memórias."
        )
      }

      HStack(spacing: OmiSpacing.sm) {
        Button {
          Task {
            if let updatedStatus = await model.copyAgentSetupPrompt() {
              statuses[destination] = updatedStatus
            }
          }
        } label: {
          Label(model.isLoadingMCPKey ? "Preparing…" : "Copy prompt", systemImage: "sparkles")
        }
        .buttonStyle(OmiButtonStyle(.primary, size: .compact))
        .disabled(model.isLoadingMCPKey)

        Button {
          Task { await model.testAgentConnection() }
        } label: {
          Label(model.isTestingAgentConnection ? "Testing…" : "Test", systemImage: "checkmark.seal")
        }
        .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
        .disabled(model.isLoadingMCPKey || model.isTestingAgentConnection)
        .help("Testar o acesso hospedado e local ao Omi")

        Button {
          Task {
            await model.createNewAgentConnectionKey()
            statuses[destination] = await MemoryExportService.shared.status(for: destination)
          }
        } label: {
          Label("New key", systemImage: "key")
        }
        .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
        .disabled(model.isLoadingMCPKey || model.isTestingAgentConnection)
        .help("Criar novas chaves de conexão hospedadas e locais")
      }
    }
  }

  private var agentSetupHeader: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xs) {
      HStack(spacing: OmiSpacing.sm) {
        Text("Deixe seu agente fazer")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)
        Text("MCP + CLI")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundColor(Ink.listeningGreen)
          .padding(.horizontal, OmiSpacing.xs)
          .padding(.vertical, OmiSpacing.hairline)
          .background(Capsule().fill(Ink.listeningGreen.opacity(0.15)))
      }
      Text(
        "Copie um prompt de configuração para o seu agente. Ele conecta as memórias do Omi via MCP, ativa o acesso local ao Desktop pelo Omi CLI e inclui um guia curto do Omi que o agente pode guardar."
      )
      .scaledFont(size: OmiType.caption)
      .foregroundColor(Ink.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func agentSetupBullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: OmiSpacing.sm) {
      Image(systemName: "checkmark.circle.fill")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.listeningGreen)
        .padding(.top, 1)
      Text(text)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var executeButtonTitle: String {
    let presentation = executePresentation
    _ = permissionRefreshID
    return presentation.primaryActionTitle ?? "Conectado"
  }

  private var executePresentation: MemoryExportConnectionPresentation {
    MemoryExportConnectionPresentation.make(
      destination: destination,
      status: statuses[destination],
      isRunning: model.isExecuting,
      accessibilityPreflightMissing: MemoryExportExecutor.accessibilityPreflightMissing(
        for: destination)
    )
  }

  private var executeBlockSubtitle: String {
    switch destination.mcpExecuteKind {
    case .directoryApp:
      return
        "Abra a listagem aprovada do Omi no ChatGPT, adicione o Omi e autorize no ChatGPT. O Omi confere a conexão quando você voltar."
    case .localAutonomous:
      return
        "O Omi configura \(destination.title) para você, como uma tarefa que dá para acompanhar na barra flutuante. Se travar, use os passos manuais abaixo."
    case .browserAutonomous:
      if MemoryExportExecutor.accessibilityPreflightMissing(for: destination) {
        return
          "O Omi precisa da permissão de Acessibilidade para usar seu navegador com login ativo em \(destination.title). Se preferir não conceder, use os passos manuais abaixo."
      } else {
        return
          "O Omi usa seu navegador com login ativo para configurar \(destination.title). Se o login ou as permissões bloquearem, o Omi diz exatamente onde parou."
      }
    case .assisted:
      if destination.assistedOverlayHint != nil {
        return
          "O Omi abre \(destination.title) e mostra um cartão na tela. Copie cada valor com um clique e cole no formulário."
      }
      return
        "O Omi abre \(destination.title) e copia sua chave. Depois você confirma os passos rápidos abaixo."
    }
  }

  /// "Execute" — hands the whole setup to Omi to run as a task.
  private var executeBlock: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      if let completion = executePresentation.completion {
        setupCompleteBlock(completion)
      } else {
        HStack(spacing: OmiSpacing.sm) {
          Image(systemName: "sparkles")
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(Ink.secondary)
          Text(destination.mcpExecuteKind == .directoryApp ? "Conectar no ChatGPT" : "Deixe o Omi fazer")
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(Ink.primary)
          Text(destination.mcpExecuteKind == .directoryApp ? "UM CLIQUE" : "MAIS RÁPIDO")
            .scaledFont(size: OmiType.micro, weight: .bold)
            .foregroundColor(Ink.listeningGreen)
            .padding(.horizontal, OmiSpacing.xs)
            .padding(.vertical, OmiSpacing.hairline)
            .background(Capsule().fill(Ink.listeningGreen.opacity(0.15)))
        }
        Text(executeBlockSubtitle)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Button {
          Task {
            await model.executeWithOmi(destination: destination)
            statuses[destination] = await MemoryExportService.shared.refreshCloudGrantConnectionStatus(
              for: destination)
            // Assisted flow: the user pastes values by hand, so surface the
            // field-by-field steps instead of leaving them collapsed.
            if destination.mcpExecuteKind == .assisted, destination.assistedOverlayHint != nil {
              showManualSetup = true
            }
          }
        } label: {
          ConnectionModalActionButton(
            title: model.isExecuting ? "Iniciando o Omi…" : executeButtonTitle,
            isConnected: isConnected
          )
        }
        .buttonStyle(.plain)
        .disabled(model.isExecuting || isConnected)
      }
    }
  }

  private func setupCompleteBlock(_ completion: MCPSetupCompletionSummary) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      HStack(alignment: .top, spacing: OmiSpacing.sm) {
        Image(systemName: "checkmark.seal.fill")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.listeningGreen)
          .padding(.top, 1)
        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text(completion.title)
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(Ink.primary)
          if destination == .claudeCode {
            ClaudeCodeRestartSubtitle()
          } else {
            Text(completion.subtitle)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      if destination.cloudOAuthClientID != nil {
        Button(isDisconnecting ? "Desconectando…" : "Desconectar") {
          disconnectCloudConnection()
        }
        .buttonStyle(.plain)
        .foregroundColor(Ink.secondary)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .disabled(isDisconnecting)
      }
    }
    .padding(OmiSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
        .fill(Ink.rowFill)
        .overlay(
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
            .stroke(Ink.listeningGreen.opacity(0.22), lineWidth: 1))
    )
  }

  private func disconnectCloudConnection() {
    guard !isDisconnecting else { return }
    isDisconnecting = true
    model.errorMessage = nil
    model.statusMessage = nil
    Task { @MainActor in
      do {
        statuses[destination] = try await MemoryExportService.shared
          .disconnectCloudOAuthConnection(for: destination)
        model.statusMessage = "Desconectado de \(destination.title)."
      } catch {
        model.errorMessage = "Não foi possível desconectar de \(destination.title). Tente de novo."
      }
      isDisconnecting = false
    }
  }

  private var isConnected: Bool {
    guard destination.hasLocallyVerifiableLiveSetup else { return false }
    return statuses[destination]?.hasConnection == true
  }

  /// Labeled header that makes the automatic (MCP) vs manual (pack) choice obvious.
  private func methodHeader(
    icon: String, title: String, tag: String, tagColor: Color, subtitle: String
  ) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: icon)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundColor(tagColor)
        Text(title)
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)
        Text(tag)
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundColor(tagColor)
          .padding(.horizontal, OmiSpacing.xs)
          .padding(.vertical, OmiSpacing.hairline)
          .background(
            Capsule().fill(tagColor.opacity(0.15))
          )
      }
      Text(subtitle)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - MCP connection

  @ViewBuilder
  private var mcpSection: some View {
    let setup = destination.mcpSetup(key: model.mcpKey ?? "YOUR_OMI_KEY")
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      if destination == .claude {
        claudeConnectorFields
      } else if destination == .chatgpt {
        chatGPTDeveloperModeFields
      } else {
        mcpCodeRow(
          label: "URL do servidor", value: MemoryExportDestination.mcpServerURL, copyLabel: "URL do servidor")

        if destination.requiresHostedMCPKeyForSetup {
          mcpKeyRow
        }
      }

      if let setup, let copyText = setup.copyText, let copyTitle = setup.copyTitle {
        mcpSnippet(copyText, title: copyTitle, enabled: model.mcpKey != nil)
      }

      if let setup {
        VStack(alignment: .leading, spacing: OmiSpacing.xs) {
          ForEach(Array(setup.steps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: OmiSpacing.sm) {
              Text("\(index + 1).")
                .scaledFont(size: OmiType.caption, weight: .semibold)
                .foregroundColor(Ink.secondary)
              Text(step)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .padding(.top, OmiSpacing.hairline)

        if let openURL = setup.openURL, let openTitle = setup.openTitle {
          Button(openTitle) { model.open(openURL) }
            .buttonStyle(.plain)
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundColor(Ink.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private var claudeConnectorFields: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      Text("Copie estes campos para o formulário \"Add custom connector\" do Claude.")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.secondary)
        .fixedSize(horizontal: false, vertical: true)

      mcpCodeRow(label: "Name", value: "Omi Memory", copyLabel: "Name")

      mcpCodeRow(
        label: "Remote MCP server URL",
        value: MemoryExportDestination.mcpServerURL,
        copyLabel: "Remote MCP server URL"
      )

      Text("Advanced settings")
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(Ink.secondary)
        .padding(.top, OmiSpacing.hairline)

      mcpCodeRow(
        label: "OAuth Client ID",
        value: destination.cloudOAuthClientID ?? "",
        copyLabel: "OAuth Client ID")

      Text("Deixe o OAuth Client Secret em branco.")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var chatGPTDeveloperModeFields: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      Text("Copie estes campos só ao criar um app personalizado do ChatGPT em modo desenvolvedor.")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.secondary)
        .fixedSize(horizontal: false, vertical: true)

      mcpCodeRow(label: "Name", value: "Omi Memory", copyLabel: "Name")
      mcpCodeRow(
        label: "Connection / server URL",
        value: MemoryExportDestination.mcpServerURL,
        copyLabel: "Connection / server URL")
      mcpCodeRow(label: "Authentication", value: "OAuth", copyLabel: "Authentication")

      Text("Advanced OAuth settings")
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(Ink.secondary)
        .padding(.top, OmiSpacing.hairline)

      mcpCodeRow(
        label: "OAuth Client ID",
        value: destination.cloudOAuthClientID ?? "",
        copyLabel: "OAuth Client ID")
      Text("Deixe o OAuth Client Secret em branco.")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.secondary)
      mcpCodeRow(
        label: "Token auth method",
        value: destination.cloudTokenAuthMethod ?? "none",
        copyLabel: "Token auth method")
      mcpCodeRow(
        label: "Auth URL",
        value: MemoryExportDestination.mcpAuthorizeURL,
        copyLabel: "Auth URL")
      mcpCodeRow(
        label: "Token URL",
        value: MemoryExportDestination.mcpTokenURL,
        copyLabel: "Token URL")
    }
  }

  @ViewBuilder
  private var mcpKeyRow: some View {
    if let key = model.mcpKey {
      mcpCodeRow(label: "Sua chave", value: key, copyLabel: "Chave", secure: true)
    } else {
      Button(model.isLoadingMCPKey ? "Gerando…" : "Gerar chave de conexão") {
        Task { await model.generateMCPKey() }
      }
      .buttonStyle(OmiButtonStyle(.primary))
      .disabled(model.isLoadingMCPKey)
    }
  }

  private func mcpCodeRow(label: String, value: String, copyLabel: String, secure: Bool = false)
    -> some View
  {
    VStack(alignment: .leading, spacing: OmiSpacing.xs) {
      Text(label)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(Ink.secondary)
      HStack(spacing: OmiSpacing.sm) {
        Text(secure ? String(repeating: "•", count: min(value.count, 28)) : value)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.primary)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button("Copiar") { model.copyToPasteboard(value, label: copyLabel) }
          .buttonStyle(.plain)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundColor(Ink.secondary)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(Ink.rowFill)
          .overlay(
            RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
              .stroke(Ink.rowFill, lineWidth: 1))
      )
    }
  }

  private func mcpSnippet(_ text: String, title: String, enabled: Bool) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      Text(text)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OmiSpacing.md)
        .background(
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
            .fill(Ink.rowFill)
            .overlay(
              RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
                .stroke(Ink.rowFill, lineWidth: 1))
        )
      Button(title) { model.copyToPasteboard(text, label: title) }
        .buttonStyle(OmiButtonStyle(.primary))
        .disabled(!enabled)
    }
  }

  // MARK: - Memory pack

  @ViewBuilder
  private var packSection: some View {
    switch destination {
    case .notion:
      let notionConnected = NotionMCPConnector.shared.isConnected
      let notionSteps = [
        "Clique em Conectar e aprove o Omi no seu navegador",
        "O Omi cria uma página Omi Memories no seu workspace. Clique em Sincronizar quando quiser atualizar",
        "Encontre a página na barra lateral ou na busca do Notion",
      ]
      VStack(alignment: .leading, spacing: OmiSpacing.md) {
        selectedLocationCard(
          title: notionConnected ? "Conectado ao Notion" : "Ainda não conectado",
          value: notionConnected
            ? (NotionMCPConnector.shared.memoriesPageURL?.absoluteString
              ?? "A primeira sincronização cria sua página Omi Memories.")
            : "Uma aprovação no navegador conecta seu workspace."
        )

        if notionConnected {
          Button("Desconectar") {
            NotionMCPConnector.shared.disconnect()
            statuses[.notion] = nil
          }
          .buttonStyle(.plain)
          .foregroundColor(Ink.secondary)
          .scaledFont(size: OmiType.caption, weight: .medium)
        }

        VStack(alignment: .leading, spacing: OmiSpacing.xs) {
          ForEach(Array(notionSteps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: OmiSpacing.sm) {
              Text("\(index + 1).")
                .scaledFont(size: OmiType.caption, weight: .semibold)
                .foregroundColor(Ink.secondary)
              Text(step)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .padding(.top, OmiSpacing.hairline)
      }

    case .obsidian:
      let obsidianSteps = [
        "Escolha a pasta do seu cofre",
        "O Omi grava suas memórias em Omi/Memories.md e abre o Obsidian. Clique em Sincronizar quando quiser atualizar",
        "Se o Obsidian perguntar “Do you trust the author of this vault?”, escolha qualquer opção. O Omi só adiciona uma nota Markdown",
      ]
      VStack(alignment: .leading, spacing: OmiSpacing.md) {
        selectedLocationCard(
          title: model.obsidianVaultPath.isEmpty ? "Nenhum cofre selecionado ainda" : "Cofre selecionado",
          value: model.obsidianVaultPath.isEmpty
            ? "Escolha seu cofre do Obsidian uma vez e o Omi mantém `Omi/Memories.md` atualizado."
            : model.obsidianVaultPath
        )

        Button(model.obsidianVaultPath.isEmpty ? "Escolher cofre" : "Trocar cofre") {
          model.pickObsidianVault()
        }
        .buttonStyle(.plain)
        .foregroundColor(Ink.secondary)
        .scaledFont(size: OmiType.caption, weight: .medium)

        VStack(alignment: .leading, spacing: OmiSpacing.xs) {
          ForEach(Array(obsidianSteps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: OmiSpacing.sm) {
              Text("\(index + 1).")
                .scaledFont(size: OmiType.caption, weight: .semibold)
                .foregroundColor(Ink.secondary)
              Text(step)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .padding(.top, OmiSpacing.hairline)
      }

    case .chatgpt, .claude, .gemini:
      VStack(alignment: .leading, spacing: OmiSpacing.md) {
        Text(
          "O Omi vai gerar um pacote de memórias em Markdown, copiar o prompt e a exportação juntos, mostrar o arquivo no Finder e abrir \(destination.title)."
        )
        .scaledFont(size: OmiType.body)
        .foregroundColor(Ink.secondary)

        Text(destination.manualPrompt)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)
          .padding(OmiSpacing.md)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: OmiChrome.controlRadius, style: .continuous)
              .fill(Ink.rowFill)
              .overlay(
                RoundedRectangle(cornerRadius: OmiChrome.controlRadius, style: .continuous)
                  .stroke(Ink.rowFill, lineWidth: 1)
              )
          )
      }

    case .agents, .claudeCode, .codex, .openclaw, .hermes:
      EmptyView()
    }
  }

  private var packActionButton: some View {
    Button(model.isRunning ? actionTitle.running : actionTitle.idle) {
      Task {
        if let updatedStatus = await model.run(destination: destination) {
          statuses[destination] = updatedStatus
        }
      }
    }
    .buttonStyle(OmiButtonStyle(.primary))
    .disabled(model.isRunning)
  }

  private var actionTitle: (idle: String, running: String) {
    switch destination {
    case .notion:
      return NotionMCPConnector.shared.isConnected
        ? ("Sincronizar", "Sincronizando…") : ("Conectar", "Conectando…")
    case .obsidian:
      return (model.obsidianVaultPath.isEmpty ? "Escolher cofre" : "Exportar", "Exportando…")
    case .chatgpt, .claude, .gemini:
      return ("Copiar e abrir", "Preparando…")
    case .agents, .claudeCode, .codex, .openclaw, .hermes:
      return ("Copiar", "…")
    }
  }

  private func textField(_ title: String, text: Binding<String>, isSecure: Bool = false)
    -> some View
  {
    VStack(alignment: .leading, spacing: OmiSpacing.xs) {
      Text(title)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(Ink.secondary)

      Group {
        if isSecure {
          SecureField(title, text: text)
        } else {
          TextField(title, text: text)
        }
      }
      .textFieldStyle(.plain)
      .foregroundColor(Ink.primary)
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.md)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
          .fill(Ink.rowFill)
          .overlay(
            RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
              .stroke(Ink.rowFill, lineWidth: 1)
          )
      )
    }
  }

  private func selectedLocationCard(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xs) {
      Text(title)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(Ink.secondary)

      Text(value)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OmiSpacing.md)
        .padding(.vertical, OmiSpacing.md)
        .background(
          RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
            .fill(Ink.rowFill)
            .overlay(
              RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
                .stroke(Ink.rowFill, lineWidth: 1)
            )
        )
    }
  }
}
