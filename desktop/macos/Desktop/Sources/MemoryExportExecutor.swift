import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Shared "Execute" logic for connector setup. Used by both the Execute button in
/// the connector sheet AND the automation bridge (`POST /execute-export`) so
/// headless e2e runs drive the exact same path — no separate execution flow.
///
/// Execution modes are explicit because local CLI setup and cloud-browser setup
/// have very different preflight requirements.
@MainActor
enum MemoryExportExecutor {
  enum Mode: Sendable { case autonomous, assisted, completed }
  struct Outcome: Sendable {
    let taskTitle: String
    let mode: Mode
  }

  enum ExecutorError: LocalizedError {
    case unsupported(String)
    case browserSetupRequired(String)
    var errorDescription: String? {
      switch self {
      case .unsupported(let name): return "\(name) não suporta uma tarefa de execução MCP."
      case .browserSetupRequired(let message): return message
      }
    }
  }

  static func run(_ destination: MemoryExportDestination) async throws -> Outcome {
    if case .directoryApp = destination.mcpExecuteKind {
      guard let directoryURL = destination.directoryInstallURL else {
        throw ExecutorError.unsupported(destination.title)
      }
      NSWorkspace.shared.open(directoryURL)
      return Outcome(
        taskTitle: "Abri o Omi no ChatGPT. Adicione o Omi e autorize por lá, depois volte ao Omi.",
        mode: .assisted)
    }

    if requiresAccessibilityPreflight(destination), !isAccessibilityReadyForBrowserSetup() {
      requestAccessibilityApprovalForCloudSetup()
      throw ExecutorError.browserSetupRequired(cloudSetupAccessibilityPermissionMessage)
    }

    let key = try await hostedMCPKey(for: destination)

    if MemoryBankConnector.handles(destination) {
      if canSkipLocalSetupWhenConfigMatches(destination),
        MemoryExportConnectionDetector.hasExistingConnection(for: destination, matchingKey: key)
      {
        return Outcome(taskTitle: "\(destination.title) já está conectado.", mode: .completed)
      }
      let message = try MemoryBankConnector.connect(destination, key: key)
      await MemoryExportService.shared.markConnected(destination)
      return Outcome(taskTitle: message, mode: .completed)
    }

    switch destination.mcpExecuteKind {
    case .directoryApp:
      throw ExecutorError.unsupported(destination.title)
    case .localAutonomous:
      guard let task = destination.omiExecutionTask(key: key) else {
        throw ExecutorError.unsupported(destination.title)
      }
      await createSetupTask(task: task)
      return Outcome(taskTitle: task.title, mode: .autonomous)

    case .browserAutonomous:
      return try await runBrowserAutonomous(destination, key: key)

    case .assisted:
      guard destination.omiExecutionTask(key: key) != nil else {
        throw ExecutorError.unsupported(destination.title)
      }
      return await runAssisted(destination, key: key)
    }
  }

  private static func canSkipLocalSetupWhenConfigMatches(_ destination: MemoryExportDestination) -> Bool {
    switch destination {
    case .claudeCode, .codex:
      return true
    case .openclaw, .hermes:
      return false
    case .notion, .obsidian, .chatgpt, .claude, .gemini, .agents:
      return false
    }
  }

  private static func hostedMCPKey(for destination: MemoryExportDestination) async throws -> String {
    guard destination.requiresHostedMCPKeyForSetup else { return "" }
    if MemoryBankConnector.handles(destination) {
      return try await MemoryExportService.shared.mcpKeyForLocalConnectorSetup()
    }
    return try await MemoryExportService.shared.ensureMCPKey()
  }

  static func requiresAccessibilityPreflight(_ destination: MemoryExportDestination) -> Bool {
    destination == .claude && destination.mcpExecuteKind == .browserAutonomous
  }

  static func accessibilityPreflightMissing(for destination: MemoryExportDestination) -> Bool {
    requiresAccessibilityPreflight(destination) && !isAccessibilityReadyForBrowserSetup()
  }

  private static func isAccessibilityReadyForBrowserSetup() -> Bool {
    AXIsProcessTrusted()
  }

