import AppKit
import Combine
import CoreGraphics
import Foundation

// MARK: - Permissions (one at a time)

extension SBOnboardingModel {
  /// Nothing is asked of macOS until the user clicks. The probes this has to do
  /// first are cross-process, so the click dispatches onto the model's actor
  /// rather than blocking the button.
  func requestPerm(_ key: String) {
    // The same task owns the preflight and the request. Leaving the row can
    // cancel it through `pollTasks`, and the step guards below cover callers
    // that navigate without going through the normal teardown path.
    pollTasks[key]?.cancel()
    let task: Task<Void, Never> = Task { [weak self] in
      guard let self else { return }
      await self.performPermissionRequest(key)
    }
    pollTasks[key] = task
  }

  func performPermissionRequest(_ key: String) async {
    // The user may have changed a grant in System Settings while this step was
    // onscreen. Re-check it before opening another pane or asking macOS again.
    await refreshPermCheckOffMain(key)
    guard !Task.isCancelled, permissionKey(for: step) == key else { return }
    if isGranted(key) {
      setPermOn(key)
      autoAdvanceIfCurrent(key)
      return
    }

    switch key {
    case "microphone":
      micState = .waiting
      appState.requestMicrophonePermission()
      pollPermission(key)
    case "system_audio":
      // A Core Audio process tap has its own consent in addition to Screen
      // Recording TCC. Wait for Screen Recording, then reconcile a real tap
      // attempt before marking this permission granted.
      sysState = .waiting
      if !appState.hasScreenRecordingPermission {
        ScreenCaptureService.requestScreenRecordingAccessAndOpenSettings()
      } else if appState.systemAudioPermissionStatus == .denied {
        // Screen Recording is already granted and a real tap has already been
        // refused, so nothing here can raise a prompt again. Open the pane
        // instead of silently re-running the same failing attempt.
        appState.openScreenRecordingPreferences()
      }
      pollPermission(key)
    case "screen_recording":
      scrState = .waiting
      appState.checkScreenRecordingPermission()
      if appState.hasScreenRecordingPermission {
        setPermOn(key)
        autoAdvanceIfCurrent(key)
      } else {
        ScreenCaptureService.requestScreenRecordingAccessAndOpenSettings()
        pollPermission(key)
      }
    case "full_disk_access":
      requestFullDiskAccess()
    case "accessibility":
      accState = .waiting
      appState.triggerAccessibilityPermission()
      pollPermission(key)
    case "automation":
      let request = beginAutomationRequest()
      await withTaskCancellationHandler {
        await request.value
      } onCancel: {
        request.cancel()
      }
    case "notifications":
      requestNotifications()
    default: break
    }
  }

  /// Ask macOS for notification authorization through the same policy-driven
  /// path Settings uses (`AppState.requestNotificationPermission()`), never
  /// `UNUserNotificationCenter` directly. `notDetermined` raises the system
  /// prompt; `denied` opens System Settings instead of re-asking a spent
  /// prompt macOS will never show again.
  func requestNotifications() {
    notifState = .waiting
    appState.requestNotificationPermission()
    pollPermission("notifications")
  }

