import Foundation

/// Why a user gave a thumbs-down.
///
/// The raw values match the backend `FeedbackReason` enum. The first five are
/// the reasons the mobile client has always sent, so desktop and mobile chat
/// feedback land in the same buckets in the daily report. The remaining five
/// are desktop-only, for proactive-notification cards (focus/insight/task/
/// memory) — a distinct taxonomy from a chat answer's, kept separate rather
/// than folded into the mobile five so neither set is diluted by the other's.
/// Adding a case here without adding it to `backend/models/feedback.py` will
/// be rejected by the API as invalid.
enum ChatFeedbackReason: String, CaseIterable, Identifiable, Sendable {
  case incorrectOrHallucination = "incorrect_or_hallucination"
  case notHelpfulOrIrrelevant = "not_helpful_or_irrelevant"
  case didntFollowInstructions = "didnt_follow_instructions"
  case tooVerbose = "too_verbose"
  case other = "other"

  case notAboutMe = "not_about_me"
  case alreadyDone = "already_done"
  case wrongFacts = "wrong_facts"
  case badTiming = "bad_timing"
  case notUseful = "not_useful"

  var id: String { rawValue }

  /// Short label for the inline picker. Kept to two or three words so the
  /// whole picker fits under a chat bubble without wrapping.
  var label: String {
    switch self {
    case .incorrectOrHallucination: return "Incorreta"
    case .notHelpfulOrIrrelevant: return "Não ajudou"
    case .didntFollowInstructions: return "Ignorou instruções"
    case .tooVerbose: return "Longa demais"
    case .other: return "Outro"
    case .notAboutMe: return "Não é sobre mim"
    case .alreadyDone: return "Já feito"
    case .wrongFacts: return "Fatos errados"
    case .badTiming: return "Hora ruim"
    case .notUseful: return "Não é útil"
    }
  }

  /// Hover help, spelling out the distinction the short label compresses.
  var help: String {
    switch self {
    case .incorrectOrHallucination: return "A resposta continha informações erradas ou inventadas"
    case .notHelpfulOrIrrelevant: return "A resposta não tratou do que eu perguntei"
    case .didntFollowInstructions: return "A resposta ignorou instruções que eu dei"
    case .tooVerbose: return "A resposta foi mais longa ou prolixa do que precisava"
    case .other: return "Outra coisa"
    case .notAboutMe: return "Esta notificação não era relevante para mim"
    case .alreadyDone: return "Eu já resolvi isso"
    case .wrongFacts: return "Esta notificação errou os fatos"
    case .badTiming: return "Isso apareceu na hora errada"
    case .notUseful: return "Isso não me ajudou"
    }
  }

  /// Five surface-appropriate chips. Notification rows use the taxonomy that
  /// classified 45 of 80 thumbs-downs; chat/voice rows use the mobile five so
  /// the daily report keeps comparing the same buckets across platforms.
  static func chips(isProactiveNotification: Bool) -> [ChatFeedbackReason] {
    if isProactiveNotification {
      return [.notAboutMe, .alreadyDone, .wrongFacts, .badTiming, .notUseful]
    }
    return [.incorrectOrHallucination, .notHelpfulOrIrrelevant, .didntFollowInstructions, .tooVerbose, .other]
  }

  /// Only ever consulted for a proactive-notification rating (guarded by the
  /// caller), so the mobile-answer cases below are never actually reached —
  /// still handled explicitly so the switch stays exhaustive.
}