  /// PARKED: no destination currently maps to `.browserAutonomous` — ChatGPT and
  /// Claude cloud moved to the assisted flow because AX/OCR automation of other
  /// people's web UIs proved too brittle across browsers and machines. Kept so a
  /// future DOM-perception rebuild has the routing to slot into. Do not remap a
  /// destination here without reading docs/cloud-connectors-roadmap.md.
  private static func runBrowserAutonomous(
    _ destination: MemoryExportDestination,
    key: String
  ) async throws -> Outcome {
    guard let setup = destination.mcpSetup(key: key), let openURL = setup.openURL else {
      throw ExecutorError.unsupported(destination.title)
    }

    if destination == .claude {
      return try await runClaudeNativeCloudSetup(setup: setup, openURL: openURL)
    }

    let browser = BrowserAutomationTargetResolver.defaultTarget(for: openURL)
    let browserName = browser?.name ?? "your default browser"

    guard let task = destination.guidedBrowserSetupTask(key: key, browserName: browserName) else {
      throw ExecutorError.unsupported(destination.title)
    }

    let pasteboardText =
      destination.requiresHostedMCPKeyForSetup
      ? "Server URL: \(setup.serverURL)\nKey: \(key)"
      : "Server URL: \(setup.serverURL)"
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(pasteboardText, forType: .string)

    if let browser {
      BrowserAutomationTargetResolver.open(openURL, in: browser)
    } else {
      NSWorkspace.shared.open(openURL)
    }

    await createSetupTask(task: task)
    return Outcome(taskTitle: task.title, mode: .autonomous)
  }

  private static func runClaudeNativeCloudSetup(
    setup: MCPSetup,
    openURL: URL
  ) async throws -> Outcome {
    CloudConnectorFormAutomation.dismissGuidanceOverlay()

    let args: [String: Any] = [
      "provider": "claude",
      "name": "Omi Memory",
      "server_url": setup.serverURL,
      "oauth_client_id": MemoryExportDestination.claude.cloudOAuthClientID ?? "",
      "submit": true,
    ]

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      """
      Name: Omi Memory
      Remote MCP server URL: \(setup.serverURL)
      OAuth Client ID: \(MemoryExportDestination.claude.cloudOAuthClientID ?? "")
      OAuth Client Secret: leave blank
      """,
      forType: .string)

    // For cloud setup, use the user's system default browser. Do not reuse the
    // Playwright/extension browser preference: that can point at Chrome even
    // when the user is signed into Claude in Atlas/Arc/another default browser.
    log("Claude cloud setup: opening connector page in default browser for native automation")
    NSWorkspace.shared.open(openURL)

    var lastResult = ""
    for attempt in 1...12 {
      try? await Task.sleep(nanoseconds: attempt == 1 ? 1_500_000_000 : 750_000_000)
      lastResult = await CloudConnectorFormAutomation.fill(args)
      log(
        "Claude cloud setup: native automation attempt \(attempt) result=\(cloudFormFillResultSummary(lastResult))"
      )
      if cloudFormFillSucceeded(lastResult) {
        CloudConnectorFormAutomation.dismissGuidanceOverlay()
        if lastResult.contains("Claude connector connected.") {
          await MemoryExportService.shared.markConnected(.claude)
        }
        return Outcome(
          taskTitle:
            "Formulário do conector do Claude enviado. Se o Claude mostrar um pedido final de consentimento, aprove o Omi Memory.",
          mode: .completed)
      }
      if cloudFormFillRequiresAccessibilityApproval(lastResult) {
        requestAccessibilityApprovalForCloudSetup()
        throw ExecutorError.browserSetupRequired(cloudSetupAccessibilityPermissionMessage)
      }
      if cloudFormFillNeedsManualClaudeAdd(lastResult),
        CloudConnectorFormAutomation.showClaudeAddGuidanceOverlay()
      {
        throw ExecutorError.browserSetupRequired(cloudSetupManualClaudeAddMessage)
      }
      if cloudFormFillRequiresScreenRecordingApproval(lastResult) {
        if CloudConnectorFormAutomation.showClaudeConnectGuidanceOverlay() {
          throw ExecutorError.browserSetupRequired(cloudSetupManualClaudeConnectMessage)
        } else {
          // We could not anchor to Claude. Send the user to grant Screen Recording, but
          // never leave them on a bare settings pane: show an instruction card too.
          requestScreenRecordingApprovalForCloudSetup()
          await CloudConnectorFormAutomation.showScreenRecordingSettingsInstructionOverlay(
            actionLabel: "Connect")
          throw ExecutorError.browserSetupRequired(cloudSetupScreenRecordingPermissionMessage)
        }
      }
      if !cloudFormFillShouldRetry(lastResult) {
        break
      }
    }

