import OmiTheme
import SwiftUI

/// Standalone multi-phase onboarding view for setting up the Playwright MCP browser extension.
/// Can be presented as a sheet, overlay, or full page from any context.
struct BrowserExtensionSetup: View {
  var onComplete: () -> Void
  var onSkip: (() -> Void)? = nil
  var onDismiss: (() -> Void)? = nil

  /// Optional ChatProvider for running the connection test.
  /// When nil, Phase 3 is skipped (token is saved and we go straight to Done).
  var chatProvider: ChatProvider? = nil

  enum Phase: Int, CaseIterable {
    case welcome = 0
    case connect = 1
    case verify = 2
    case done = 3
  }

  @State private var phase: Phase = .welcome
  @State private var tokenInput: String = ""
  @State private var tokenError: String? = nil
  @State private var isVerifying = false
  @State private var verifyError: String? = nil
  @State private var verifySuccess = false
  @State private var selectedTarget =
    BrowserAutomationTargetResolver.preferredTarget() ?? BrowserAutomationTargetResolver.knownTargets[0]
  @State private var browserInstalled = false
  @State private var extensionStepDone = false
  @State private var tokenStepDone = false
  @State private var browserCheckTimer: Timer? = nil
  @State private var extensionCheckTimer: Timer? = nil

  var body: some View {
    VStack(spacing: 0) {
      // Top bar: progress dots + dismiss button
      HStack {
        Spacer()

        // Progress dots
        HStack(spacing: OmiSpacing.sm) {
          ForEach(Phase.allCases, id: \.rawValue) { p in
            Circle()
              .fill(p.rawValue <= phase.rawValue ? Ink.accent : Ink.hairline)
              .frame(width: 8, height: 8)
          }
        }

        Spacer()

        // Dismiss button (always visible)
        DismissButton(action: dismissSheet, showBackground: false)
      }
      .padding(.top, OmiSpacing.lg)
      .padding(.horizontal, OmiSpacing.lg)
      .padding(.bottom, OmiSpacing.md)

      // Phase content
      Group {
        switch phase {
        case .welcome:
          welcomePhase
        case .connect:
          connectPhase
        case .verify:
          verifyPhase
        case .done:
          donePhase
        }
      }
      .frame(maxWidth: .infinity)

      Spacer()

      // Bottom buttons
      VStack(spacing: OmiSpacing.sm) {
        Button(action: handlePrimaryAction) {
          Text(primaryButtonTitle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, OmiSpacing.sm)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isPrimaryDisabled)

        if let onSkip = onSkip, phase == .welcome {
          Button(action: onSkip) {
            Text("Pular por agora")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, OmiSpacing.page)
      .padding(.bottom, OmiSpacing.xxl)
    }
    .frame(width: phase == .connect ? 880 : 480, height: phase == .connect ? 520 : 420)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(Ink.wash)
        .overlay(
          RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
            .stroke(Ink.separator, lineWidth: 1)
        )
    )
    .omiAnimation(.easeInOut(duration: 0.3), value: phase)
  }

  // MARK: - Phase Views

  private var welcomePhase: some View {
    VStack(spacing: OmiSpacing.lg) {
      Image(systemName: "globe")
        .scaledFont(size: 48)
        .foregroundColor(Ink.primary)

      Text("Configurar acesso ao navegador")
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundColor(Ink.primary)

      Text(
        "Isso permite que a IA use a sessão do seu navegador, já conectada, para buscar na web, preencher formulários e interagir com sites por você."
      )
      .scaledFont(size: OmiType.body)
      .foregroundColor(Ink.secondary)
      .multilineTextAlignment(.center)
      .padding(.horizontal, OmiSpacing.page)

      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        featureRow(
          icon: "checkmark.shield",
          text: "Usa uma extensão do navegador (Chrome, Arc ou similar) para ler páginas em que você já está conectado")
        featureRow(icon: "key", text: "Configuração única do token de autenticação")
        featureRow(icon: "bolt", text: "Chega de pop-ups de Permitir/Recusar")
      }
      .padding(.horizontal, OmiSpacing.page)
      .padding(.top, OmiSpacing.sm)
    }
    .padding(.horizontal, OmiSpacing.xl)
  }

