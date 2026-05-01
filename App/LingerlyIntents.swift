import AppIntents
import AppKit

private enum LingerlyIntentError: LocalizedError {
    case appUnavailable

    var errorDescription: String? {
        switch self {
        case .appUnavailable:
            return String(localized: "IntentsUnavailableText")
        }
    }
}

struct PauseTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Timer"
    static let description = IntentDescription("Pauses Lingerly's timer without resetting your progress.")
    static let openAppWhenRun = true

    @MainActor
    /// Pauses the running timer while preserving elapsed progress.
    func perform() throws -> some IntentResult {
        guard let appState = (NSApp.delegate as? AppDelegate)?.appState else {
            throw LingerlyIntentError.appUnavailable
        }
        appState.pauseTimer()
        return .result()
    }
}

struct ResumeTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Timer"
    static let description = IntentDescription("Resumes a paused Lingerly timer.")
    static let openAppWhenRun = true

    @MainActor
    /// Resumes the timer if it is currently paused.
    func perform() throws -> some IntentResult {
        guard let appState = (NSApp.delegate as? AppDelegate)?.appState else {
            throw LingerlyIntentError.appUnavailable
        }
        appState.resumeTimer()
        return .result()
    }
}

struct SkipBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Break"
    static let description = IntentDescription("Skips the current or pending break.")
    static let openAppWhenRun = true

    @MainActor
    /// Skips the current break prompt/session.
    func perform() throws -> some IntentResult {
        guard let appState = (NSApp.delegate as? AppDelegate)?.appState else {
            throw LingerlyIntentError.appUnavailable
        }
        appState.skipBreak()
        return .result()
    }
}

struct SnoozeBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Snooze Break"
    static let description = IntentDescription("Snoozes the next break using your default duration.")
    static let openAppWhenRun = true

    @MainActor
    /// Snoozes using the default duration configured in settings.
    func perform() throws -> some IntentResult {
        guard let appState = (NSApp.delegate as? AppDelegate)?.appState else {
            throw LingerlyIntentError.appUnavailable
        }
        appState.snoozeDefault()
        return .result()
    }
}

struct ResetTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "ActionRestartTimerButton"
    static let description = IntentDescription("Resets the current timer cycle.")
    static let openAppWhenRun = true

    @MainActor
    /// Resets the current cycle counters without changing app configuration.
    func perform() throws -> some IntentResult {
        guard let appState = (NSApp.delegate as? AppDelegate)?.appState else {
            throw LingerlyIntentError.appUnavailable
        }
        appState.resetTimer()
        return .result()
    }
}

struct LingerlyShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseTimerIntent(),
            phrases: [
                "Pause \\(.applicationName) timer",
                "Pause \\(.applicationName)"
            ],
            shortTitle: "Pause Timer",
            systemImageName: "pause.circle.fill"
        )
        AppShortcut(
            intent: ResumeTimerIntent(),
            phrases: [
                "Resume \\(.applicationName) timer",
                "Resume \\(.applicationName)"
            ],
            shortTitle: "Resume Timer",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: SkipBreakIntent(),
            phrases: [
                "Skip break in \\(.applicationName)",
                "Skip \\(.applicationName) break"
            ],
            shortTitle: "Skip Break",
            systemImageName: "forward.end.circle.fill"
        )
        AppShortcut(
            intent: SnoozeBreakIntent(),
            phrases: [
                "Snooze \\(.applicationName) break",
                "Snooze break in \\(.applicationName)"
            ],
            shortTitle: "Snooze Break",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: ResetTimerIntent(),
            phrases: [
                "Reset \\(.applicationName) timer",
                "Reset timer in \\(.applicationName)"
            ],
            shortTitle: "ActionRestartTimerButton",
            systemImageName: "arrow.counterclockwise.circle.fill"
        )
    }
}
