import Foundation

enum ProactiveNotificationKind: String, Equatable, CaseIterable {
  /// **Decode-only.** Historical rows were journaled under a bare
  /// `notification:<uuid>` key, which reads back as this. No producer may pass
  /// it: `showNotification` requires an explicit kind, and a card with no
  /// category of its own is `.functional`, not "Notification".
  case general
  /// A system notice that is not a proactive observation — screen-recording
  /// reset, a support reply, an onboarding test ping. It is ungated by the five
  /// category toggles, exactly as `.general` was.
  case functional
  /// Trial/plan messaging. Never journaled: it is product copy about billing,
  /// not something Omi observed.
  case trial
  /// First-run permission help. Never journaled, for the same reason.
  case onboarding
  /// The daily recap's once-a-day announcement. Never journaled: the recap's
  /// transcript presence is the dedicated `ChatDailyRecapRow` day boundary, and
  /// INV-CHAT-1 makes the recap chrome rather than a turn — a journaled bell
  /// card would be a second, degraded copy (title truncated, no day stats) of
  /// a row the transcript already renders.
  case dailyRecap = "daily_recap"
  /// Feed-backed v2 cards open their source; the feed owns their history.
  case proactivityV2 = "proactivity_v2"
  case suggestion
  case insight
  case task
  case memory
  case goal
  case meetingNotes = "meeting_notes"
  case resurface
  case integration

  static func from(decisionType: String) -> Self {
    switch decisionType {
    // Director "suggest" decisions are generic tips, which the user-facing taxonomy
    // files under Insight; `.suggestion` is reserved for the focus-nudge assistant.
    case "suggest": return .insight
    // Retained focus-nudge decisions keep their historical suggestion badge and
    // Settings toggle when displayed from existing records.
    case "focus_nudge": return .suggestion
    case "insight": return .insight
    case "task_candidate": return .task
    case "resurface": return .resurface
    // An unrecognised director decision is a system notice, not an
    // uncategorised observation: `.general` is decode-only.
    default: return .functional
    }
  }

  static func from(assistantId: String) -> Self {
    switch assistantId {
    case "suggestion": return .suggestion
    case "insight": return .insight
    case "task", "context_reminder": return .task
    case "memory-extraction": return .memory
    case "goals": return .goal
    case "meeting-notes": return .meetingNotes
    case "integration_connect": return .integration
    case "trial": return .trial
    case "onboarding": return .onboarding
    case "daily_recap": return .dailyRecap
    case "proactivity_v2": return .proactivityV2
    default: return .functional
    }
  }

  /// Kinds whose cards are presentation only and must never enter the chat
  /// journal.
  var isJournaled: Bool {
    switch self {
    case .trial, .onboarding, .dailyRecap, .proactivityV2: return false
    case .general, .functional, .suggestion, .insight, .task, .memory, .goal, .meetingNotes,
      .resurface, .integration:
      return true
    }
  }
}