  func requestFullDiskAccess() {
    fdaState = .waiting
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
      NSWorkspace.shared.open(url)
      // Show the drag-to-grant helper card (drag the Omi icon into the FDA list),
      // matching Screen Recording's flow. Full Disk Access has no in-place toggle,
      // so the drag card is the fastest grant path (#9742). Both FDA entry points
      // (the permission step and the Files connector) route through here.
      Task { await PermissionDragGuidance.presentDragToGrantHelper(for: .fullDiskAccess) }
    }
    pollPermission("full_disk_access")
  }

  func pollPermission(_ key: String) {
    // Cancel only this key's prior poll — never a sibling permission's, so the
    // "both" mic+system-audio step can poll two grants at once.
    pollTasks[key]?.cancel()

    if key == "system_audio" {
      pollSystemAudioPermission()
      return
    }

    pollTasks[key] = Task { [weak self] in
      for _ in 0..<40 {  // ~20s
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let self, !Task.isCancelled, self.permissionKey(for: self.step) == key else { return }
        await self.refreshPermCheckOffMain(key)
        guard !Task.isCancelled, self.permissionKey(for: self.step) == key else { return }
        if self.isGranted(key) {
          self.setPermOn(key)
          // Auto-advance once the grant lands — the user shouldn't have to click
          // Continue after granting. Brief pause so the ✓ is visible, then only
          // advance if they're still on this permission's step (a late poll for a
          // step already left must never yank the flow forward).
          try? await Task.sleep(nanoseconds: 600_000_000)
          guard !Task.isCancelled, self.permissionKey(for: self.step) == key else { return }
          self.autoAdvanceIfCurrent(key)
          return
        }
      }
      // Timed out without a grant. This is a backstop, not the mechanism:
      // FDA/Accessibility routinely exceed 20s (open System Settings →
      // authenticate → toggle), and a grant made in that window is picked up by
      // `recheckActivePermission()` when the user switches back to Omi. Re-arm
      // the Allow button so the row is never stranded on "macOS…".
      guard let self, !Task.isCancelled, self.permissionKey(for: self.step) == key else { return }
      self.resetPermToAsk(key)
    }
  }

  /// Screen Recording TCC is only a prerequisite for system audio. The
  /// authoritative grant is a successful Core Audio tap attempt.
  private func pollSystemAudioPermission() {
    // A precheck and an Allow click can race to start this poll. Preserve one
    // authoritative consent attempt so an older task cannot advance the flow
    // after the replacement has already reconciled a newer result.
    pollTasks["system_audio"]?.cancel()
    pollTasks["system_audio"] = Task { [weak self] in
      for _ in 0..<40 {  // ~20s
        guard let self, !Task.isCancelled else { return }
        // Skipping this step is an explicit choice not to surface its consent.
        // Never let a late Screen Recording grant trigger the modal elsewhere.
        guard self.step == .systemAudio else { return }
        self.appState.checkScreenRecordingPermission()
        if self.appState.hasScreenRecordingPermission {
          // A real process-tap attempt is the only truthful preflight for
          // system audio. It completes without another prompt when consent was
          // already granted, so reconcile it before asking the user again.
          let granted = await self.appState.primeSystemAudioPermission()
          guard !Task.isCancelled else { return }
          guard granted else {
            // A refused tap re-arms Allow. That is only an escape when a retry
            // could plausibly succeed: `primeSystemAudioPermission` recorded
            // `.denied`, so once the Screen Recording prerequisite only landed
            // after launch the step now renders the relaunch offer instead of
            // an Allow button that would fail identically forever
            // (`SBPermissionRelaunchGate`).
            self.resetPermToAsk("system_audio")
            return
          }

          guard self.step == .systemAudio else { return }
          self.setPermOn("system_audio")
          try? await Task.sleep(nanoseconds: 600_000_000)
          guard !Task.isCancelled, self.step == .systemAudio else { return }
          self.autoAdvanceIfCurrent("system_audio")
          return
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
      }

      guard let self, !Task.isCancelled, self.step == .systemAudio else { return }
      self.resetPermToAsk("system_audio")
    }
  }

  /// Re-probe a single permission (each check writes the matching AppState flag).
  /// Prefer `refreshPermCheckOffMain` anywhere the probe can repeat — the
  /// Accessibility/FDA/Automation probes are cross-process and expensive.
  func refreshPermCheck(_ key: String) {
    switch key {
    case "microphone": appState.checkMicrophonePermission()
    case "system_audio":
      appState.checkScreenRecordingPermission()
      appState.checkSystemAudioPermission()
    case "screen_recording": appState.checkScreenRecordingPermission()
    case "full_disk_access": appState.checkFullDiskAccess()
    case "accessibility": appState.checkAccessibilityPermission()
    case "automation": appState.checkAutomationPermission()
    case "notifications": appState.checkNotificationPermission()
    default: appState.checkAllPermissions()
    }
  }

  /// When a permission step appears, reflect a grant the user already has so it
  /// shows ✓ instead of an Allow button they'd tap for nothing. Pre-existing
  /// grants are folded in live rather than from a snapshot, so a reinstall
  /// cannot leave a "Granted" row above a step that still wants an answer.
  func precheckPerm(_ key: String) {
    pollTasks[key]?.cancel()
    let task: Task<Void, Never> = Task { [weak self] in
      guard let self else { return }
      await self.precheckPermOffMain(key)
    }
    pollTasks[key] = task
  }

  func precheckPermOffMain(_ key: String) async {
    guard !Task.isCancelled, permissionKey(for: step) == key else { return }
    await refreshPermCheckOffMain(key)
    // The probe can outlive the step that started it (Automation's Apple Event
    // lookup takes a round trip). Writing a permission row for a page the user
    // already left is how a late answer used to land on the wrong step.
    guard !Task.isCancelled, permissionKey(for: step) == key else { return }
    if isGranted(key) {
      setPermOn(key)
    } else if key == "system_audio", appState.hasScreenRecordingPermission,
      appState.systemAudioPermissionStatus == .unknown
    {
      // Already holding Screen Recording must not skip this separate consent.
      // Prime while its own onboarding step is visible and reconcile the result.
      sysState = .waiting
      pollSystemAudioPermission()
    }
  }

  /// Fire a single throwaway ScreenCaptureKit capture the first time Screen
  /// Recording is confirmed granted during onboarding, so macOS surfaces the
  /// "bypass the private window picker" consent here — while the user is already
  /// granting screen access — instead of mid-question during the live screen demo
  /// (the exact spot users hit it). See `ScreenCaptureService.primeCaptureConsent`.
  func primeScreenCaptureConsentIfNeeded() {
    guard !didPrimeScreenCapture else { return }
    guard
      ScreenRecordingPermissionPolicy.shouldInvokeScreenCaptureKit(
        grantedAtLaunch: appState.screenRecordingGrantedAtLaunch)
    else { return }
    didPrimeScreenCapture = true
    if #available(macOS 14.0, *) {
      Task.detached { await ScreenCaptureService.primeCaptureConsent() }
    }
  }

  func isGranted(_ key: String) -> Bool {
    switch key {
    case "microphone": return appState.hasMicrophonePermission
    case "system_audio":
      return appState.hasSystemAudioPermission || appState.systemAudioPermissionStatus == .unsupported
    case "screen_recording": return appState.hasScreenRecordingPermission
    case "full_disk_access": return appState.hasFullDiskAccess
    case "accessibility": return appState.hasAccessibilityPermission && !appState.isAccessibilityBroken
    case "automation": return appState.hasAutomationPermission
    case "notifications": return appState.hasNotificationPermission
    default: return false
    }
  }

  func setPermOn(_ key: String) {
    switch key {
    case "microphone": micState = .on
    case "system_audio":
      sysState = .on
      // System audio shares Screen Recording TCC; once it's on, the ScreenCaptureKit
      // capture consent can be primed so the demo doesn't surface it later.
      primeScreenCaptureConsentIfNeeded()
    case "screen_recording":
      scrState = .on
      primeScreenCaptureConsentIfNeeded()
    case "full_disk_access":
      fdaState = .on
      // The Files connector row shares the FDA grant; reflect it here so the row
      // flips to "on" when FDA is granted from the context step — its poll only
      // drives fdaState, unlike every other connector that writes back its own state.
      contextStates["files"] = "on"
    // Do not read Apple Notes merely because Full Disk Access changed. The
    // explicit Connect action owns the data read.
    case "accessibility": accState = .on
    case "automation": autoState = .on
    case "notifications": notifState = .on
    default: break
    }
  }

  /// Return a still-`.waiting` row to `.ask` so its Allow button reappears after
  /// the poll times out without a grant (a later grant re-triggers the poll).
  func resetPermToAsk(_ key: String) {
    switch key {
    case "microphone": micState = .ask
    case "system_audio": sysState = .ask
    case "screen_recording": scrState = .ask
    case "full_disk_access": fdaState = .ask
    case "accessibility": accState = .ask
    case "automation": autoState = .ask
    case "notifications": notifState = .ask
    default: break
    }
  }

  func permState(_ key: String) -> PermState {
    switch key {
    case "microphone": return micState
    case "system_audio": return sysState
    case "screen_recording": return scrState
    case "full_disk_access": return fdaState
    case "accessibility": return accState
    case "automation": return autoState
    case "notifications": return notifState
    default: return .ask
    }
  }

  /// Skip on the mic step is a durable off for the automatic listening path: write
  /// `.off` so launch/restore never tries to start (and prompt) again. Allowing
  /// undoes an earlier skip so a user who goes Back and grants isn't left dark —
  /// the capture step's explicit answer remains the final word either way.
  func answerMic() {
    let allowed = micState == .on
    if allowed {
      if AssistantSettings.shared.audioRecordingMode == .off {
        AssistantSettings.shared.audioRecordingMode = .onlyMeetings
      }
    } else {
      AssistantSettings.shared.audioRecordingMode = .off
    }
    advance(userAnswer: allowed ? "Permitido" : "Pular", to: .systemAudio)
  }

  func answerSystemAudio() {
    UserDefaults.standard.set(sysState != .on, forKey: .onboardingSystemAudioSkipped)
    advance(userAnswer: sysState == .on ? "Permitido" : "Pular", to: .screen)
  }

  /// Skip on the screen step is a durable off for screen analysis — completion and
  /// every later automatic restore read this as the user's standing intent instead
  /// of force-enabling Rewind for someone who just declined it.
  func answerScreen() {
    AssistantSettings.shared.screenAnalysisEnabled = scrState == .on
    advance(userAnswer: scrState == .on ? "Permitido" : "Pular", to: .files)
  }
  /// A granted Files step builds the local-file profile. A skipped step must
  /// not enumerate Desktop/Documents/Downloads: touching those folders can
  /// itself raise Files & Folders consent when Full Disk Access is absent.
  func answerFiles() {
    guard fdaState == .on else {
      advance(userAnswer: "Pular", to: .accessibility)
      return
    }
    switch localFileProfileState {
    case .idle:
      thread.append(Msg(isOmi: false, text: "Permitido"))
      startLocalFileScan()
    case .scanning:
      break
    case .complete, .failed:
      finishFilesStep()
    }
  }

  func startLocalFileScan() {
    guard case .idle = localFileProfileState, localFileScanTask == nil else { return }
    localFileProfileState = .scanning
    let taskID = UUID()
    localFileScanID = taskID
    localFileScanTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.localFileScanID == taskID {
          self.localFileScanTask = nil
          self.localFileScanID = nil
        }
      }
      let result = await self.fileScanRunner(self.appState)
      guard !Task.isCancelled, self.step == .files, self.localFileScanID == taskID else { return }
      self.localFileProfileState = result
      if case .complete = result {
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasCompletedFileIndexing.rawValue)
        // If the app closes before the user taps Continue, resuming at Files
        // would otherwise run the scan and import a second time. The scan is
        // complete, so resume at the next stage instead.
        UserDefaults.standard.set(Step.accessibility.rawValue, forKey: Self.resumeStepKey)
      }
    }
  }

  func retryLocalFileScan() {
    guard case .failed = localFileProfileState else { return }
    localFileProfileState = .idle
    startLocalFileScan()
  }

  func finishFilesStep() {
    guard localFileProfileState.isTerminal else { return }
    advance(userAnswer: nil, to: .accessibility)
  }
  /// Skip on accessibility is a durable "not now": the sidebar must not pulse the
  /// row as denied for a user who explicitly walked past it. macOS exposes no
  /// denied/notDetermined distinction for AX, so the onboarding decision is the
  /// only honest signal — an Allow clears it, a Skip sets it.
  func answerAccessibility() {
    UserDefaults.standard.set(accState != .on, forKey: .onboardingAccessibilitySkipped)
    advance(userAnswer: accState == .on ? "Permitido" : "Pular", to: .automation)
  }
  func answerAutomation() { advance(userAnswer: autoState == .on ? "Permitido" : "Pular", to: .notifications) }
  func answerNotifications() { advance(userAnswer: notifState == .on ? "Permitido" : "Pular", to: .agents) }

  /// Advance past a permission step automatically once its grant lands — but only
  /// when the user is still ON that step, so a late poll never skips a step they've
  /// already moved past.
  func autoAdvanceIfCurrent(_ key: String) {
    autoAdvanceIfCurrent(key, needsRelaunch: permissionNeedsRelaunch(key))
  }

  func autoAdvanceIfCurrent(_ key: String, needsRelaunch: Bool) {
    guard permissionKey(for: step) == key, permState(key) == .on else { return }
    // A grant this process cannot act on must not move the flow on. Screen
    // Recording granted while running is on in System Settings and dead here
    // until relaunch; advancing would hand the user a live screen demo over a
    // capture path that cannot produce a frame. The step offers the reopen
    // instead (`SBPermissionRelaunchGate`).
    guard !needsRelaunch else { return }
    switch step {
    case .mic: answerMic()
    case .systemAudio: answerSystemAudio()
    case .screen: answerScreen()
    case .files: answerFiles()
    case .accessibility: answerAccessibility()
    case .automation: answerAutomation()
    case .notifications: answerNotifications()
    default: break
    }
  }

  /// The permission key a step gates on, or nil for non-permission steps.
  func permissionKey(for step: Step) -> String? {
    switch step {
    case .mic: return "microphone"
    case .systemAudio: return "system_audio"
    case .screen: return "screen_recording"
    case .files: return "full_disk_access"
    case .accessibility: return "accessibility"
    case .automation: return "automation"
    case .notifications: return "notifications"
    default: return nil
    }
  }

  /// Starting at `target`, skip past any permission step whose cached permission
  /// is already granted. The synchronous compatibility path is intentionally
  /// limited to the state already available on the main actor; callers that
  /// need a current TCC answer must use `firstUnaskedStepAwaitingCurrentProbes`.
  func firstUnaskedStep(from target: Step) -> Step {
    var step = target
    while let key = permissionKey(for: step) {
      // These probes are local/cheap. The cross-process probes intentionally
      // stay out of this synchronous compatibility path and are awaited by the
      // async entry point below.
      if ["microphone", "system_audio", "screen_recording"].contains(key) {
        refreshPermCheck(key)
      }
      // A pre-granted FDA permission must still visit Files once so this flow
      // performs the required scan and aggregate-memory formation.
      if step == .files, isGranted(key), !localFileProfileState.isTerminal {
        setPermOn(key)
        break
      }
      guard isGranted(key), let next = Step(rawValue: step.rawValue + 1) else { break }
      setPermOn(key)
      step = next
    }
    return step
  }

  /// First-unasked scan for entry points that need a current permission answer.
  /// Every TCC/AX/Apple Events probe is awaited through the off-main refresh
  /// seam, so this scan never blocks the main actor while deciding where to land.
  func firstUnaskedStepAwaitingCurrentProbes(
    from target: Step,
    refresh: ((String) async -> Void)? = nil
  ) async -> Step {
    var step = target
    while let key = permissionKey(for: step) {
      if let refresh {
        await refresh(key)
      } else {
        await refreshPermCheckOffMain(key)
      }
      guard !Task.isCancelled else { return step }

      // A pre-granted FDA permission must still visit Files once so this flow
      // performs the required scan and aggregate-memory formation.
      if step == .files, isGranted(key), !localFileProfileState.isTerminal {
        setPermOn(key)
        break
      }
      guard isGranted(key), let next = Step(rawValue: step.rawValue + 1) else { break }
      setPermOn(key)
      step = next
    }
    return step
  }
}
// MARK: - Agents (do things for you)

