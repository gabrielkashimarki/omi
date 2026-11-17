import AppKit
import Foundation

/// Closed reason a presented notification left the screen. Auto-hide and explicit
/// close must not share a single "dismissed" bucket — that made engagement
/// unreadable (expiry counted as a user dismiss).
enum NotificationDismissalKind: String, CaseIterable, Sendable {
  case user
  case timeout
  case replaced
}

/// Closed source for `floating_bar_query_sent`. Historical events omit this
/// property; dashboards that need continuity with that volume should filter
/// `source=typed`.
enum FloatingBarQuerySource: String, CaseIterable, Sendable {
  case typed
  case ptt
  case pttVoiceOnly = "ptt_voice_only"
  case pttRealtime = "ptt_realtime"

}

/// Unified analytics manager that sends events to PostHog.
/// Use this instead of calling PostHogManager directly
@MainActor
class AnalyticsManager {
  static let shared = AnalyticsManager()

  /// Returns true for non-production Omi bundles so test apps don't pollute production analytics.
  nonisolated static var isDevBuild: Bool {
    AppBuild.isNonProduction
  }

  private var lastTranscriptionStartedAt: Date?
  /// Main-actor-isolated test observation at the actual AnalyticsManager
  /// boundary. It is nil in production and is deliberately not a mutable global
  /// outside the actor, so tests can observe the real event/payload safely under
  /// Swift concurrency.
  private var memoryAssistantTelemetryCaptureForTests: (@MainActor (String, [String: Any]) -> Void)?
  private var devicePairingTelemetryCaptureForTests: (@MainActor (String?, [String: Any], [String: Any]) -> Void)?

  private init() {}

  /// Install a scoped test observer for MemoryAssistant telemetry. Tests must
  /// clear it in teardown; production behavior remains the PostHog call below.
  func setMemoryAssistantTelemetryCaptureForTests(
    _ capture: (@MainActor (String, [String: Any]) -> Void)?
  ) {
    memoryAssistantTelemetryCaptureForTests = capture
  }

  private func captureMemoryAssistantTelemetryForTests(_ event: String, properties: [String: Any]) {
    memoryAssistantTelemetryCaptureForTests?(event, properties)
  }

  /// Scoped observation of the privacy-safe live-suggestion funnel. This lives
  /// at the same production boundary as PostHog so tests can assert the real
  /// event payload without initializing analytics or exposing a mutable global.
  private var suggestionAssistantTelemetryCaptureForTests: (@MainActor (String, [String: Any]) -> Void)?
  /// Delivery callbacks can race (for example a floating-bar enqueue and a system-banner
  /// completion). Keep one terminal outcome per opaque advice delivery ID at this boundary.

  func setSuggestionAssistantTelemetryCaptureForTests(
    _ capture: (@MainActor (String, [String: Any]) -> Void)?
  ) {
    suggestionAssistantTelemetryCaptureForTests = capture
  }

  private func captureSuggestionAssistantTelemetryForTests(_ event: String, properties: [String: Any]) {
    suggestionAssistantTelemetryCaptureForTests?(event, properties)
  }

  /// Scoped observation of Advice delivery telemetry. Tests install a capture at the same
  /// production boundary as PostHog; production leaves it nil.

  /// Test observer for integration-connect telemetry. Mirrors the
  /// MemoryAssistant seam: nil in production; tests install a scoped capture
  /// to observe the real event/payload without a mutable unsafe global.
  private var integrationConnectTelemetryCaptureForTests: (@MainActor (String, [String: Any]) -> Void)?

  /// Install a scoped test observer for integration-connect telemetry. Tests
  /// must clear it in teardown; production behavior remains the PostHog call.
  func setIntegrationConnectTelemetryCaptureForTests(
    _ capture: (@MainActor (String, [String: Any]) -> Void)?
  ) {
    integrationConnectTelemetryCaptureForTests = capture
  }

  private func captureIntegrationConnectTelemetryForTests(_ event: String, properties: [String: Any]) {
    integrationConnectTelemetryCaptureForTests?(event, properties)
  }

  /// Integration-nudge seam: nil in production; tests install a scoped capture
  /// to observe the real event names and payloads these methods emit.
  private var integrationNudgeTelemetryCaptureForTests: (@MainActor (String, [String: Any]) -> Void)?

  func setIntegrationNudgeTelemetryCaptureForTests(
    _ capture: (@MainActor (String, [String: Any]) -> Void)?
  ) {
    integrationNudgeTelemetryCaptureForTests = capture
  }

  private func trackIntegrationNudge(_ event: String, properties: [String: Any]) {
    integrationNudgeTelemetryCaptureForTests?(event, properties)
    PostHogManager.shared.track(event, properties: properties)
  }

  /// Notification-delivery-drop seam: nil in production; tests install a scoped
  /// capture to observe the real event/payload `NotificationService` emits when
  /// it drops a notification for lack of authorization.
  private var notificationDeliveryTelemetryCaptureForTests: (@MainActor (String, [String: Any]) -> Void)?

  /// Capture-attempt outcome seam: nil in production; tests install a scoped
  /// capture to observe the real event/payload the ambient-capture lifecycle
  /// emits at `AnalyticsManager`'s PostHog boundary.
  private var captureAttemptTelemetryCaptureForTests: (@MainActor (String, [String: Any]) -> Void)?

  func setCaptureAttemptTelemetryCaptureForTests(
    _ capture: (@MainActor (String, [String: Any]) -> Void)?
  ) {
    captureAttemptTelemetryCaptureForTests = capture
  }

  private func captureCaptureAttemptTelemetryForTests(_ event: String, properties: [String: Any]) {
    captureAttemptTelemetryCaptureForTests?(event, properties)
  }

  func setNotificationDeliveryTelemetryCaptureForTests(
    _ capture: (@MainActor (String, [String: Any]) -> Void)?
  ) {
    notificationDeliveryTelemetryCaptureForTests = capture
  }

  /// Monitoring-duration seam: nil in production; tests install a scoped
  /// capture to observe the real event names/payloads these methods emit.
  private var monitoringTelemetryCaptureForTests: (@MainActor (String, [String: Any]) -> Void)?

  func setMonitoringTelemetryCaptureForTests(
    _ capture: (@MainActor (String, [String: Any]) -> Void)?
  ) {
    monitoringTelemetryCaptureForTests = capture
  }