    log(
      "Claude cloud setup: stopping without agent fallback result=\(cloudFormFillResultSummary(lastResult))"
    )
    throw ExecutorError.browserSetupRequired(cloudSetupNativeAutomationBlockedMessage)
  }

  nonisolated static func cloudFormFillSucceeded(_ result: String) -> Bool {
    let cleanResult =
      !result.contains("Missing:")
      && !result.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Error:")
    return cleanResult
      && (result.contains("Submitted with button: Connect")
        || result.contains("Submitted with button: Create")
        || result.contains("Submitted with button: Save")
        || result.contains("Claude connector connected."))
  }

  static func cloudFormFillRequiresAccessibilityApproval(_ result: String) -> Bool {
    result.lowercased().contains("accessibility permission is not available")
  }

  static func cloudFormFillRequiresScreenRecordingApproval(_ result: String) -> Bool {
    result.lowercased().contains("screen recording permission is not available")
  }

  nonisolated static func cloudFormFillShouldRetry(_ result: String) -> Bool {
    result.contains("Could not find a visible")
      || result.contains("Submit skipped: no enabled")
      || result.contains("set failed")
      || result.contains("Submitted with button: Add")
  }

  private static func cloudFormFillResultSummary(_ result: String) -> String {
    let sanitized =
      result
      .split(separator: "\n")
      .filter { !$0.lowercased().contains("oauth client secret") }
      .joined(separator: " | ")
    return String(sanitized.prefix(500))
  }

  static func cloudFormFillNeedsManualClaudeAdd(_ result: String) -> Bool {
    let lower = result.lowercased()
    return lower.contains("hidden add button")
      || lower.contains("claude add connector button is not exposed")
      || (lower.contains("claude add") && lower.contains("not exposed to accessibility"))
      || (lower.contains("add connector button") && lower.contains("refusing blind"))
  }

  private static var cloudSetupNativeAutomationBlockedMessage: String {
    """
    O Omi abriu o Claude no seu navegador padrão, mas o Claude ainda precisa de um passo manual.

    Termine a configuração do conector na janela do Claude que já está aberta. Se o formulário do conector estiver preenchido, clique em Add. Se o Claude pedir permissão, aprove Omi Memory.

    Se nada estiver esperando no Claude, clique em "Faça por mim" de novo ou use os passos de instalação manual abaixo.
    """
  }

  private static var cloudSetupAccessibilityPermissionMessage: String {
    """
    O Omi precisa da permissão de Acessibilidade para terminar a configuração do Claude sozinho.

    Aprove a Acessibilidade para este app Omi nos Ajustes do Sistema e clique em "Faça por mim" de novo. Se não quiser conceder, use os passos de instalação manual abaixo.
    """
  }

  private static var cloudSetupScreenRecordingPermissionMessage: String {
    """
    O Omi precisa da permissão de Gravação de Tela para terminar a configuração do Claude sozinho.

    Adicionei o conector do Claude, mas o Claude esconde o botão final Connect da Acessibilidade neste navegador. Aprove a Gravação de Tela para este app Omi nos Ajustes do Sistema e clique em "Faça por mim" de novo.
    """
  }

  private static var cloudSetupManualClaudeConnectMessage: String {
    """
    O Claude está esperando um último clique.

    Adicionei o conector e apontei o botão Connect no seu navegador.
    """
  }

  private static var cloudSetupManualClaudeAddMessage: String {
    """
    O Claude está esperando um clique.

    Preenchi o formulário do conector e apontei o botão Add no seu navegador.
    """
  }

  private static func requestAccessibilityApprovalForCloudSetup() {
    let options =
      ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)
    guard !trusted,
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else { return }
    NSWorkspace.shared.open(url)
  }

  private static func requestScreenRecordingApprovalForCloudSetup() {
    // Actually request access first. CGRequestScreenCaptureAccess() both shows the
    // system consent prompt AND registers this app in the Screen Recording list with a
    // ready-to-flip toggle. Without it the app never appears in the list, so opening
    // Settings alone left the user with nothing to turn on.
    ScreenCaptureService.requestAllScreenCapturePermissions()

    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    else { return }
    NSWorkspace.shared.open(url)
  }

  /// Assisted setup: everything deterministic happens in code (copy the full
  /// field payload, open the deep link), then an on-screen card tells the user
  /// the one thing left to do. This is the primary path for ChatGPT/Claude cloud
  /// connectors — see docs/cloud-connectors-roadmap.md for why autonomous
  /// browser automation is parked and what replaces it.
  private static func runAssisted(_ destination: MemoryExportDestination, key: String) async -> Outcome {
    if let url = destination.mcpSetup(key: key)?.openURL {
      NSWorkspace.shared.open(url)
    }

    if let hint = destination.assistedOverlayHint,
      let sections = destination.assistedSetupSections(key: key)
    {
      CloudConnectorGuidanceOverlay.shared.presentFieldCopyCard(
        title: hint.title, subtitle: hint.subtitle, sections: sections, near: nil)
      return Outcome(
        taskTitle:
          "Abri \(destination.title). Copie cada valor do cartão na tela para o formulário.",
        mode: .assisted)
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(key, forType: .string)

    _ = await TasksStore.shared.createTask(
      description: "Terminar de conectar \(destination.title) ao Omi (página aberta, chave copiada)",
      dueAt: Date(), priority: "medium", tags: ["mcp-setup"])
    return Outcome(
      taskTitle: "Abri \(destination.title) e copiei sua chave. Conclua com os passos abaixo.",
      mode: .assisted)
  }

  private static func createSetupTask(task: (title: String, body: String)) async {
    _ = await TasksStore.shared.createTask(
      description: task.title, dueAt: Date(), priority: "high", tags: ["mcp-setup"])
  }
}