extension SBOnboardingModel {
  var agentRows: [(id: String, name: String, detail: String)] {
    [
      ("openclaw", "OpenClaw", "executa tarefas no seu Mac"),
      ("hermes", "Hermes", "agente autônomo em segundo plano"),
      ("claudeCode", "Claude Code", "programa nos seus repositórios"),
      ("codex", "Codex", "agente de programação da OpenAI"),
    ]
  }

  private func agentDestination(_ id: String) -> MemoryExportDestination {
    switch id {
    case "openclaw": return .openclaw
    case "hermes": return .hermes
    case "claudeCode": return .claudeCode
    case "codex": return .codex
    default: return .openclaw
    }
  }

  /// Brand mark for a connector row (agents + context), so every row shows its
  /// real logo even when the app isn't installed (#10210). Brands without a
  /// bundled logo (openclaw/hermes/files) fall back to the icon's default glyph.
  func connectorBrand(_ id: String) -> ConnectorBrand {
    switch id {
    case "openclaw": return .openclaw
    case "hermes": return .hermes
    case "claudeCode": return .claudeCode
    case "codex": return .codex
    case "calendar": return .calendar
    case "gmail": return .gmail
    case "applenotes": return .appleNotes
    case "files": return .localFiles
    case "chatgpt": return .chatgpt
    case "claude": return .claude
    default: return .agents
    }
  }