  private func trackMonitoring(_ event: String, properties: [String: Any]) {
    monitoringTelemetryCaptureForTests?(event, properties)
    PostHogManager.shared.track(event, properties: properties)
  }

  func setDevicePairingTelemetryCaptureForTests(
    _ capture: (@MainActor (String?, [String: Any], [String: Any]) -> Void)?
  ) {
    devicePairingTelemetryCaptureForTests = capture
  }

  /// Test seam for search events; emitters live in `Analytics/AnalyticsManager+Search.swift`.
  var searchTelemetryCaptureForTests: (@MainActor (String, [String: Any]) -> Void)?

  func setSearchTelemetryCaptureForTests(
    _ capture: (@MainActor (String, [String: Any]) -> Void)?
  ) {
    searchTelemetryCaptureForTests = capture
  }

  // MARK: - Initialization

  func initialize() {
    // Skip analytics in development builds
    guard !Self.isDevBuild else {
      log("Analytics: Skipping initialization (development build)")
      return
    }
    PostHogManager.shared.initialize()
  }

  // MARK: - User Identification

  func identify() {
    PostHogManager.shared.identify()
  }

  func reset() {
    PostHogManager.shared.reset()
  }

  // MARK: - Opt In/Out

  func optInTracking() {
    PostHogManager.shared.optIn()
  }

  func optOutTracking() {
    PostHogManager.shared.optOut()
  }

  // MARK: - Onboarding Events

  func onboardingStepCompleted(step: Int, stepName: String) {
    PostHogManager.shared.onboardingStepCompleted(step: step, stepName: stepName)
  }

  func onboardingHowDidYouHear(source: String) {
    let props: [String: Any] = ["source": source, "is_referral": source == "Friend"]
    PostHogManager.shared.track("Onboarding How Did You Hear", properties: props)
  }

  func onboardingCompleted() {
    PostHogManager.shared.onboardingCompleted()
  }

  func onboardingChatToolUsed(tool: String, properties: [String: Any] = [:]) {
    var props = properties
    props["tool"] = tool
    PostHogManager.shared.track("Onboarding Chat Tool Used", properties: props)
  }

  private static func boundedAnalyticsDimension(_ value: String) -> String {
    let normalized = value.lowercased().map { character in
      character.isLetter || character.isNumber || "._:-".contains(character) ? character : "_"
    }
    return String(normalized.prefix(80))
  }

  // MARK: - Authentication Events

  func signInStarted(provider: String) {
    PostHogManager.shared.signInStarted(provider: provider)
  }

  func signInCompleted(provider: String) {
    PostHogManager.shared.signInCompleted(provider: provider)
  }

  func signInFailed(provider: String, error: String, errorClass: String? = nil) {
    PostHogManager.shared.signInFailed(provider: provider, error: error, errorClass: errorClass)
  }

  func authFlowEvent(_ eventName: String, properties: [String: Any]) {
    PostHogManager.shared.authFlowEvent(eventName, properties: properties)
  }

  func signedOut() {
    PostHogManager.shared.signedOut()
  }

  // MARK: - Integration Connect Events

  /// Privacy-safe macOS integration-connect funnel. Mirrors the Flutter
  /// `Integration Connect Attempted/Succeeded/Failed` event names for
  /// cross-platform PostHog aggregation; dimensions are bounded by
  /// ``IntegrationConnectTelemetry``. See that type for the full contract.
  func integrationConnectAttempted(
    integrationName: String,
    connectorID: String,
    surface: IntegrationConnectTelemetry.Surface,
    stage: String
  ) {
    let payload = IntegrationConnectTelemetry.attemptedPayload(
      integrationName: integrationName, connectorID: connectorID,
      surface: surface, stage: stage)
    captureIntegrationConnectTelemetryForTests(
      IntegrationConnectTelemetry.attemptedEventName, properties: payload)
    PostHogManager.shared.track(
      IntegrationConnectTelemetry.attemptedEventName, properties: payload)
  }

  func integrationConnectSucceeded(
    integrationName: String,
    connectorID: String,
    surface: IntegrationConnectTelemetry.Surface,
    stage: String,
    durationMs: Int? = nil,
    sourceCount: Int? = nil,
    memoryCount: Int? = nil,
    wasFirstSync: Bool = false
  ) {
    let payload = IntegrationConnectTelemetry.succeededPayload(
      integrationName: integrationName, connectorID: connectorID,
      surface: surface, stage: stage, durationMs: durationMs,
      sourceCount: sourceCount, memoryCount: memoryCount, wasFirstSync: wasFirstSync)
    captureIntegrationConnectTelemetryForTests(
      IntegrationConnectTelemetry.succeededEventName, properties: payload)
    PostHogManager.shared.track(
      IntegrationConnectTelemetry.succeededEventName, properties: payload)
  }

  func integrationConnectFailed(
    integrationName: String,
    connectorID: String,
    surface: IntegrationConnectTelemetry.Surface,
    stage: String,
    errorClass: IntegrationConnectTelemetry.ErrorClass,
    durationMs: Int? = nil,
    wasFirstSync: Bool = false
  ) {
    let payload = IntegrationConnectTelemetry.failedPayload(
      integrationName: integrationName, connectorID: connectorID,
      surface: surface, stage: stage, errorClass: errorClass,
      durationMs: durationMs, wasFirstSync: wasFirstSync)
    captureIntegrationConnectTelemetryForTests(
      IntegrationConnectTelemetry.failedEventName, properties: payload)
    PostHogManager.shared.track(
      IntegrationConnectTelemetry.failedEventName, properties: payload)
  }

  // MARK: - Integration Nudge Events

  func integrationNudgeShown(
    entry: IntegrationNudgeCatalogEntry,
    trigger: IntegrationNudgeTrigger,
    shownCount: Int
  ) {
    trackIntegrationNudge(
      IntegrationNudgeTelemetry.shownEventName,
      properties: IntegrationNudgeTelemetry.shownPayload(
        integrationName: entry.displayName,
        route: entry.route,
        triggerID: trigger.id,
        triggerKind: trigger.kind,
        shownCount: shownCount
      )
    )
  }