/// Detects running Claude Code CLI sessions so the post-setup UI can offer to
/// stop them (new MCP config only loads at session start). Stopping is safe-ish:
/// Claude Code persists conversations, so `claude --continue` resumes them.
enum ClaudeCodeSessions {
  /// The CLI binary is ".../bin/claude" (native install) or ".../bin/claude.exe"
  /// (pnpm/bun bundle). Claude Desktop and its helpers are capitalized
  /// ("Claude", "Claude Helper") and must never match.
  static func isClaudeCLI(executablePath: String) -> Bool {
    let name = (executablePath as NSString).lastPathComponent
    return name == "claude" || name == "claude.exe"
  }

  static func completionSubtitle(sessionCount: Int, didStop: Bool) -> String {
    if didStop {
      return "Sessões encerradas. Rode claude --continue no terminal para continuar de onde parou."
    }
    if sessionCount == 0 {
      return "Tudo pronto. O Omi Memory carrega automaticamente na sua próxima sessão do Claude Code."
    }
    return "Reinicie o Claude Code para carregar o Omi Memory."
  }

  /// Current user's running Claude Code CLI processes.
  static func runningPIDs() -> [pid_t] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,uid=,comm="]
    let pipe = Pipe()
    process.standardOutput = pipe
    do { try process.run() } catch { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    let uid = getuid()
    var pids: [pid_t] = []
    for line in output.split(separator: "\n") {
      // comm may contain spaces — keep everything after pid and uid as the path.
      let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
      guard fields.count == 3,
        let pid = pid_t(fields[0]),
        let lineUID = uid_t(fields[1]),
        lineUID == uid,
        isClaudeCLI(executablePath: String(fields[2]))
      else { continue }
      pids.append(pid)
    }
    return pids
  }

  static func stop(_ pids: [pid_t]) {
    for pid in pids where pid > 0 {
      kill(pid, SIGTERM)
    }
  }
}