  func refreshAgentStates() {
    // Show a "checking" placeholder up front so a not-installed agent never briefly
    // offers a "Connect" button that only flips to "not installed" after a click
    // (the async install probe below resolves each row to its real state).
    for row in agentRows where agentStates[row.id] == nil {
      agentStates[row.id] = "checking"
    }
    Task { [weak self] in
      guard let self else { return }
      for row in self.agentRows {
        // Only offer Connect for agents actually present on this Mac; otherwise
        // mark "unavailable" so the row shows "not installed" with no button.
        let installed = await Self.agentInstalled(self.agentDestination(row.id))
        guard installed else {
          self.agentStates[row.id] = "unavailable"
          continue
        }
        let connected = await MemoryExportService.shared.status(for: self.agentDestination(row.id)).hasConnection
        self.agentStates[row.id] = connected ? "on" : "idle"
      }
    }
  }

  /// Local install probe using the SAME evidence the real connect path requires,
  /// so a row never offers "Connect" and then flips to "not installed" on click
  /// (e.g. Codex: a stray `~/.codex` dir is not enough — the connector needs the
  /// `codex` binary on PATH). Delegates to `MemoryBankConnector.isInstalled`.
  private static func agentInstalled(_ destination: MemoryExportDestination) async -> Bool {
    await Task.detached { MemoryBankConnector.isInstalled(destination) }.value
  }

