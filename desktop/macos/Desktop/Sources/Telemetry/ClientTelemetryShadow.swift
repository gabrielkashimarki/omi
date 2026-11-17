import Foundation

/// Replacement observations for the frozen collector. PostHog emission stays at the
/// existing call sites; this type only adds the shadow copy when the transport flag is on.
enum ClientTelemetryShadow {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var recorder: ((ClientTelemetryObservation) -> Void)?
  nonisolated(unsafe) private static var dropRecorder: ((ClientTelemetryDropReason) -> Void)?

  static func resetForTests() {
    lock.lock()
    recorder = nil
    dropRecorder = nil
    lock.unlock()
  }

  static func setRecorderForTests(_ recorder: ((ClientTelemetryObservation) -> Void)?) {
    lock.lock()
    self.recorder = recorder
    lock.unlock()
  }

  static func setDropRecorderForTests(_ recorder: ((ClientTelemetryDropReason) -> Void)?) {
    lock.lock()
    dropRecorder = recorder
    lock.unlock()
  }

  static func captureScreenTaskTerminal(ownerID: String?, properties: [String: Any], occurredAt: Date = Date()) {
    guard ClientTelemetryFlags.transportShadowEnabled else { return }
    guard let channel = ClientTelemetryFlags.resolvedChannel() else { return }
    guard let ownerID, !ownerID.isEmpty else {
      noteDrop(.missingOwner)
      return
    }
    guard
      let observation = screenTaskObservation(
        ownerID: ownerID, properties: properties, occurredAt: occurredAt, channel: channel)
    else {
      noteDrop(.invalid)
      return
    }
    deliver(observation)
  }

  static func captureFallback(area: String, from: String, to: String, reason: String, outcome: String) {
    guard ClientTelemetryFlags.transportShadowEnabled else { return }
    guard let channel = ClientTelemetryFlags.resolvedChannel() else { return }
    guard let ownerID = ClientTelemetryIdentity.currentOwnerID(), !ownerID.isEmpty else {
      noteDrop(.missingOwner)
      return
    }
    let operationID = UUID()
    let attributes: [String: ClientTelemetryJSON] = [
      "area": .string(bounded(area, allowed: fallbackAreas, fallback: "other")),
      "from": .string(from),
      "operation_id": .string(operationID.uuidString.lowercased()),
      "outcome": .string(bounded(outcome, allowed: fallbackOutcomes, fallback: "degraded")),
      "reason": .string(reason),
      "to": .string(to),
    ]
    guard let observation = make(ownerID: ownerID, channel: channel, family: "fallback", attributes: attributes)
    else { return }
    deliver(observation)
  }

  static func screenTaskObservation(
    ownerID: String,
    properties: [String: Any],
    occurredAt: Date,
    channel: String,
    eventID: UUID = UUID(),
    operationID: UUID = UUID()
  ) -> ClientTelemetryObservation? {
    var attributes: [String: ClientTelemetryJSON] = [
      "operation_id": .string(operationID.uuidString.lowercased()),
      "schema_version": .int(2),
    ]
    for key in screenTaskStrings {
      attributes[key] = .string(screenTaskString(key, properties: properties))
    }
    for key in screenTaskInts {
      attributes[key] = .int(screenTaskInt(key, properties: properties))
    }
    for key in screenTaskBools {
      attributes[key] = .bool(screenTaskBool(key, properties: properties))
    }
    for key in screenTaskDurations {
      attributes[key] = .int(screenTaskDuration(key, properties: properties))
    }
    return make(
      ownerID: ownerID,
      channel: channel,
      family: "screen_task",
      attributes: attributes,
      occurredAt: occurredAt,
      eventID: eventID
    )
  }

  private static func deliver(_ observation: ClientTelemetryObservation) {
    lock.lock()
    let recorder = recorder
    lock.unlock()
    if let recorder {
      recorder(observation)
      return
    }
    Task { await ClientTelemetryTransport.shared.enqueue(observation) }
  }

  private static func noteDrop(_ reason: ClientTelemetryDropReason) {
    lock.lock()
    let recorder = dropRecorder
    lock.unlock()
    if let recorder {
      recorder(reason)
      return
    }
    Task { await ClientTelemetryTransport.shared.recordDrop(reason) }
  }

