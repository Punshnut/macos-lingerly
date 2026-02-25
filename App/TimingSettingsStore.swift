import Foundation

/// UserDefaults keys for timing configuration and reminders.
enum TimingSettingsKeys {
    static let intervalMinutes = "lingerly.reminderIntervalMinutes"
    static let breakDurationSeconds = "lingerly.breakDurationSeconds"
    static let modeIntervalEnabled = "lingerly.timing.mode.interval"
    static let modeActiveEnabled = "lingerly.timing.mode.active"
    static let modeScheduleEnabled = "lingerly.timing.mode.schedule"
    static let scheduleTimes = "lingerly.timing.schedule.times"
    static let presetId = "lingerly.timing.preset.id"
    static let waterReminderEnabled = "lingerly.reminder.water.enabled"
    static let freshAirReminderEnabled = "lingerly.reminder.freshAir.enabled"
    static let standUpReminderEnabled = "lingerly.reminder.standUp.enabled"
    static let workoutReminderEnabled = "lingerly.reminder.workout.enabled"
    static let snoozeMinutes = "lingerly.snooze.duration.minutes"
    static let mediaPauseEnabled = "lingerly.media.pause.enabled"
    static let mediaResetOnResume = "lingerly.media.reset.on.resume"
    static let smartPauseResumeBehavior = "lingerly.smart.pause.resume.behavior"
    static let smartPauseCooldownMinutes = "lingerly.smart.pause.cooldown.minutes"
    static let smartPauseScheduleEnabled = "lingerly.smart.pause.schedule.enabled"
    static let smartPauseSchedulePeriods = "lingerly.smart.pause.schedule.periods"
    static let pauseForAppsEnabled = "lingerly.smart.pause.apps.enabled"
    static let pauseForAppsRules = "lingerly.smart.pause.apps.rules"
    static let resetOnUnlock = "lingerly.timer.reset.on.unlock"
    static let menuBarTimerEnabled = "lingerly.menu.timer.enabled"
    static let mutedModeEnabled = "lingerly.mode.muted.enabled"
    static let overlayStyle = "lingerly.overlay.style"
    static let hotkeyStartStop = "lingerly.hotkey.startStop"
    static let hotkeyResetTimer = "lingerly.hotkey.resetTimer"
    static let hotkeyLingerALittle = "lingerly.hotkey.lingerALittle"
    static let hotkeySnoozePrompt = "lingerly.hotkey.snoozePrompt"
}

/// Thin wrapper around UserDefaults for timing configuration.
final class TimingSettingsStore {
    private let defaults: UserDefaults