  func connectAgent(_ id: String) {
    guard agentStates[id] != "connecting", agentStates[id] != "checking", agentStates[id] != "on" else { return }
    agentStates[id] = "connecting"
    let dest = agentDestination(id)
    Task { [weak self] in
      do {
        _ = try await MemoryExportExecutor.run(dest)
      } catch {
        self?.agentStates[id] = "unavailable"
        return
      }
      guard let self else { return }
      let connected = await MemoryExportService.shared.status(for: dest).hasConnection
      self.agentStates[id] = connected ? "on" : "idle"
    }
  }

  func answerAgents() { advance(userAnswer: "Continuar", to: .context) }
}

// MARK: - Context (connect what I can see)

extension SBOnboardingModel {
  enum ContextConnectionRoute: Equatable {
    case importConnector(String)
    case direct
  }

  struct GoogleContextResolution: Equatable {
    let state: String
    let detail: String?
    let shouldOpenSignIn: Bool
  }

  var contextRows: [(id: String, name: String, detail: String)] {
    [
      ("calendar", "Calendário", "reuniões + preparo"),
      ("gmail", "Gmail", "retornos de e-mail"),
      ("applenotes", "Apple Notes", "suas notas"),
      ("files", "Arquivos", "documentos neste Mac"),
      ("chatgpt", "ChatGPT", "leva a memória junto"),
      ("claude", "Claude", "leva a memória junto"),
    ]
  }