  /// Which GIF to show based on the current active step.
  private var activeGifName: String? {
    if !browserInstalled { return nil }
    if !extensionStepDone { return "installing_extension" }
    return "enabling_token"
  }

  private var connectPhase: some View {
    HStack(spacing: OmiSpacing.lg) {
      // Left side: steps
      VStack(spacing: OmiSpacing.lg) {
        Text("Conectar a extensão")
          .scaledFont(size: OmiType.heading, weight: .semibold)
          .foregroundColor(Ink.primary)

        browserPicker

        // Step 1: Install the selected browser
        HStack(alignment: .top, spacing: OmiSpacing.md) {
          stepBadge("1", done: browserInstalled)

          VStack(alignment: .leading, spacing: OmiSpacing.xs) {
            Text(browserInstalled ? "\(selectedTarget.name) está instalado" : "Instalar \(selectedTarget.name)")
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(browserInstalled ? Ink.secondary : Ink.primary)

            if !browserInstalled {
              Button(action: {
                if let url = selectedTarget.installURL {
                  NSWorkspace.shared.open(url)
                }
                startBrowserCheckTimer()
              }) {
                HStack(spacing: OmiSpacing.xxs) {
                  Image(systemName: "arrow.down.circle")
                    .scaledFont(size: OmiType.caption)
                  Text("Baixar \(selectedTarget.name)")
                    .scaledFont(size: OmiType.caption)
                }
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Step 2: Install extension from the browser's extension store
        HStack(alignment: .top, spacing: OmiSpacing.md) {
          stepBadge("2", done: extensionStepDone)

          VStack(alignment: .leading, spacing: OmiSpacing.xs) {
            Text("Instale a extensão Playwright MCP Bridge")
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(extensionStepDone ? Ink.secondary : Ink.primary)

            Button(action: {
              if let url = selectedTarget.extensionInstallURL() {
                BrowserAutomationTargetResolver.open(url, in: selectedTarget)
              }
              startExtensionCheckTimer()
            }) {
              HStack(spacing: OmiSpacing.xxs) {
                Image(systemName: extensionStepDone ? "checkmark" : "arrow.up.right.square")
                  .scaledFont(size: OmiType.caption)
                Text(extensionStepDone ? "Instalada" : "Adicionar extensão")
                  .scaledFont(size: OmiType.caption)
              }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!browserInstalled || extensionStepDone)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Step 3: Open extension settings & copy token
        HStack(alignment: .top, spacing: OmiSpacing.md) {
          stepBadge("3", done: tokenStepDone)

          VStack(alignment: .leading, spacing: OmiSpacing.xs) {
            Text("Abra a extensão e copie o token de autenticação")
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(tokenStepDone ? Ink.secondary : Ink.primary)

            Button(action: {
              if let url = selectedTarget.extensionStatusURL() {
                BrowserAutomationTargetResolver.open(url, in: selectedTarget)
              }
              OmiMotion.withGated(.easeInOut(duration: 0.2)) {
                tokenStepDone = true
              }
            }) {
              HStack(spacing: OmiSpacing.xxs) {
                Image(systemName: tokenStepDone ? "checkmark" : "key")
                  .scaledFont(size: OmiType.caption)
                Text(tokenStepDone ? "Aberto" : "Abrir ajustes da extensão")
                  .scaledFont(size: OmiType.caption)
              }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!browserInstalled)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Step 4: Paste token
        HStack(alignment: .top, spacing: OmiSpacing.md) {
          stepBadge("4", done: isTokenValid)

          VStack(alignment: .leading, spacing: OmiSpacing.xs) {
            Text("Cole aqui")
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(isTokenValid ? Ink.secondary : Ink.primary)

            TextField("Cole o token aqui…", text: $tokenInput)
              .textFieldStyle(.plain)
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.primary)
              .padding(OmiSpacing.sm)
              .background(
                RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
                  .fill(Ink.wash)
                  .overlay(
                    RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
                      .stroke(
                        tokenError != nil
                          ? Ink.errorRed.opacity(0.5)
                          : isTokenValid ? Ink.listeningGreen.opacity(0.5) : Ink.hairline,
                        lineWidth: 1
                      )
                  )
              )
              .disabled(!browserInstalled)
              .onChange(of: tokenInput) { _, _ in
                tokenError = nil
              }

            if let error = tokenError {
              Text(error)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.errorRed)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, OmiSpacing.page)
      .padding(.trailing, OmiSpacing.sm)
      .frame(maxWidth: .infinity)

      // Right side: GIF guide
      guidePanel
        .frame(maxWidth: .infinity)
        .padding(.trailing, OmiSpacing.xxl)
    }
    .onAppear {
      refreshBrowserState()
    }
    .onDisappear {
      browserCheckTimer?.invalidate()
      browserCheckTimer = nil
      extensionCheckTimer?.invalidate()
      extensionCheckTimer = nil
    }
  }

  private var browserPicker: some View {
    HStack(alignment: .center, spacing: OmiSpacing.sm) {
      Text("Navegador")
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(Ink.secondary)

      Picker("", selection: $selectedTarget) {
        ForEach(BrowserAutomationTargetResolver.knownTargets) { target in
          Text(target.name).tag(target)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .onChange(of: selectedTarget) { _, target in
        BrowserAutomationTargetStore.select(target)
        resetConnectionStateForSelectedBrowser()
        refreshBrowserState()
      }

      Spacer()

      if let defaultTarget = BrowserAutomationTargetResolver.defaultTarget(),
        defaultTarget.bundleIdentifier == selectedTarget.bundleIdentifier
      {
        Text("Padrão")
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundColor(Ink.listeningGreen)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Right-side guide panel showing the appropriate GIF for the current step.
  private var guidePanel: some View {
    VStack(spacing: OmiSpacing.md) {
      if let gifName = activeGifName {
        AnimatedGIFView(gifName: gifName)
          .id(gifName)
          .clipShape(RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
              .stroke(Ink.hairline, lineWidth: 1)
          )
      } else if !browserInstalled {
        VStack(spacing: OmiSpacing.md) {
          Image(systemName: "desktopcomputer")
            .scaledFont(size: OmiType.hero)
            .foregroundColor(Ink.secondary)
          Text("Instale o \(selectedTarget.name) para começar")
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
      }
    }
    .padding(.vertical, OmiSpacing.sm)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(Ink.wash)
    )
  }

  private var verifyPhase: some View {
    VStack(spacing: OmiSpacing.lg) {
      if isVerifying {
        ProgressView()
          .scaleEffect(1.5)
          .frame(height: 48)

        Text("Testando a conexão…")
          .scaledFont(size: OmiType.heading, weight: .semibold)
          .foregroundColor(Ink.primary)

        Text("Enviando uma requisição de teste para verificar se a extensão está funcionando.")
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, OmiSpacing.page)
      } else if verifySuccess {
        Image(systemName: "checkmark.circle.fill")
          .scaledFont(size: 48)
          .foregroundColor(Ink.listeningGreen)

        Text("Conectado")
          .scaledFont(size: OmiType.heading, weight: .semibold)
          .foregroundColor(Ink.primary)

        Text("A extensão do navegador está funcionando. A IA já pode usar o \(selectedTarget.name).")
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, OmiSpacing.page)
      } else if let error = verifyError {
        Image(systemName: "exclamationmark.triangle.fill")
          .scaledFont(size: 48)
          .foregroundColor(SettingsInk.notice)

        Text("Falha na conexão")
          .scaledFont(size: OmiType.heading, weight: .semibold)
          .foregroundColor(Ink.primary)

        Text(error)
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, OmiSpacing.page)

        Text("Confira se o \(selectedTarget.name) está aberto e se a página da extensão mostra \"Connected\".")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, OmiSpacing.page)
      }
    }
    .padding(.horizontal, OmiSpacing.xl)
  }

  private var donePhase: some View {
    VStack(spacing: OmiSpacing.lg) {
      Image(systemName: "checkmark.circle.fill")
        .scaledFont(size: 48)
        .foregroundColor(Ink.listeningGreen)

      Text("Tudo pronto")
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundColor(Ink.primary)

      Text(
        "O acesso ao navegador está configurado. A IA já pode navegar na web, preencher formulários e interagir com sites usando suas sessões do \(selectedTarget.name)."
      )
      .scaledFont(size: OmiType.body)
      .foregroundColor(Ink.secondary)
      .multilineTextAlignment(.center)
      .padding(.horizontal, OmiSpacing.page)
    }
    .padding(.horizontal, OmiSpacing.xl)
  }

  // MARK: - Helpers

  private func featureRow(icon: String, text: String) -> some View {
    HStack(spacing: OmiSpacing.sm) {
      Image(systemName: icon)
        .scaledFont(size: OmiType.body)
        .foregroundColor(Ink.secondary)
        .frame(width: 20)
      Text(text)
        .scaledFont(size: OmiType.body)
        .foregroundColor(Ink.secondary)
    }
  }

  /// The numbered disc beside a setup step, in the same two shapes `PermissionsPage`'s
  /// `instructionStep` uses — this sheet and that page are the same instruction, and they were
  /// drawn differently.
  ///
  /// The pending disc set `Ink.surface` on `Ink.hairline`: a white numeral on `labelColor` at 0.22,
  /// which over the light panel is a pale grey disc with nothing legible on it. `Ink.surface` is the
  /// *inverted* label and it is only ever correct over an `Ink.primary` fill. The done disc had the
  /// same shape of problem one step milder — white on `systemGreen` measures about 2:1 — so both
  /// now compose the ground from the tint the way `SettingsStatusChip` does, which keeps the fill
  /// and the label a pair rather than two independent choices.
  private func stepBadge(_ number: String, done: Bool = false) -> some View {
    let tint = done ? Ink.listeningGreen : Ink.primary
    return Group {
      if done {
        Image(systemName: "checkmark")
          .scaledFont(size: OmiType.caption, weight: .bold)
      } else {
        Text(number)
          .scaledFont(size: OmiType.caption, weight: .bold)
      }
    }
    .foregroundColor(tint)
    .frame(width: 22, height: 22)
    .background(Circle().fill(tint.opacity(0.14)))
  }

  /// Strip the "PLAYWRIGHT_MCP_EXTENSION_TOKEN=" prefix if the user copied the full env var line.
  static func parseToken(_ input: String) -> String {
    var token = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let eqIndex = token.firstIndex(of: "="), token.hasPrefix("PLAYWRIGHT") {
      token = String(token[token.index(after: eqIndex)...])
    }
    return token
  }

  /// Validate that a parsed token looks like a real extension auth token.
  /// Returns an error message if invalid, nil if valid.
  static func validateToken(_ token: String) -> String? {
    if token.isEmpty {
      return "Cole o token da página da extensão."
    }
    if token.count < 20 {
      return "O token está curto demais. Copie o token completo da página da extensão."
    }
    // Extension tokens are base64url: alphanumeric + hyphen + underscore
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    if token.unicodeScalars.contains(where: { !allowed.contains($0) }) {
      return "O token contém caracteres inválidos. Copie só o valor do token, sem o texto ao redor."
    }
    return nil
  }

  private func resetConnectionStateForSelectedBrowser() {
    tokenInput = ""
    tokenError = nil
    tokenStepDone = false
    verifyError = nil
    verifySuccess = false
  }

  private func refreshBrowserState() {
    browserInstalled = BrowserAutomationTargetResolver.isInstalled(selectedTarget)
    extensionStepDone = BrowserAutomationTargetResolver.isExtensionInstalled(in: selectedTarget)
  }

  /// Poll every 2 seconds to detect selected browser installation.
  private func startBrowserCheckTimer() {
    guard browserCheckTimer == nil else { return }
    browserCheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
      MainActor.assumeIsolated {
        if BrowserAutomationTargetResolver.isInstalled(selectedTarget) {
          OmiMotion.withGated(.easeInOut(duration: 0.2)) {
            browserInstalled = true
          }
          browserCheckTimer?.invalidate()
          browserCheckTimer = nil
        }
      }
    }
  }

  /// Poll every 2 seconds to detect extension installation.
  private func startExtensionCheckTimer() {
    guard extensionCheckTimer == nil else { return }
    extensionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
      MainActor.assumeIsolated {
        if BrowserAutomationTargetResolver.isExtensionInstalled(in: selectedTarget) {
          OmiMotion.withGated(.easeInOut(duration: 0.2)) {
            extensionStepDone = true
          }
          extensionCheckTimer?.invalidate()
          extensionCheckTimer = nil
        }
      }
    }
  }

  private func dismissSheet() {
    if let onDismiss = onDismiss {
      onDismiss()
    } else {
      onComplete()
    }
  }

  // MARK: - Button Logic

  private var primaryButtonTitle: String {
    switch phase {
    case .welcome:
      return "Configurar"
    case .connect:
      return "Continuar"
    case .verify:
      if isVerifying { return "Testando…" }
      if verifySuccess { return "Continuar" }
      return "Tentar de novo"
    case .done:
      return "OK"
    }
  }

  /// Whether the current token input parses and validates successfully.
  private var isTokenValid: Bool {
    let token = Self.parseToken(tokenInput)
    return Self.validateToken(token) == nil
  }

  private var isPrimaryDisabled: Bool {
    switch phase {
    case .connect:
      return tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .verify:
      return isVerifying
    default:
      return false
    }
  }

  private func handlePrimaryAction() {
    switch phase {
    case .welcome:
      OmiMotion.withGated(.easeInOut(duration: 0.2)) {
        phase = .connect
      }

    case .connect:
      let token = Self.parseToken(tokenInput)
      if let error = Self.validateToken(token) {
        tokenError = error
        return
      }
      UserDefaults.standard.set(token, forKey: "playwrightExtensionToken")
      log("BrowserExtensionSetup: Token saved (\(token.prefix(8))...)")

      if chatProvider != nil {
        OmiMotion.withGated(.easeInOut(duration: 0.2)) {
          phase = .verify
        }
        runConnectionTest()
      } else {
        // No provider available — skip verification, go to done
        OmiMotion.withGated(.easeInOut(duration: 0.2)) {
          phase = .done
        }
      }

    case .verify:
      if verifySuccess {
        OmiMotion.withGated(.easeInOut(duration: 0.2)) {
          phase = .done
        }
      } else {
        // Try again
        runConnectionTest()
      }

    case .done:
      onComplete()
    }
  }

  private func runConnectionTest() {
    guard let provider = chatProvider else { return }
    isVerifying = true
    verifyError = nil
    verifySuccess = false

    Task {
      do {
        let connected = try await provider.testPlaywrightConnection()
        await MainActor.run {
          isVerifying = false
          if connected {
            verifySuccess = true
            log("BrowserExtensionSetup: Connection test succeeded")
          } else {
            verifyError = "Não foi possível conectar à extensão. Confira se o \(selectedTarget.name) está aberto e tente de novo."
            log("BrowserExtensionSetup: Connection test returned false")
          }
        }
      } catch {
        await MainActor.run {
          isVerifying = false
          let msg = error.localizedDescription
          if msg.contains("timeout") || msg.contains("Extension connection timeout") {
            verifyError =
              "A conexão expirou. Confira se o \(selectedTarget.name) está aberto e se a extensão está instalada, e tente de novo."
          } else {
            verifyError = UserFacingErrorPresentation.message(for: error, while: .browserExtension)
          }
          log("BrowserExtensionSetup: Connection test error: \(error)")
        }
      }
    }
  }
}
