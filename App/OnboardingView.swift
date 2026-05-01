import SwiftUI

/// Guided onboarding flow for first launch configuration.
struct OnboardingView: View {
    @State private var step = 0
    @AppStorage(OnboardingKeys.completed) private var completed = false
    @AppStorage(OnboardingKeys.allowLockScreen) private var allowLockScreen = false
    @AppStorage(OnboardingKeys.fullscreenBehavior) private var fullscreenBehaviorRaw = FullscreenBehavior.notify.rawValue
    @AppStorage(OnboardingKeys.alwaysNotificationOnly) private var alwaysNotificationOnly = false
    @AppStorage(OnboardingKeys.preset) private var presetRaw = ReminderPreset.twentyTwentyTwenty.rawValue
    @AppStorage(TimingSettingsKeys.intervalMinutes) private var intervalMinutes = 20
    @AppStorage(TimingSettingsKeys.breakDurationSeconds) private var breakDurationSeconds = 20
    @AppStorage(TimingSettingsKeys.modeIntervalEnabled) private var modeIntervalEnabled = false
    @AppStorage(TimingSettingsKeys.modeActiveEnabled) private var modeActiveEnabled = true
    @AppStorage(TimingSettingsKeys.modeScheduleEnabled) private var modeScheduleEnabled = false
    @AppStorage(TimingSettingsKeys.presetId) private var presetId = "20-20-20"

    let onComplete: () -> Void

    private var fullscreenBehavior: FullscreenBehavior {
        FullscreenBehavior(rawValue: fullscreenBehaviorRaw) ?? .notify
    }

    private var preset: ReminderPreset {
        ReminderPreset(rawValue: presetRaw) ?? .twentyTwentyTwenty
    }

    /// Renders the current onboarding step with navigation controls.
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "OnboardingWelcomeTitle"))
                .font(.title2.weight(.semibold))

            stepView()
                .transition(.opacity)

            HStack {
                if step > 0 {
                    Button(String(localized: "OnboardingBackButton")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            step -= 1
                        }
                    }
                }

                Spacer()

                Button(step == 1 ? String(localized: "OnboardingFinishButton") : String(localized: "OnboardingNextButton")) {
                    handleNext()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    @ViewBuilder
    /// Selects the onboarding content for the current step.
    private func stepView() -> some View {
        switch step {
        case 0:
            fullscreenStep
        default:
            presetStep
        }
    }

    /// Step 1: choose behavior while fullscreen apps are active.
    private var fullscreenStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "OnboardingFullscreenTitle"))
                .font(.headline)
            Text(String(localized: "OnboardingFullscreenSubtitle"))
                .foregroundStyle(.secondary)

            RadioRow(
                title: String(localized: "OnboardingFullscreenNotifyOption"),
                subtitle: String(localized: "OnboardingFullscreenNotifyDetail"),
                isSelected: fullscreenBehavior == .notify
            ) {
                fullscreenBehaviorRaw = FullscreenBehavior.notify.rawValue
            }

            RadioRow(
                title: String(localized: "OnboardingFullscreenInterruptOption"),
                subtitle: String(localized: "OnboardingFullscreenInterruptDetail"),
                isSelected: fullscreenBehavior == .interrupt
            ) {
                fullscreenBehaviorRaw = FullscreenBehavior.interrupt.rawValue
            }

            Toggle(String(localized: "EnforcementNotifOnlyTitle"), isOn: $alwaysNotificationOnly)
            Text(String(localized: "EnforcementNotifOnlySubtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(String(localized: "OnboardingLockScreenToggle"), isOn: $allowLockScreen)
            Text(String(localized: "OnboardingLockScreenDetail"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Step 2: select a timing preset.
    private var presetStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "OnboardingPresetTitle"))
                .font(.headline)
            Text(String(localized: "OnboardingPresetSubtitle"))
                .foregroundStyle(.secondary)

            RadioRow(
                title: String(localized: "OnboardingPreset2020Option"),
                subtitle: String(localized: "OnboardingPreset2020Detail"),
                isSelected: preset == .twentyTwentyTwenty
            ) {
                presetRaw = ReminderPreset.twentyTwentyTwenty.rawValue
            }

            RadioRow(
                title: String(localized: "OnboardingPreset4515Option"),
                subtitle: String(localized: "OnboardingPreset4515Detail"),
                isSelected: preset == .fortyFiveFifteen
            ) {
                presetRaw = ReminderPreset.fortyFiveFifteen.rawValue
            }
        }
    }

    /// Advances steps or completes onboarding.
    private func handleNext() {
        if step < 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                step += 1
            }
        } else {
            applyPreset()
            completed = true
            onComplete()
        }
    }

    /// Persists the chosen preset to settings defaults.
    private func applyPreset() {
        switch preset {
        case .twentyTwentyTwenty:
            intervalMinutes = 20
            breakDurationSeconds = 20
            presetId = "20-20-20"
        case .fortyFiveFifteen:
            intervalMinutes = 45
            breakDurationSeconds = 900
            presetId = "45-15"
        }
        modeIntervalEnabled = false
        modeActiveEnabled = true
        modeScheduleEnabled = false
    }
}

/// Reusable radio-style selection row.
private struct RadioRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onSelect: () -> Void

    /// Renders the row and handles selection.
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(isSelected ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
    }
}