  func refreshContextStates() {
    if appState.hasFullDiskAccess { contextStates["files"] = "on" }
    Task { [weak self] in
      guard let self else { return }
      // Do not probe browser cookies or Apple Notes just to decorate a fresh
      // onboarding row.
      // A functional probe without a completed import used to paint "on" even
      // though post-onboarding Home/Apps had no persisted connector state and
      // no imported data. Only re-check a connector that this account already
      // completed through the canonical import path; a new source stays
      // explicitly connectable until the user starts that import.
      guard self.hasPersistedGoogleImport("calendar") || self.hasPersistedGoogleImport("gmail") else {
        return
      }
      if self.hasPersistedGoogleImport("calendar") {
        let calendar = await CalendarReaderService.shared.verifyConnection()
        self.projectGoogleVerification("calendar", status: calendar)
      }
      if self.hasPersistedGoogleImport("gmail") {
        let gmail = await GmailReaderService.shared.verifyConnection()
        self.projectGoogleVerification("gmail", status: gmail)
      }
    }
  }

  private func hasPersistedGoogleImport(_ contextID: String) -> Bool {
    guard
      let statusStore = importConnectorStatusStore,
      let connector = ImportConnector.all.first(where: {
        $0.id == Self.importConnectorID(forGoogleContextID: contextID)
      })
    else { return false }
    return statusStore.snapshot(for: connector).isConnected
  }

  private func markGoogleContextImported(_ id: String) {
    contextStates[id] = "on"
    contextDetails[id] = nil
  }

  private func projectGoogleVerification(_ id: String, status: CalendarConnectionStatus) {
    switch status {
    case .connected:
      markGoogleContextImported(id)
    case .needsSignIn:
      projectGoogleContext(id, connected: false, needsSignIn: true)
    case .error:
      projectGoogleContext(id, connected: false, needsSignIn: false)
    }
  }

  private func projectGoogleVerification(_ id: String, status: GmailConnectionStatus) {
    switch status {
    case .connected:
      markGoogleContextImported(id)
    case .needsSignIn:
      projectGoogleContext(id, connected: false, needsSignIn: true)
    case .error:
      projectGoogleContext(id, connected: false, needsSignIn: false)
    }
  }