  func integrationNudgeActioned(
    entry: IntegrationNudgeCatalogEntry,
    action: IntegrationNudgeTelemetry.Action,
    triggerID: String
  ) {
    trackIntegrationNudge(
      IntegrationNudgeTelemetry.actionedEventName,
      properties: IntegrationNudgeTelemetry.actionedPayload(
        integrationName: entry.displayName,
        route: entry.route,
        action: action,
        triggerID: triggerID
      )
    )
  }

  // MARK: - Notification Delivery Events

  /// A proactive notification was dropped because the app is not authorized to
  /// show it. See `NotificationDeliveryTelemetry` for the full contract. Never
  /// call this from a permission-request path — it only observes an existing
  /// drop, it must never itself trigger the system prompt.
  func notificationDeliverySkipped(
    authStatus: NotificationDeliveryTelemetry.AuthStatus,
    surface: ProactiveNotificationKind
  ) {
    let payload = NotificationDeliveryTelemetry.skippedPayload(authStatus: authStatus, surface: surface)
    notificationDeliveryTelemetryCaptureForTests?(NotificationDeliveryTelemetry.skippedEventName, payload)
    PostHogManager.shared.track(NotificationDeliveryTelemetry.skippedEventName, properties: payload)
  }

  // MARK: - Monitoring Events

  func monitoringStarted(sessionID: String) {
    trackMonitoring(
      MonitoringTelemetry.startedEventName,
      properties: MonitoringTelemetry.startedPayload(sessionID: sessionID))
  }

  func monitoringStopped(summary: MonitoringSummary) {
    trackMonitoring(
      MonitoringTelemetry.stoppedEventName,
      properties: MonitoringTelemetry.stoppedPayload(summary: summary))
  }

  /// Emits the missing `Monitoring Stopped` for a session recovered from disk
  /// at launch (crash or quit — see `MonitoringSessionRecovery`). Shares the
  /// `Monitoring Stopped` event name with a live stop; `duration_source`
  /// (`recovered_clean` / `recovered_heartbeat`) is what distinguishes a
  /// recovered row in analysis.
  func monitoringSessionRecovered(_ outcome: MonitoringSessionRecovery.Outcome) {
    trackMonitoring(
      MonitoringTelemetry.stoppedEventName,
      properties: MonitoringTelemetry.recoveredStoppedPayload(outcome))
  }

  /// Recovers a monitoring session that never got to emit its live
  /// `Monitoring Stopped` — either the app quit (`applicationWillTerminate`
  /// stamped `endedAt`/`endReason` synchronously; there is no synchronous
  /// PostHog flush available at terminate time) or crashed outright (no
  /// stamp at all; the last heartbeat is the only evidence). Call once at
  /// launch, adjacent to `detectAndReportCrash()`.
  ///
  /// Ownership is enforced in the store, not here: a rewind-only process reads
  /// nil and writes nothing, so this is a no-op there without needing its own
  /// launch-mode check. See `MonitoringSessionDefaultsStore.shared`.
  func recoverMonitoringSessionIfNeeded() {
    guard let record = MonitoringSessionDefaultsStore.shared.load() else { return }
    let outcome = MonitoringSessionRecovery.recover(record, now: Date())
    monitoringSessionRecovered(outcome)
    MonitoringSessionDefaultsStore.shared.clear()
  }

  // MARK: - Recording Events

  func transcriptionStarted(attemptId: String? = nil, mode: String? = nil, intent: String? = nil) {
    // Debounce: skip if called within 5 seconds (catches rapid wake/reconnect double-fires)
    if let last = lastTranscriptionStartedAt, Date().timeIntervalSince(last) < 5 {
      return
    }
    lastTranscriptionStartedAt = Date()
    PostHogManager.shared.transcriptionStarted(attemptId: attemptId, mode: mode, intent: intent)
  }

  func transcriptionStopped(wordCount: Int, attemptId: String? = nil, reason: String? = nil) {
    PostHogManager.shared.transcriptionStopped(wordCount: wordCount, attemptId: attemptId, reason: reason)
  }

  /// Terminal outcome of one armed ambient-capture attempt. Observes the
  /// acceptance registry first so `conversation_accepted` reflects every
  /// accepted conversation of this attempt observed before emission.
  func captureAttemptOutcome(
    _ attempt: inout CaptureAttemptOutcomeState,
    finalizationReason: TranscriptionFinalizationReason
  ) {
    if CaptureAttemptAcceptanceRegistry.consumeAccepted(attempt.attemptId) {
      attempt.noteConversationAccepted()
    }
    let properties = PostHogManager.captureAttemptOutcomeProperties(attempt, finalizationReason: finalizationReason)
    captureCaptureAttemptTelemetryForTests(PostHogManager.captureAttemptOutcomeEventName, properties: properties)
    PostHogManager.shared.captureAttemptOutcome(properties: properties)
  }

  /// Mid-flight process death discovered by next-run crash recovery: only the
  /// persisted join key is knowable, so the payload is deliberately minimal.
  func captureAttemptPendingOutcome(attemptId: String) {
    let properties = PostHogManager.captureAttemptPendingProperties(attemptId: attemptId)
    captureCaptureAttemptTelemetryForTests(PostHogManager.captureAttemptOutcomeEventName, properties: properties)
    PostHogManager.shared.captureAttemptOutcome(properties: properties)
  }

  func recordingError(
    error: String,
    reason: String? = nil,
    source: String? = nil,
    stage: String? = nil,
    retryCount: Int? = nil
  ) {
    PostHogManager.shared.recordingError(
      error: error,
      reason: reason,
      source: source,
      stage: stage,
      retryCount: retryCount
    )
  }

  func conversationReconciliationFailed(
    error: String,
    reason: String,
    source: String?,
    stage: String?,
    retryCount: Int,
    hasBackendId: Bool,
    hasClientConversationId: Bool,
    segmentCount: Int?,
    diagnostics: ReconciliationFailureDiagnostics? = nil
  ) {
    PostHogManager.shared.conversationReconciliationFailed(
      error: error,
      reason: reason,
      source: source,
      stage: stage,
      retryCount: retryCount,
      hasBackendId: hasBackendId,
      hasClientConversationId: hasClientConversationId,
      segmentCount: segmentCount,
      diagnostics: diagnostics
    )
  }

  // MARK: - Permission Events