    /// Creates a settings store backed by the provided defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Interval minutes for break reminders.
    var intervalMinutes: Int {
        get { value(forKey: TimingSettingsKeys.intervalMinutes, defaultValue: 20) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.intervalMinutes) }
    }

    /// Break duration in seconds.
    var breakDurationSeconds: Int {
        get { value(forKey: TimingSettingsKeys.breakDurationSeconds, defaultValue: 20) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.breakDurationSeconds) }
    }

    /// Whether the interval timer mode is enabled.
    var modeIntervalEnabled: Bool {
        get { bool(forKey: TimingSettingsKeys.modeIntervalEnabled, defaultValue: false) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.modeIntervalEnabled) }
    }

    /// Whether active-time mode is enabled.
    var modeActiveEnabled: Bool {
        get { bool(forKey: TimingSettingsKeys.modeActiveEnabled, defaultValue: true) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.modeActiveEnabled) }
    }

    /// Whether schedule-based reminders are enabled.
    var modeScheduleEnabled: Bool {
        get { bool(forKey: TimingSettingsKeys.modeScheduleEnabled, defaultValue: false) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.modeScheduleEnabled) }
    }

    /// Whether timing pauses while media is playing.
    var mediaPauseEnabled: Bool {
        get { bool(forKey: TimingSettingsKeys.mediaPauseEnabled, defaultValue: false) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.mediaPauseEnabled) }
    }

    /// Whether the timer resets when media playback ends.
    var mediaResetOnResume: Bool {
        get { bool(forKey: TimingSettingsKeys.mediaResetOnResume, defaultValue: false) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.mediaResetOnResume) }
    }

    /// Behavior used after a smart pause ends.
    var smartPauseResumeBehavior: SmartPauseResumeBehavior {
        get {
            if let raw = defaults.string(forKey: TimingSettingsKeys.smartPauseResumeBehavior),
               let behavior = SmartPauseResumeBehavior(rawValue: raw) {
                if behavior == .countDownDuringPause {
                    defaults.set(SmartPauseResumeBehavior.resumeTimer.rawValue, forKey: TimingSettingsKeys.smartPauseResumeBehavior)
                    return .resumeTimer
                }
                return behavior
            }
            // Migration from the old boolean media-reset setting.
            return mediaResetOnResume ? .resetTimer : .resumeTimer
        }
        set { defaults.set(newValue.rawValue, forKey: TimingSettingsKeys.smartPauseResumeBehavior) }
    }

    /// Cooldown before smart pause resumes after a condition ends.
    var smartPauseCooldownMinutes: Int {
        get { value(forKey: TimingSettingsKeys.smartPauseCooldownMinutes, defaultValue: 1) }
        set { defaults.set(max(1, min(newValue, 5)), forKey: TimingSettingsKeys.smartPauseCooldownMinutes) }
    }

    /// Whether schedule-based smart pause is enabled.
    var smartPauseScheduleEnabled: Bool {
        get { bool(forKey: TimingSettingsKeys.smartPauseScheduleEnabled, defaultValue: false) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.smartPauseScheduleEnabled) }
    }

    /// Daily schedule periods that control smart pause.
    var smartPauseSchedulePeriods: [SmartPauseSchedulePeriod] {
        get {
            guard let data = defaults.data(forKey: TimingSettingsKeys.smartPauseSchedulePeriods) else { return [] }
            return (try? JSONDecoder().decode([SmartPauseSchedulePeriod].self, from: data)) ?? []
        }
        set {
            let encoded = try? JSONEncoder().encode(newValue)
            defaults.set(encoded, forKey: TimingSettingsKeys.smartPauseSchedulePeriods)
        }
    }

    /// Whether app-based smart pause is enabled.
    var pauseForAppsEnabled: Bool {
        get { bool(forKey: TimingSettingsKeys.pauseForAppsEnabled, defaultValue: false) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.pauseForAppsEnabled) }
    }

    /// App bundle ids that trigger smart pause while running.
    var pauseForAppsRules: [PauseAppRule] {
        get {
            guard let data = defaults.data(forKey: TimingSettingsKeys.pauseForAppsRules) else { return [] }
            return (try? JSONDecoder().decode([PauseAppRule].self, from: data)) ?? []
        }
        set {
            let encoded = try? JSONEncoder().encode(newValue)
            defaults.set(encoded, forKey: TimingSettingsKeys.pauseForAppsRules)
        }
    }

    /// Whether the timer resets when the user unlocks the Mac.
    var resetOnUnlock: Bool {
        get { bool(forKey: TimingSettingsKeys.resetOnUnlock, defaultValue: false) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.resetOnUnlock) }
    }

    /// Whether to show the countdown in the menu bar title.
    var menuBarTimerEnabled: Bool {
        get { bool(forKey: TimingSettingsKeys.menuBarTimerEnabled, defaultValue: false) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.menuBarTimerEnabled) }
    }

    /// Whether muted mode suppresses break overlays and notifications.
    var mutedModeEnabled: Bool {
        get { bool(forKey: TimingSettingsKeys.mutedModeEnabled, defaultValue: false) }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.mutedModeEnabled) }
    }

    /// Times of day to trigger scheduled breaks.
    var scheduleTimes: [ScheduleTime] {
        get {
            let raw = defaults.stringArray(forKey: TimingSettingsKeys.scheduleTimes) ?? []
            return raw.compactMap { ScheduleTime(string: $0) }
        }
        set {
            defaults.set(newValue.map { $0.stringValue }, forKey: TimingSettingsKeys.scheduleTimes)
        }
    }

    /// Currently selected preset id.
    var presetId: String {
        get { defaults.string(forKey: TimingSettingsKeys.presetId) ?? "20-20-20" }
        set { defaults.set(newValue, forKey: TimingSettingsKeys.presetId) }
    }

    /// Produces the combined timing modes for the current settings.
    func timingModes() -> TimingModes {
        var modes: TimingModes = []
        if modeIntervalEnabled { modes.insert(.interval) }
        if modeActiveEnabled { modes.insert(.activeTime) }
        if modeScheduleEnabled { modes.insert(.schedule) }
        return modes
    }

    /// Applies a preset and updates user defaults.
    func applyPreset(_ preset: TimingPreset) {
        intervalMinutes = preset.intervalMinutes
        breakDurationSeconds = preset.breakDurationSeconds
        presetId = preset.id
    }

    /// Reads an integer with a fallback when no value exists.
    private func value(forKey key: String, defaultValue: Int) -> Int {
        if defaults.object(forKey: key) == nil { return defaultValue }
        return defaults.integer(forKey: key)
    }

    /// Reads a boolean with a fallback when no value exists.
    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if defaults.object(forKey: key) == nil { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