  /// ChatGPT and Claude on this surface mean importing existing memories into
  /// Omi. Live MCP exports are a separate Apps > Exports action and must never
  /// be substituted here.
  nonisolated static func contextConnectionRoute(for id: String) -> ContextConnectionRoute {
    switch id {
    case "chatgpt", "claude":
      return .importConnector(id)
    default:
      return .direct
    }
  }

  nonisolated static func importConnectorID(forGoogleContextID id: String) -> String {
    id == "gmail" ? "email" : "calendar"
  }

  nonisolated static func googleContextResolution(
    connectorID: String,
    connected: Bool,
    needsSignIn: Bool
  ) -> GoogleContextResolution {
    if connected {
      return GoogleContextResolution(state: "on", detail: nil, shouldOpenSignIn: false)
    }
    let name = connectorID == "gmail" ? "Gmail" : "Google Calendar"
    let detail =
      needsSignIn
      ? "Abra o \(name) no Chrome, Arc, Brave ou Edge, entre na conta e tente de novo."
      : "Não foi possível verificar o \(name). Confira a sessão do navegador e a conexão, e tente de novo."
    return GoogleContextResolution(
      state: needsSignIn ? "needsSignIn" : "error",
      detail: detail,
      shouldOpenSignIn: needsSignIn
    )
  }

  /// Projects a cookie-based Google import/probe into bounded onboarding copy.
  /// Reconnect-required terminal imports open the browser separately; passive
  /// refreshes must only show an honest retry state, never steal focus.
  private func projectGoogleContext(_ id: String, connected: Bool, needsSignIn: Bool) {
    let resolution = Self.googleContextResolution(
      connectorID: id,
      connected: connected,
      needsSignIn: needsSignIn
    )
    contextStates[id] = resolution.state
    contextDetails[id] = resolution.detail
  }

  func connectContext(_ id: String) {
    guard contextStates[id] != "connecting", contextStates[id] != "on" else { return }
    // The view owns import-sheet presentation. Keep this guard so another
    // caller cannot accidentally route a memory import into the MCP exporter.
    guard Self.contextConnectionRoute(for: id) == .direct else { return }
    switch id {
    case "calendar":
      startGoogleContextImport("calendar") { progress in
        await ConnectorImportOperations.importCalendar(progress: progress)
      }
    case "gmail":
      startGoogleContextImport("gmail") { progress in
        await ConnectorImportOperations.importGmail(progress: progress)
      }
    case "applenotes":
      Task { [weak self] in
        guard let self else { return }
        // Full Disk Access covers Notes when it applies; if not, grant a
        // security-scoped folder bookmark (the real, re-sign-proof connect path).
        var status = await AppleNotesReaderService.shared.connectionStatus(userInitiated: true)
        if status.isConnected {
          self.contextStates["applenotes"] = "on"
          return
        }
        let pickedPath: String? = await MainActor.run {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          panel.allowsMultipleSelection = false
          panel.prompt = "Conceder acesso"
          panel.message = "Escolha a pasta de dados do Notas para eu poder lê-la."
          panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes")
          return panel.runModal() == .OK ? panel.url?.path : nil
        }
        guard let path = pickedPath else {
          self.contextStates["applenotes"] = "needsSignIn"
          return
        }
        do {
          _ = try await AppleNotesReaderService.shared.validateSelectedFolder(path: path)
          status = await AppleNotesReaderService.shared.connectionStatus(
            selectedFolderPath: path,
            userInitiated: true
          )
          self.contextStates["applenotes"] = status.isConnected ? "on" : "needsSignIn"
        } catch {
          self.contextStates["applenotes"] = "needsSignIn"
        }
      }
    case "files":
      appState.checkFullDiskAccess()
      if appState.hasFullDiskAccess {
        contextStates["files"] = "on"
      } else {
        requestFullDiskAccess()
        contextStates["files"] = "idle"
      }
    default: break
    }
  }