  func permissionRequested(permission: String, extraProperties: [String: Any] = [:]) {
    PostHogManager.shared.permissionRequested(
      permission: permission, extraProperties: extraProperties)
  }

  func permissionGranted(permission: String, extraProperties: [String: Any] = [:]) {
    PostHogManager.shared.permissionGranted(
      permission: permission, extraProperties: extraProperties)
  }

  func permissionDenied(permission: String, extraProperties: [String: Any] = [:]) {
    PostHogManager.shared.permissionDenied(permission: permission, extraProperties: extraProperties)
  }

  func permissionSkipped(permission: String, extraProperties: [String: Any] = [:]) {
    PostHogManager.shared.permissionSkipped(
      permission: permission, extraProperties: extraProperties)
  }

  /// Track Bluetooth state changes for debugging
  func bluetoothStateChanged(
    oldState: String, newState: String, oldStateRaw: Int, newStateRaw: Int, authorization: String,
    authorizationRaw: Int
  ) {
    let properties: [String: Any] = [
      "old_state": oldState,
      "new_state": newState,
      "old_state_raw": oldStateRaw,
      "new_state_raw": newStateRaw,
      "authorization": authorization,
      "authorization_raw": authorizationRaw,
    ]
    PostHogManager.shared.track("Bluetooth State Changed", properties: properties)
  }

  func devicePairingReady(
    device: BtDevice,
    isNewPair: Bool,
    isFirstPair: Bool,
    firstPairedAt: Date?
  ) {
    let vendor = device.type.analyticsVendorSlug
    let eventProperties: [String: Any] = [
      "device_vendor": vendor,
      "device_type": device.type.rawValue,
      "model": device.displayModelNumber,
      "is_first_pair": isFirstPair,
    ]
    var userProperties: [String: Any] = [
      "has_paired_device": true,
      "paired_device_type": device.type.rawValue,
      "device_vendor": vendor,
    ]
    if let firstPairedAt {
      userProperties["first_paired_at"] = ISO8601DateFormatter().string(from: firstPairedAt)
    }

    devicePairingTelemetryCaptureForTests?(
      isNewPair ? "Device Paired" : nil,
      eventProperties,
      userProperties
    )
    if isNewPair {
      PostHogManager.shared.track("Device Paired", properties: eventProperties)
    }
    PostHogManager.shared.setUserProperties(userProperties)
  }

  private var deviceConnectionTelemetryCaptureForTests: (@MainActor (String) -> Void)?

  func setDeviceConnectionTelemetryCaptureForTests(
    _ capture: (@MainActor (String) -> Void)?
  ) {
    deviceConnectionTelemetryCaptureForTests = capture
  }

  func deviceConnected(device: BtDevice) {
    let vendor = device.type.analyticsVendorSlug
    let eventProperties: [String: Any] = [
      "device_vendor": vendor,
      "device_type": device.type.rawValue,
    ]
    deviceConnectionTelemetryCaptureForTests?("Device Connected")
    PostHogManager.shared.track("Device Connected", properties: eventProperties)
    PostHogManager.shared.setUserProperties(["device_vendor": vendor])
  }

  func deviceDisconnected() {
    deviceConnectionTelemetryCaptureForTests?("Device Disconnected")
    PostHogManager.shared.track("Device Disconnected")
  }

  /// Report when ScreenCaptureKit broken state is detected (TCC granted but capture failing).
  func screenCaptureBrokenDetected() {
    guard !Self.isDevBuild else { return }
    log("Analytics: Screen Capture Broken Detected")
  }

  /// Track when user clicks reset button or notification to reset screen capture
  func screenCaptureResetClicked(source: String) {
    PostHogManager.shared.screenCaptureResetClicked(source: source)
  }

  /// Track when screen capture reset completes (success or failure)
  func screenCaptureResetCompleted(success: Bool) {
    PostHogManager.shared.screenCaptureResetCompleted(success: success)
  }

  /// Track when notification repair is triggered (auto-repair or error-triggered)
  func notificationRepairTriggered(reason: String, previousStatus: String, currentStatus: String) {
    PostHogManager.shared.notificationRepairTriggered(
      reason: reason, previousStatus: previousStatus, currentStatus: currentStatus)
  }

  /// Track notification settings status (auth, alertStyle, sound, badge)
  func notificationSettingsChecked(
    authStatus: String,
    alertStyle: String,
    soundEnabled: Bool,
    badgeEnabled: Bool,
    bannersDisabled: Bool
  ) {
    PostHogManager.shared.notificationSettingsChecked(
      authStatus: authStatus,
      alertStyle: alertStyle,
      soundEnabled: soundEnabled,
      badgeEnabled: badgeEnabled,
      bannersDisabled: bannersDisabled
    )
  }

  // MARK: - Crash Detection

  /// Detect if the previous session crashed (no clean exit) and report to PostHog.
  /// Must be called AFTER analytics initialization but BEFORE appLaunched().
  func detectAndReportCrash() {
    guard !Self.isDevBuild else { return }

    let cleanExitKey = "lastSessionCleanExit"
    let hasLaunchedBeforeKey = "crashDetection_hasLaunchedBefore"

    let hadPreviousSession = UserDefaults.standard.bool(forKey: hasLaunchedBeforeKey)
    let lastCleanExit = UserDefaults.standard.bool(forKey: cleanExitKey)

    // Mark that we've launched at least once (skip crash report on very first launch)
    UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)

    // Clear the flag — will be set back to true only on clean exit
    UserDefaults.standard.set(false, forKey: cleanExitKey)

