import Foundation

/// Whether to notify or interrupt when a fullscreen app is active.
enum FullscreenBehavior: String, CaseIterable {
    case notify
    case interrupt
}

/// Preset identifiers used during onboarding.
enum ReminderPreset: String, CaseIterable {
    case twentyTwentyTwenty
    case fortyFiveFifteen
}

/// UserDefaults keys for onboarding choices.
enum OnboardingKeys {
    static let completed = "lingerly.onboarding.completed"
    static let allowLockScreen = "lingerly.onboarding.allowLockScreen"
    static let fullscreenBehavior = "lingerly.onboarding.fullscreenBehavior"
    static let alwaysNotificationOnly = "lingerly.onboarding.alwaysNotificationOnly"
    static let preset = "lingerly.onboarding.preset"
}
