import Foundation

/// Data do dia para prompts dos assistentes proativos.
enum PromptCalendarDay {

  /// Shared formatter for calendar-day grounding (see `current`).
  private static let calendarDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd (EEEE)"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    return f
  }()

  /// Calendar-day grounding for agents that judge dates, deadlines, or recency but
  /// not clock time: "2026-08-25 (Tuesday)".
  ///
  /// Date-only by contract: the string is stable within a local day, so it can ride in
  /// a prompt without busting it per call — and it still belongs in the uncached user
  /// turn, never in a cached system prefix. Without a year the model falls back to its
  /// training-cutoff year and flags correctly recorded current-era dates as mistakes.
  static func current(at date: Date = Date(), timeZone: TimeZone = .current) -> String {
    if timeZone == .current {
      return calendarDayFormatter.string(from: date)
    }
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd (EEEE)"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = timeZone
    return f.string(from: date)
  }
}
