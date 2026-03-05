import Foundation

/// Clock time used for schedule-mode break reminders.
struct ScheduleTime: Hashable {
    let hour: Int
    let minute: Int

    /// Creates a time when hour/minute are within valid bounds.
    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses a time from a `HH:mm` string.
    init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        self.init(hour: hour, minute: minute)
    }

    /// Returns the `HH:mm` representation.
    var stringValue: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// Marks whether a smart-pause period is active-time or inactive-time.
enum SmartPauseScheduleMode: String, Codable, CaseIterable {
    case active
    case inactive
}

/// Daily time range used by smart-pause schedule logic.
struct SmartPauseSchedulePeriod: Codable, Hashable, Identifiable {
    let id: UUID
    var mode: SmartPauseScheduleMode
    var startMinute: Int
    var endMinute: Int
    /// 1...7 in Calendar weekday order (1 = Sunday).
    var weekdays: Set<Int>

    /// Creates a schedule period with clamped minutes and valid weekdays.
    init(
        id: UUID = UUID(),
        mode: SmartPauseScheduleMode,
        startMinute: Int,
        endMinute: Int,
        weekdays: Set<Int>
    ) {
        self.id = id
        self.mode = mode
        self.startMinute = Self.clampMinute(startMinute)
        self.endMinute = Self.clampMinute(endMinute)
        self.weekdays = Set(weekdays.filter { (1...7).contains($0) })
    }

    /// Clamps minute-of-day values into the valid 00:00...23:59 range.
    static func clampMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 1_439)
    }

    /// Returns `true` when this period applies at the given date.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        guard !weekdays.isEmpty else { return false }
        if startMinute == endMinute {
            return weekdays.contains(weekday)
        }
        if startMinute < endMinute {
            guard weekdays.contains(weekday) else { return false }
            return minute >= startMinute && minute < endMinute
        }

        // Overnight window (e.g. 22:00-06:00): after midnight belongs to previous day.
        if minute >= startMinute {
            return weekdays.contains(weekday)
        }
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
        let previousWeekday = calendar.component(.weekday, from: previousDay)
        return weekdays.contains(previousWeekday)
    }
}

/// Timing mode bit flags that can be combined.
struct TimingModes: OptionSet {
    let rawValue: Int

    static let interval = TimingModes(rawValue: 1 << 0)
    static let activeTime = TimingModes(rawValue: 1 << 1)
    static let schedule = TimingModes(rawValue: 1 << 2)
}

/// Behavior to apply when smart pause ends.
enum SmartPauseResumeBehavior: String, CaseIterable {
    case resumeTimer
    case resetTimer
    case countDownDuringPause
}

/// App rule used by pause-while-app-open logic.
struct PauseAppRule: Codable, Hashable, Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let bundlePath: String?

    var id: String { bundleIdentifier.lowercased() }
}

/// Built-in preset values for interval and break duration.
struct TimingPreset: Identifiable {
    let id: String
    let intervalMinutes: Int
    let breakDurationSeconds: Int
}

/// Collection of built-in timing presets.
enum TimingPresets {
    static let all: [TimingPreset] = [
        TimingPreset(id: "20-20-20", intervalMinutes: 20, breakDurationSeconds: 20),
        TimingPreset(id: "45-15", intervalMinutes: 45, breakDurationSeconds: 900)
    ]

    /// Finds a preset by id.
    static func preset(for id: String) -> TimingPreset? {
        all.first { $0.id == id }
    }
}