  private static func make(
    ownerID: String,
    channel: String,
    family: String,
    attributes: [String: ClientTelemetryJSON],
    occurredAt: Date = Date(),
    eventID: UUID = UUID()
  ) -> ClientTelemetryObservation? {
    guard channel == "production" || channel == "beta" else { return nil }
    guard families.contains(family) else { return nil }
    return ClientTelemetryObservation(
      eventID: eventID,
      occurredAt: occurredAt,
      platform: "macos",
      channel: channel,
      family: family,
      attributes: attributes,
      ownerID: ownerID,
      enqueuedAt: occurredAt,
      attemptCount: 0
    )
  }

  private static func bounded(_ value: String, allowed: Set<String>, fallback: String = "unknown") -> String {
    allowed.contains(value) ? value : fallback
  }

  private static func screenTaskString(_ key: String, properties: [String: Any]) -> String {
    let raw = properties[key] as? String ?? "unknown"
    let allowed = screenTaskStringSets[key] ?? ["unknown"]
    return allowed.contains(raw) ? raw : "unknown"
  }

  private static func screenTaskInt(_ key: String, properties: [String: Any]) -> Int {
    let value = properties[key]
    let number: Int
    if let int = value as? Int {
      number = int
    } else if let double = value as? Double {
      number = Int(double.rounded())
    } else if let ns = value as? NSNumber, CFGetTypeID(ns) != CFBooleanGetTypeID() {
      number = ns.intValue
    } else {
      number = 0
    }
    return max(0, number)
  }

  private static func screenTaskBool(_ key: String, properties: [String: Any]) -> Bool {
    let value = properties[key]
    if let bool = value as? Bool { return bool }
    if let ns = value as? NSNumber, CFGetTypeID(ns) == CFBooleanGetTypeID() { return ns.boolValue }
    return false
  }

  private static func screenTaskDuration(_ key: String, properties: [String: Any]) -> Int {
    let raw = properties[key] as? Double ?? (properties[key] as? NSNumber)?.doubleValue ?? 0
    guard raw.isFinite else { return 0 }
    return min(max(Int(raw.rounded()), 0), 86_400_000)
  }

  private static let families: Set<String> = ["screen_task", "fallback"]
  private static let fallbackAreas: Set<String> = [
    "realtime_hub", "ptt_cascade", "screen_task_gate", "screen_task_extraction", "other",
  ]
  private static let fallbackOutcomes: Set<String> = ["recovered", "degraded", "exhausted"]
  private static let screenTaskStrings = [
    "pipeline", "gate_outcome", "extractor", "outcome", "error_class", "fallback_reason",
  ]
  private static let screenTaskInts = [
    "eligible_frames", "invalid_items", "gate_attempts", "extraction_attempts", "legacy_attempts",
    "policy_rejected", "outbox_saved", "coalesced", "pending_delivered", "failed",
  ]
  private static let screenTaskBools = ["audit_sample", "feature_enabled_at_start", "client_bypass"]
  private static let screenTaskDurations = [
    "ocr_ms", "retrieval_ms", "gate_ms", "extraction_ms", "delivery_ms", "capture_to_terminal_ms",
  ]
  private static let screenTaskStringSets: [String: Set<String>] = [
    "pipeline": ["screen_task_v2", "legacy", "unknown"],
    "gate_outcome": ["none", "passed", "rejected", "fail_open", "unknown"],
    "extractor": ["gemini_3_8", "legacy", "none", "unknown"],
    "outcome": ["completed", "failed", "refused", "disabled", "dedupe_skipped", "gate_rejected", "unknown"],
    "error_class": [
      "none", "legacy_task_reservation_inactive", "auth", "plan_or_quota", "backpressure", "http_terminal",
      "owner_revoked", "privacy_revoked", "cancelled", "delivery_failure", "stopped", "gate_budget_cooldown",
      "invalid_response", "provider_outage", "provider_5xx", "admission_denied", "local_failure", "unknown",
      "timeout", "offline",
    ],
    "fallback_reason": [
      "none", "ocr_unusable", "gate_invalid_response", "provider_5xx", "timeout", "offline", "dispatch_disabled",
      "unknown",
    ],
  ]
}