    if hadPreviousSession && !lastCleanExit {
      log("Analytics: Previous session did not exit cleanly — reporting crash")
      log(
        "Analytics: App Crash Detected; version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")"
      )
    }
  }

  // MARK: - App Lifecycle Events

  func appLaunched() {
    PostHogManager.shared.appLaunched()
  }

  /// A process reports startup once. `ViewModelContainer.loadAllData()` runs
  /// again after an owner switch, and that second run is not a launch.
  private var didReportStartupTiming = false

  /// Report one launch's startup timing.
  ///
  /// - `dataLoadMs` is the critical startup path inside `loadAllData()`. This is
  ///   what the old `time_to_interactive_ms` actually measured, which is why it
  ///   reported 11–131ms for a "cold start".
  /// - `timeToInteractiveMs` is measured from the kernel's process-start stamp,
  ///   so it includes dyld, `main`, and everything before the data load. It is
  ///   omitted rather than faked when the kernel lookup fails.
  func trackStartupTiming(
    dbInitMs: Double, dataLoadMs: Double, hadUncleanShutdown: Bool,
    databaseInitFailed: Bool,
    timeToInteractiveMs: Double? = AppStartupTiming.millisecondsSinceProcessStart()
  ) {
    guard !Self.isDevBuild else { return }
    guard !didReportStartupTiming else { return }
    didReportStartupTiming = true

    var properties: [String: Any] = [
      "db_init_ms": round(dbInitMs),
      "data_load_ms": round(dataLoadMs),
      "had_unclean_shutdown": hadUncleanShutdown,
      "database_init_failed": databaseInitFailed,
    ]
    if let timeToInteractiveMs {
      properties["time_to_interactive_ms"] = round(timeToInteractiveMs)
    }

    PostHogManager.shared.track("App Startup Timing", properties: properties)
  }

  /// Track first launch with comprehensive system diagnostics
  /// This only fires once per installation
  func trackFirstLaunchIfNeeded() {
    // Skip in dev builds
    guard !Self.isDevBuild else { return }

    let defaults = UserDefaults.standard
    let hasLaunchedKey = "hasLaunchedBefore"

    // Check if this is the first launch
    guard !defaults.bool(forKey: hasLaunchedKey) else {
      return
    }

    // Mark as launched so this only fires once
    defaults.set(true, forKey: hasLaunchedKey)

    // Collect system diagnostics
    let diagnostics = collectSystemDiagnostics()

    // Track in all analytics systems
    PostHogManager.shared.firstLaunch(diagnostics: diagnostics)

    log("Analytics: First launch diagnostics tracked")
  }

  /// Collect comprehensive system diagnostics for first launch event
  private func collectSystemDiagnostics() -> [String: Any] {
    var diagnostics: [String: Any] = [:]

    // App version
    diagnostics["app_version"] =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    diagnostics["build_number"] =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

    // macOS version (detailed)
    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    diagnostics["os_version"] =
      "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
    diagnostics["os_major_version"] = osVersion.majorVersion
    diagnostics["os_minor_version"] = osVersion.minorVersion
    diagnostics["os_patch_version"] = osVersion.patchVersion
    diagnostics["os_version_string"] = ProcessInfo.processInfo.operatingSystemVersionString

    // Architecture (Apple Silicon vs Intel)
    #if arch(arm64)
      diagnostics["architecture"] = "arm64"
      diagnostics["is_apple_silicon"] = true
    #elseif arch(x86_64)
      diagnostics["architecture"] = "x86_64"
      diagnostics["is_apple_silicon"] = false
    #else
      diagnostics["architecture"] = "unknown"
      diagnostics["is_apple_silicon"] = false
    #endif

    // App bundle location - helps diagnose installation issues
    if let bundlePath = Bundle.main.bundlePath as String? {
      // Categorize the installation location
      if bundlePath.hasPrefix("/Volumes/") {
        diagnostics["install_location"] = "dmg_mounted"
      } else if bundlePath.contains("/Downloads/") {
        diagnostics["install_location"] = "downloads_folder"
      } else if bundlePath.hasPrefix("/Applications/") {
        diagnostics["install_location"] = "applications_system"
      } else if bundlePath.contains("/Applications/") {
        diagnostics["install_location"] = "applications_user"
      } else if bundlePath.contains("DerivedData") || bundlePath.contains("Xcode") {
        diagnostics["install_location"] = "xcode_build"
      } else {
        diagnostics["install_location"] = "other"
      }
      diagnostics["is_standard_install"] = bundlePath.hasPrefix("/Applications/")
    }

    // Device info
    diagnostics["processor_count"] = ProcessInfo.processInfo.processorCount
    diagnostics["physical_memory_gb"] = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)

    // Locale info
    diagnostics["locale"] = Locale.current.identifier
    diagnostics["timezone"] = TimeZone.current.identifier

    return diagnostics
  }

  // MARK: - Conversation Events
  // Note: The event is named "Memory Created" in analytics for historical reasons,
  // but it actually tracks when a conversation/recording is created, not a "memory".

  func conversationCreated(
    conversationId: String,
    source: String,
    durationSeconds: Int? = nil,
    attemptId: String? = nil
  ) {
    if let attemptId {
      CaptureAttemptAcceptanceRegistry.noteAccepted(attemptId)
    }
    PostHogManager.shared.conversationCreated(
      conversationId: conversationId, source: source, durationSeconds: durationSeconds, attemptId: attemptId)
  }

  func memoryDeleted(conversationId: String) {
    PostHogManager.shared.memoryDeleted(conversationId: conversationId)
  }

  func memoryShareButtonClicked(conversationId: String) {
    PostHogManager.shared.memoryShareButtonClicked(conversationId: conversationId)
  }

  func shareAction(category: String, properties: [String: Any] = [:]) {
    var props = properties
    props["category"] = category
    PostHogManager.shared.track("Share Action", properties: props)
  }

  func memoryListItemClicked(conversationId: String) {
    PostHogManager.shared.memoryListItemClicked(conversationId: conversationId)
  }

  // MARK: - Chat Events

  func desktopRatingSubmitted(rating: Int, revision: Int? = nil) {
    PostHogManager.shared.desktopRatingSubmitted(rating: rating, revision: revision)
  }

  func desktopPromptShown(promptId: String, promptType: String) {
    PostHogManager.shared.track(
      "Desktop Prompt Shown", properties: ["prompt_id": promptId, "prompt_type": promptType])
  }

  func desktopPromptAnswered(promptId: String, promptType: String, value: String) {
    PostHogManager.shared.track(
      "Desktop Prompt Answered",
      properties: ["prompt_id": promptId, "prompt_type": promptType, "value": value])
  }

  func desktopPromptDismissed(promptId: String, promptType: String) {
    PostHogManager.shared.track(
      "Desktop Prompt Dismissed", properties: ["prompt_id": promptId, "prompt_type": promptType])
  }

  // MARK: - Settings Events

  func settingsPageOpened() {
    PostHogManager.shared.settingsPageOpened()
  }

  // MARK: - Page/Screen Views (PostHog specific, but tracked in both)

  func pageViewed(_ pageName: String) {
    PostHogManager.shared.pageViewed(pageName)
  }

  // MARK: - Account Events

  func deleteAccountClicked() {
    PostHogManager.shared.deleteAccountClicked()
  }

  func deleteAccountConfirmed() {
    PostHogManager.shared.deleteAccountConfirmed()
  }

  func deleteAccountCancelled() {
    PostHogManager.shared.deleteAccountCancelled()
  }

  // MARK: - Navigation Events

  func tabChanged(tabName: String) {
    PostHogManager.shared.tabChanged(tabName: tabName)
  }

  func conversationDetailOpened(conversationId: String) {
    PostHogManager.shared.conversationDetailOpened(conversationId: conversationId)
  }

  // MARK: - Chat Events (Additional)

  func chatAppSelected(appId: String?, appName: String?) {
    PostHogManager.shared.chatAppSelected(appId: appId, appName: appName)
  }

  func chatCleared() {
    PostHogManager.shared.chatCleared()
  }

  // MARK: - Claude Agent Events

  /// Sends a Chat-first event only after its closed, content-free mapper has
  /// produced the payload. Views must use this typed entry point instead of a
  /// generic PostHog event so rich controls cannot leak user text or IDs.
  func chatFirst(_ event: ChatFirstAnalyticsEvent) {
    let payload = event.analyticsPayload
    PostHogManager.shared.track(
      payload.eventName,
      properties: payload.properties.mapValues { $0 as Any }
    )
  }

  private func boundedAnalyticsIdentifier(_ value: String) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
  }

  // MARK: - Conversation Events (Additional)

  func conversationReprocessed(conversationId: String, appId: String) {
    PostHogManager.shared.conversationReprocessed(conversationId: conversationId, appId: appId)
  }

  func conversationReprocessedDefault(conversationId: String) {
    PostHogManager.shared.conversationReprocessedDefault(conversationId: conversationId)
  }

  // MARK: - Settings Events (Additional)

  func settingToggled(setting: String, enabled: Bool) {
    PostHogManager.shared.settingToggled(setting: setting, enabled: enabled)
  }

  func languageChanged(language: String) {
    PostHogManager.shared.languageChanged(language: language)
  }

  // MARK: - Launch At Login Events

  /// Track when launch at login state changes
  /// - Parameters:
  ///   - enabled: New state
  ///   - source: What triggered the change (user, migration, onboarding)
  func launchAtLoginChanged(enabled: Bool, source: String) {
    PostHogManager.shared.launchAtLoginChanged(enabled: enabled, source: source)
  }

  // MARK: - Feedback Events

  func feedbackOpened() {
    PostHogManager.shared.feedbackOpened()
  }

  func feedbackSubmitted(feedbackLength: Int) {
    PostHogManager.shared.feedbackSubmitted(feedbackLength: feedbackLength)
  }

  func desktopHealthEvent(name: String, properties: [String: Any]) {
    guard !Self.isDevBuild else { return }
    var props = properties
    props["health_event"] = name
    PostHogManager.shared.track("desktop_health_event", properties: props)
  }

  // MARK: - Rewind Events (Desktop-specific)

  func rewindSearchPerformed(queryLength: Int) {
    PostHogManager.shared.rewindSearchPerformed(queryLength: queryLength)
  }

  func rewindScreenshotViewed(timestamp: Date) {
    PostHogManager.shared.rewindScreenshotViewed(timestamp: timestamp)
  }

  func rewindTimelineNavigated(direction: String) {
    PostHogManager.shared.rewindTimelineNavigated(direction: direction)
  }

  // MARK: - Proactive Assistant Events (Desktop-specific)

  func taskExtracted(taskCount: Int) {
    PostHogManager.shared.taskExtracted(taskCount: taskCount)
  }

  func taskIntelligenceAttribution(_ event: TaskIntelligenceAttributionEvent) {
    PostHogManager.shared.taskIntelligenceAttribution(event)
  }

  func proactiveTaskGateEvaluated(_ trace: TaskInterruptionGateTrace) {
    PostHogManager.shared.proactiveTaskGateEvaluated(trace)
  }

  func taskPromoted(taskCount: Int) {
    PostHogManager.shared.taskPromoted(taskCount: taskCount)
  }

  func taskCompleted(source: String?) {
    PostHogManager.shared.taskCompleted(source: source)
  }

  func taskDeleted(source: String?) {
    PostHogManager.shared.taskDeleted(source: source)
  }

  func taskAdded() {
    PostHogManager.shared.taskAdded()
  }

  func memoryExtracted(memoryCount: Int) {
    captureMemoryAssistantTelemetryForTests("Memory Extracted", properties: ["memory_count": memoryCount])
    PostHogManager.shared.memoryExtracted(memoryCount: memoryCount)
  }

  // MARK: - Memory Assistant Telemetry

  /// Proactive MemoryAssistant setting change (the activation denominator). See
  /// `MemoryAssistantTelemetry.Setting`. Emitted only on a real persisted change.
  func memoryAssistantSettingChanged(setting: MemoryAssistantTelemetry.Setting, value: Bool) {
    captureMemoryAssistantTelemetryForTests(
      MemoryAssistantTelemetry.settingChangedEventName,
      properties: MemoryAssistantTelemetry.settingChangedPayload(setting: setting, value: value)
    )
    PostHogManager.shared.memoryAssistantSettingChanged(setting: setting, value: value)
  }

  /// Proactive MemoryAssistant analysis-outcome funnel. See
  /// `MemoryAssistantTelemetry.AnalysisOutcome`. One event per actual analysis
  /// attempt; supplements (does not alter) the `Memory Extracted` success terminal.
  func memoryAssistantAnalysisRun(
    outcome: MemoryAssistantTelemetry.AnalysisOutcome,
    confidence: Double? = nil
  ) {
    captureMemoryAssistantTelemetryForTests(
      MemoryAssistantTelemetry.analysisRunEventName,
      properties: MemoryAssistantTelemetry.analysisRunPayload(outcome: outcome, confidence: confidence)
    )
    PostHogManager.shared.memoryAssistantAnalysisRun(outcome: outcome, confidence: confidence)
  }

  // MARK: - Suggestion Assistant Telemetry

  func suggestionAssistantSettingChanged(setting: SuggestionAssistantTelemetry.Setting, value: Bool) {
    let payload = SuggestionAssistantTelemetry.settingChangedPayload(setting: setting, value: value)
    captureSuggestionAssistantTelemetryForTests(
      SuggestionAssistantTelemetry.settingChangedEventName,
      properties: payload
    )
    PostHogManager.shared.suggestionAssistantSettingChanged(setting: setting, value: value)
  }

  func suggestionAssistantGateOutcome(_ outcome: SuggestionAssistantTelemetry.GateOutcome) {
    guard outcome.emitsAnalytics else { return }
    let payload = SuggestionAssistantTelemetry.gateOutcomePayload(outcome)
    captureSuggestionAssistantTelemetryForTests(
      SuggestionAssistantTelemetry.gateOutcomeEventName,
      properties: payload
    )
    PostHogManager.shared.suggestionAssistantGateOutcome(outcome)
  }

  func suggestionAssistantEvaluationStarted(
    identity: SuggestionAssistantTelemetry.Identity,
    shape: SuggestionAssistantTelemetry.EvaluationShape
  ) {
    let payload = SuggestionAssistantTelemetry.evaluationStartedPayload(identity: identity, shape: shape)
    captureSuggestionAssistantTelemetryForTests(
      SuggestionAssistantTelemetry.evaluationStartedEventName,
      properties: payload
    )
    PostHogManager.shared.suggestionAssistantEvaluationStarted(identity: identity, shape: shape)
  }

  func suggestionAssistantEvaluationCompleted(
    identity: SuggestionAssistantTelemetry.Identity,
    shape: SuggestionAssistantTelemetry.EvaluationShape,
    latency: TimeInterval,
    producedSuggestion: Bool
  ) {
    let payload = SuggestionAssistantTelemetry.evaluationCompletedPayload(
      identity: identity,
      shape: shape,
      latency: latency,
      producedSuggestion: producedSuggestion
    )
    captureSuggestionAssistantTelemetryForTests(
      SuggestionAssistantTelemetry.evaluationCompletedEventName,
      properties: payload
    )
    PostHogManager.shared.suggestionAssistantEvaluationCompleted(
      identity: identity,
      shape: shape,
      latency: latency,
      producedSuggestion: producedSuggestion
    )
  }

  func suggestionAssistantEvaluationFailed(
    identity: SuggestionAssistantTelemetry.Identity,
    shape: SuggestionAssistantTelemetry.EvaluationShape,
    latency: TimeInterval,
    reason: SuggestionAssistantTelemetry.EvaluationFailureReason
  ) {
    let payload = SuggestionAssistantTelemetry.evaluationFailedPayload(
      identity: identity,
      shape: shape,
      latency: latency,
      reason: reason
    )
    captureSuggestionAssistantTelemetryForTests(
      SuggestionAssistantTelemetry.evaluationFailedEventName,
      properties: payload
    )
    PostHogManager.shared.suggestionAssistantEvaluationFailed(
      identity: identity,
      shape: shape,
      latency: latency,
      reason: reason
    )
  }

  func suggestionAssistantDeliveryOutcome(
    _ outcome: SuggestionAssistantTelemetry.DeliveryOutcome,
    identity: SuggestionAssistantTelemetry.NotificationIdentity
  ) {
    let payload = SuggestionAssistantTelemetry.deliveryOutcomePayload(outcome, identity: identity)
    captureSuggestionAssistantTelemetryForTests(
      SuggestionAssistantTelemetry.deliveryOutcomeEventName,
      properties: payload
    )
    PostHogManager.shared.suggestionAssistantDeliveryOutcome(outcome, identity: identity)
  }

  /// Record one terminal outcome for a generated Advice item. The bounded recent-ID window
  /// absorbs racing presentation callbacks without allowing process-lifetime growth.

  // MARK: - Apps Events

  func appEnabled(appId: String, appName: String) {
    PostHogManager.shared.appEnabled(appId: appId, appName: appName)
  }

  func appDisabled(appId: String, appName: String) {
    PostHogManager.shared.appDisabled(appId: appId, appName: appName)
  }

  func appDetailViewed(appId: String, appName: String) {
    PostHogManager.shared.appDetailViewed(appId: appId, appName: appName)
  }

  // MARK: - Update Events

  func updateAvailable(
    version: String,
    context: UpdateAnalyticsContext,
    item: UpdateItemAnalytics
  ) {
    PostHogManager.shared.updateAvailable(version: version, context: context, item: item)
  }

  func updateInstallStarted(attempt: UpdateInstallAttempt) {
    PostHogManager.shared.updateInstallStarted(attempt: attempt)
  }

  func updateInstalled(
    attempt: UpdateInstallAttempt,
    installedVersion: String,
    installedBuild: String
  ) {
    PostHogManager.shared.updateInstalled(
      attempt: attempt,
      installedVersion: installedVersion,
      installedBuild: installedBuild
    )
  }

  func updateInstallVerificationFailed(
    attempt: UpdateInstallAttempt,
    installedVersion: String,
    installedBuild: String
  ) {
    PostHogManager.shared.updateInstallVerificationFailed(
      attempt: attempt,
      installedVersion: installedVersion,
      installedBuild: installedBuild
    )
  }

  func updateCheckFailed(diagnostics: UpdateFailureDiagnostics) {
    PostHogManager.shared.updateCheckFailed(diagnostics: diagnostics)
  }

  // MARK: - Notification Events

  func notificationSent(
    notificationId: String,
    title: String,
    assistantId: String,
    surface: String,
    suggestionIdentity: SuggestionAssistantTelemetry.NotificationIdentity? = nil
  ) {
    if let suggestionIdentity {
      captureSuggestionAssistantTelemetryForTests(
        "Notification Sent",
        properties: SuggestionAssistantTelemetry.notificationPayload(suggestionIdentity)
      )
    }
    PostHogManager.shared.notificationSent(
      notificationId: notificationId,
      title: title,
      assistantId: assistantId,
      surface: surface,
      suggestionIdentity: suggestionIdentity
    )
  }

  func notificationClicked(
    notificationId: String,
    title: String,
    assistantId: String,
    surface: String,
    suggestionIdentity: SuggestionAssistantTelemetry.NotificationIdentity? = nil
  ) {
    if let suggestionIdentity {
      captureSuggestionAssistantTelemetryForTests(
        "Notification Clicked",
        properties: SuggestionAssistantTelemetry.notificationPayload(suggestionIdentity)
      )
    }
    PostHogManager.shared.notificationClicked(
      notificationId: notificationId,
      title: title,
      assistantId: assistantId,
      surface: surface,
      suggestionIdentity: suggestionIdentity
    )
  }

  func notificationDismissed(
    notificationId: String,
    title: String,
    assistantId: String,
    surface: String,
    dismissalKind: NotificationDismissalKind,
    suggestionIdentity: SuggestionAssistantTelemetry.NotificationIdentity? = nil
  ) {
    if let suggestionIdentity {
      var properties = SuggestionAssistantTelemetry.notificationPayload(suggestionIdentity)
      properties["dismissal_kind"] = dismissalKind.rawValue
      captureSuggestionAssistantTelemetryForTests(
        "Notification Dismissed",
        properties: properties
      )
    }
    PostHogManager.shared.notificationDismissed(
      notificationId: notificationId,
      title: title,
      assistantId: assistantId,
      surface: surface,
      dismissalKind: dismissalKind,
      suggestionIdentity: suggestionIdentity
    )
  }

  func notificationWillPresent(notificationId: String, title: String) {
    PostHogManager.shared.notificationWillPresent(notificationId: notificationId, title: title)
  }

  func notificationDelegateReady() {
    PostHogManager.shared.notificationDelegateReady()
  }

  // MARK: - Menu Bar Events

  /// Track when user opens the menu bar dropdown
  func menuBarOpened() {
    PostHogManager.shared.menuBarOpened()
  }

  /// Track when user clicks an action in the menu bar
  func menuBarActionClicked(action: String) {
    PostHogManager.shared.menuBarActionClicked(action: action)
  }

  // MARK: - Tier Events

  func tierChanged(tier: Int, reason: String) {
    PostHogManager.shared.tierChanged(tier: tier, reason: reason)
  }

  func chatBridgeModeChanged(from oldMode: String, to newMode: String) {
    PostHogManager.shared.chatBridgeModeChanged(from: oldMode, to: newMode)
  }

  // MARK: - Floating Bar Events

  // MARK: - Knowledge Graph Events

  /// Track when knowledge graph generation starts during onboarding
  func knowledgeGraphBuildStarted(filesIndexed: Int, hadExistingGraph: Bool) {
    let props: [String: Any] = [
      "files_indexed": filesIndexed,
      "had_existing_graph": hadExistingGraph,
    ]
    PostHogManager.shared.track("knowledge_graph_build_started", properties: props)
  }

  /// Track when knowledge graph generation completes (successfully loaded with data)
  func knowledgeGraphBuildCompleted(
    nodeCount: Int, edgeCount: Int, pollAttempts: Int, hadExistingGraph: Bool
  ) {
    let props: [String: Any] = [
      "node_count": nodeCount,
      "edge_count": edgeCount,
      "poll_attempts": pollAttempts,
      "had_existing_graph": hadExistingGraph,
    ]
    PostHogManager.shared.track("knowledge_graph_build_completed", properties: props)
  }

  /// Track when knowledge graph generation fails or times out empty
  func knowledgeGraphBuildFailed(reason: String, pollAttempts: Int, filesIndexed: Int) {
    let props: [String: Any] = [
      "reason": reason,
      "poll_attempts": pollAttempts,
      "files_indexed": filesIndexed,
    ]
    PostHogManager.shared.track("knowledge_graph_build_failed", properties: props)
  }

  // MARK: - Subscription funnel
  //
  // Same wire names as mobile. `Upgrade Succeeded` stays property-less because
  // that released registry id cannot gain properties; tier and interval are on
  // `Upgrade Succeeded Attributed`, emitted with it.

  func paywallOpened(source: String, currentPlan: String) {
    PostHogManager.shared.track(
      "Paywall Opened",
      properties: SubscriptionFunnelWire.paywallProperties(source: source, currentPlan: currentPlan))
  }

  func upgradePlanSelected(plan: String, billingInterval: String, source: String) {
    PostHogManager.shared.track(
      "Upgrade Plan Selected",
      properties: SubscriptionFunnelWire.planSelectedProperties(
        plan: plan, billingInterval: billingInterval, source: source))
  }

  func upgradeSucceeded(plan: String, billingInterval: String) {
    let properties = SubscriptionFunnelWire.upgradeSucceededProperties(plan: plan, billingInterval: billingInterval)
    PostHogManager.shared.track("Upgrade Succeeded Attributed", properties: properties)
    PostHogManager.shared.track("Upgrade Succeeded")
  }

  func upgradeCancelled() {
    PostHogManager.shared.track("Upgrade Cancelled")
  }

}