  /// Starts Gmail/Calendar through the exact shared importer that Apps uses.
  /// Success is deliberately a three-part predicate: the browser auth worked
  /// for a real data read, that read/import completed, and the account-scoped
  /// connector status persisted for the surface shown after onboarding.
  private func startGoogleContextImport(
    _ contextID: String,
    operation: @escaping @MainActor (ConnectorImportRunner.ProgressSink) async -> ConnectorImportOperations.Outcome
  ) {
    guard
      let statusStore = importConnectorStatusStore,
      let connector = ImportConnector.all.first(where: {
        $0.id == Self.importConnectorID(forGoogleContextID: contextID)
      })
    else {
      projectGoogleContext(contextID, connected: false, needsSignIn: false)
      return
    }

    let connectorID = connector.id
    let wasFirstSync = !statusStore.snapshot(for: connector).isConnected
    contextStates[contextID] = "connecting"
    contextDetails[contextID] = nil
    let task = ConnectorImportRunner.shared.start(
      connectorID: connectorID,
      progressTitle: "Conectando a \(connector.title)",
      progressDetail: "Lendo os dados e salvando na sua memória do Omi.",
      surface: .onboarding
    ) { [self] progress in
      let outcome = await operation(progress)
      let terminal = completeGoogleContextImport(
        contextID: contextID,
        connectorID: connectorID,
        outcome: outcome,
        statusStore: statusStore,
        wasFirstSync: wasFirstSync
      )
      if case .failure(_, let metrics) = terminal,
        let failureClass = metrics.failureClass,
        IntegrationConnectTelemetry.failureRequiresReconnect(failureClass),
        let url = URL(string: contextID == "gmail" ? "https://mail.google.com" : "https://calendar.google.com")
      {
        NSWorkspace.shared.open(url)
      }
      return terminal
    }
    if task == nil {
      // A shared Apps/onboarding import is already running. Don't leave the
      // row spinning indefinitely; the persisted status is updated by that
      // authoritative run and the user can retry once it settles.
      contextStates[contextID] = "error"
      contextDetails[contextID] = "Esta conexão já está sincronizando. Espere um instante e tente de novo."
    }
  }

  /// Applies an import terminal exactly once. Keeping this state transition in
  /// the onboarding model makes the durable Apps/Home status and the visible
  /// onboarding status change together, so one cannot report a false success.
  func completeGoogleContextImport(
    contextID: String,
    connectorID: String,
    outcome: ConnectorImportOperations.Outcome,
    statusStore: ImportConnectorStatusStore,
    wasFirstSync: Bool
  ) -> ConnectorImportRunner.RunOutcome {
    switch outcome {
    case .success(let result, let message):
      statusStore.markSynced(
        connectorID: connectorID,
        sourceCount: result.sourceCount,
        memoryCount: result.memoryCount,
        lastDeltaCount: result.newItems
      )
      markGoogleContextImported(contextID)
      return .success(
        message: message,
        metrics: ConnectorImportRunner.RunMetrics(
          sourceCount: result.sourceCount,
          memoryCount: result.memoryCount,
          wasFirstSync: wasFirstSync
        )
      )
    case .failure(let message, let failureClass):
      let reconnectRequired = failureClass.map(IntegrationConnectTelemetry.failureRequiresReconnect) ?? false
      projectGoogleContext(contextID, connected: false, needsSignIn: reconnectRequired)
      return .failure(
        message: message,
        metrics: ConnectorImportRunner.RunMetrics(
          failureClass: failureClass,
          wasFirstSync: wasFirstSync
        )
      )
    }
  }

  func markContextImportConnected(_ connectorID: String) {
    guard Self.contextConnectionRoute(for: connectorID) == .importConnector(connectorID) else { return }
    contextStates[connectorID] = "on"
    contextDetails[connectorID] = nil
  }

  /// Receives the canonical persisted connector ID from the shared import
  /// status store. Gmail's context-row ID differs from its Apps ID (`gmail`
  /// vs `email`), so translate at this one authority boundary rather than
  /// allowing a completed shared import to leave the onboarding row stale.
  func markPersistedContextConnectorConnected(_ connectorID: String) {
    switch connectorID {
    case "calendar": markGoogleContextImported("calendar")
    case "email": markGoogleContextImported("gmail")
    default: markContextImportConnected(connectorID)
    }
  }

  /// A reconnect failure intentionally hands focus to browser sign-in. Only terminal states
  /// that keep the user in Omi should summon the onboarding window.
  nonisolated static func shouldRefocusContext(from oldStates: [String: String], to newStates: [String: String]) -> Bool
  {
    oldStates.contains { id, state in
      state == "connecting" && (newStates[id] == "on" || newStates[id] == "error")
    }
  }

  func answerContext() { advance(userAnswer: "Continuar", to: .capture) }
}
