import Foundation

/// Persists break statistics and streak metadata in UserDefaults.
final class StatsStore {
    private let defaults: UserDefaults

    private enum Keys {
        static let completedBreaks = "lingerly.stats.completedBreaks"
        static let totalBreakSeconds = "lingerly.stats.totalBreakSeconds"
        static let skips = "lingerly.stats.skips"
        static let snoozes = "lingerly.stats.snoozes"
        static let currentStreak = "lingerly.stats.streak.current"
        static let bestStreak = "lingerly.stats.streak.best"
        static let lastBreakDay = "lingerly.stats.streak.lastBreakDay"
    }

    /// Creates a stats store backed by the provided defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var completedBreaks: Int { defaults.integer(forKey: Keys.completedBreaks) }
    var totalBreakSeconds: Int { defaults.integer(forKey: Keys.totalBreakSeconds) }
    var skips: Int { defaults.integer(forKey: Keys.skips) }
    var snoozes: Int { defaults.integer(forKey: Keys.snoozes) }
    var currentStreak: Int { defaults.integer(forKey: Keys.currentStreak) }
    var bestStreak: Int { defaults.integer(forKey: Keys.bestStreak) }
    var lastBreakDay: String { defaults.string(forKey: Keys.lastBreakDay) ?? "" }

    /// Records a completed break and updates streak counters.
    func recordBreakCompleted(durationSeconds: Int, date: Date = Date()) {
        defaults.set(completedBreaks + 1, forKey: Keys.completedBreaks)
        defaults.set(totalBreakSeconds + max(durationSeconds, 0), forKey: Keys.totalBreakSeconds)
        updateStreak(for: date)
    }

    /// Records a skipped break.
    func recordSkip() {
        defaults.set(skips + 1, forKey: Keys.skips)
    }

    /// Records a snooze action.
    func recordSnooze() {
        defaults.set(snoozes + 1, forKey: Keys.snoozes)
    }

    /// Updates streak counters based on the provided date.
    private func updateStreak(for date: Date) {
        let calendar = Calendar.current
        let dayString = Self.dayKey(from: date, calendar: calendar)
        let previousDay = lastBreakDay

        if previousDay.isEmpty {
            defaults.set(1, forKey: Keys.currentStreak)
        } else if previousDay == dayString {
            // Same day: no change to streak.
        } else if let previousDate = Self.dateFromDayKey(previousDay, calendar: calendar) {
            let dayDiff = calendar.dateComponents([.day], from: previousDate, to: date).day ?? 0
            if dayDiff == 1 {
                defaults.set(currentStreak + 1, forKey: Keys.currentStreak)
            } else {
                defaults.set(1, forKey: Keys.currentStreak)
            }
        } else {
            defaults.set(1, forKey: Keys.currentStreak)
        }

        let updatedCurrent = defaults.integer(forKey: Keys.currentStreak)
        if updatedCurrent > bestStreak {
            defaults.set(updatedCurrent, forKey: Keys.bestStreak)
        }

        defaults.set(dayString, forKey: Keys.lastBreakDay)
    }

    /// Formats a date into a stable YYYY-MM-DD key.
    private static func dayKey(from date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// Parses a YYYY-MM-DD key into a Date.
    private static func dateFromDayKey(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