enum SubscriptionFunnelWire {
  static func plan(_ raw: String?) -> String {
    switch raw?.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "free":
      return "basic"
    case "pro":
      return "unknown"
    case "basic", "plus", "unlimited", "unlimited_v2", "operator", "architect", "unknown":
      return (raw ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
    default:
      return "unknown"
    }
  }

  static func interval(_ raw: String?) -> String {
    switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "month", "monthly":
      return "month"
    case "year", "yearly", "annual":
      return "year"
    default:
      return "unknown"
    }
  }

  static func source(_ raw: String) -> String {
    switch raw {
    case "chat_quota_exceeded", "freemium_switch", "locked_conversation", "locked_memory", "chat_apps",
      "usage_page", "transcription_settings", "unlimited_deeplink", "macos_billing", "macos_usage_limit",
      "macos_chat_quota_banner", "windows_billing", "windows_usage_limit", "web_plans",
      "macos_settings_view", "windows_settings_view", "unknown":
      return raw
    default:
      return "unknown"
    }
  }

  static func paywallProperties(source: String, currentPlan: String) -> [String: String] {
    [
      "source": self.source(source),
      "current_plan": plan(currentPlan),
    ]
  }

  static func planSelectedProperties(plan: String, billingInterval: String, source: String) -> [String: String] {
    [
      "plan": self.plan(plan),
      "billing_interval": interval(billingInterval),
      "source": self.source(source),
    ]
  }

  static func upgradeSucceededProperties(plan: String, billingInterval: String) -> [String: String] {
    [
      "plan": self.plan(plan),
      "billing_interval": interval(billingInterval),
    ]
  }
}
