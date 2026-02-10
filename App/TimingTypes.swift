import Foundation

/// Represents a clock time used for scheduled break reminders.
struct ScheduleTime: Hashable {
    let hour: Int
    let minute: Int

    /// Creates a time if the hour/minute are within valid ranges.
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

    /// Formats the time as a `HH:mm` string.
    var stringValue: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// Selected timing modes that can be combined together.
struct TimingModes: OptionSet {
    let rawValue: Int

    static let interval = TimingModes(rawValue: 1 << 0)
    static let activeTime = TimingModes(rawValue: 1 << 1)
    static let schedule = TimingModes(rawValue: 1 << 2)
}

/// What to do when an automatic smart-pause condition ends.
enum SmartPauseResumeBehavior: String, CaseIterable {
    case resumeTimer
    case resetTimer
    case countDownDuringPause
}

/// App bundle rule used for "pause while this app is open".
struct PauseAppRule: Codable, Hashable, Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let bundlePath: String?

    var id: String { bundleIdentifier.lowercased() }
}

/// Preset configuration for interval and break duration.
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
