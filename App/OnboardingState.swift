import Foundation

/// How strongly the app should enforce breaks.
enum EnforcementStyle: String, CaseIterable {
    case gentle
    case firm
}

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
    static let enforcementStyle = "lingerly.onboarding.enforcementStyle"
    static let allowLockScreen = "lingerly.onboarding.allowLockScreen"
    static let fullscreenBehavior = "lingerly.onboarding.fullscreenBehavior"
    static let preset = "lingerly.onboarding.preset"
}
