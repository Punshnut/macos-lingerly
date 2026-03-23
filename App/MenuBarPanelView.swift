import AppKit
import SwiftUI

/// Localized lookup with explicit fallback used by the menu panel.
private func menuPanelL(_ key: String, _ fallback: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
}

@MainActor
final class MenuBarPanelViewModel: ObservableObject {
    enum StatusKind {
        case idle
        case running
        case paused
        case muted
        case cooldown
        case snoozing
        case breakDue
        case onBreak

        var symbol: String {
            switch self {
            case .idle: return "stop.circle"
            case .running: return "clock.arrow.2.circlepath"
            case .paused: return "pause.circle"
            case .muted: return "speaker.slash.fill"
            case .cooldown: return "hourglass"
            case .snoozing: return "moon.zzz"
            case .breakDue: return "exclamationmark.circle"
            case .onBreak: return "figure.mind.and.body"
            }
        }

        var tint: Color {
            switch self {
            case .idle: return .secondary
            case .running: return .blue
            case .muted: return .purple
            case .paused, .cooldown, .snoozing: return .orange
            case .breakDue: return .red
            case .onBreak: return .green
            }
        }

        var subtitle: String {
            switch self {
            case .idle:
                return menuPanelL("menu.panel.status.subtitle.idle", "Reminders are currently off")
            case .running:
                return menuPanelL("menu.panel.status.subtitle.running", "Lingerly rhythm is active")
            case .paused:
                return menuPanelL("menu.panel.status.subtitle.paused", "Timer is paused")
            case .muted:
                return menuPanelL("menu.panel.status.subtitle.muted", "Muted while timer keeps counting")
            case .cooldown:
                return menuPanelL("menu.panel.status.subtitle.cooldown", "Auto-pause cooldown in progress")
            case .snoozing:
                return menuPanelL("menu.panel.status.subtitle.snoozing", "Snooze is active")
            case .breakDue:
                return menuPanelL("menu.panel.status.subtitle.break_due", "Break prompt is waiting")
            case .onBreak:
                return menuPanelL("menu.panel.status.subtitle.on_break", "Break session in progress")
            }
        }
    }

    @Published var statusText = ""
    @Published var statusKind: StatusKind = .idle

    @Published var isRunning = false
    @Published var isPaused = false

    @Published var intervalMinutes = 20
    @Published var breakDurationSeconds = 20
    @Published var snoozeMinutes = 5
    @Published var selectedPresetID = "custom"

    @Published var modeActiveEnabled = true
    @Published var modeScheduleEnabled = false
    @Published var menuBarTimerEnabled = false
    @Published var mediaPauseEnabled = false
    @Published var resetOnUnlock = false
    @Published var mutedModeEnabled = false
    @Published var launchAtLoginEnabled = false
    @Published var smartPauseCooldownMinutes = 1
    @Published var smartPauseResumeBehavior: SmartPauseResumeBehavior = .resumeTimer
    @Published var isPanelVisible = false

    var onToggleStartStop: (() -> Void)?
    var onDeferOneMinute: (() -> Void)?
    var onDeferFiveMinutes: (() -> Void)?
    var onDeferFifteenMinutes: (() -> Void)?
    var onBringOneMinuteCloser: (() -> Void)?
    var onBringFiveMinutesCloser: (() -> Void)?
    var onBringFifteenMinutesCloser: (() -> Void)?
    var onToggleMutedMode: (() -> Void)?
    var onTakeBreakNow: (() -> Void)?
    var onResetTimer: (() -> Void)?
    var onSkipBreak: (() -> Void)?
    var onSetIntervalMinutes: ((Int) -> Void)?
    var onSetBreakDurationSeconds: ((Int) -> Void)?
    var onSetSnoozeMinutes: ((Int) -> Void)?
    var onApplyPreset: ((String) -> Void)?
    var onSetModeActiveEnabled: ((Bool) -> Void)?
    var onSetModeScheduleEnabled: ((Bool) -> Void)?
    var onSetMenuBarTimerEnabled: ((Bool) -> Void)?
    var onSetMediaPauseEnabled: ((Bool) -> Void)?
    var onSetResetOnUnlock: ((Bool) -> Void)?
    var onSetLaunchAtLoginEnabled: ((Bool) -> Void)?
    var onSetSmartPauseCooldownMinutes: ((Int) -> Void)?
    var onSetSmartPauseResumeBehavior: ((SmartPauseResumeBehavior) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onPanelHeightChange: ((CGFloat, Bool) -> Void)?

    var startStopTitle: String {
        (!isRunning || isPaused)
            ? menuPanelL("menu.panel.controls.start", "Start")
            : menuPanelL("menu.panel.controls.pause", "Pause")
    }

    var startStopSymbol: String {
        (!isRunning || isPaused) ? "play.fill" : "pause.fill"
    }
}

struct MenuBarPanelView: View {
    static let panelWidth: CGFloat = 396
    static let defaultPanelHeight: CGFloat = 460
    private static let chromeHeight: CGFloat = 178
    private static let rhythmContentHeight: CGFloat = 256
    private static let soundsContentHeight: CGFloat = 230
    private static let settingsContentHeight: CGFloat = 282

    @ObservedObject var model: MenuBarPanelViewModel
    @State private var selectedTab: Tab = .rhythm

    @State private var auroraDrift = false
    @State private var shimmerTravel = false
    @State private var statusPulse = false
    @State private var alertSoundsEnabled = true
    @State private var backgroundPauseSoundsEnabled = false
    @State private var selectedAlertSound: AlertSoundStyle = .bell
    @State private var selectedBackgroundSound: BackgroundSoundStyle = .waves

    private enum Tab: String, CaseIterable, Identifiable {
        case rhythm
        case settings
        case sounds

        var id: String { rawValue }
        var title: String {
            switch self {
            case .rhythm: return menuPanelL("menu.panel.tab.lingerly", "Lingerly")
            case .settings: return menuPanelL("menu.panel.tab.settings", "Settings")
            case .sounds: return menuPanelL("menu.panel.tab.sounds", "Sounds")
            }
        }
    }

    private enum AlertSoundStyle: String, CaseIterable, Identifiable {
        case bell
        case glass
        case chime

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bell: return menuPanelL("menu.panel.sound.alert.bell", "Bell")
            case .glass: return menuPanelL("menu.panel.sound.alert.glass", "Glass")
            case .chime: return menuPanelL("menu.panel.sound.alert.chime", "Chime")
            }
        }

        var symbol: String {
            switch self {
            case .bell: return "bell.fill"
            case .glass: return "sparkles"
            case .chime: return "tuningfork"
            }
        }
    }

    private enum BackgroundSoundStyle: String, CaseIterable, Identifiable {
        case waves
        case rain
        case forest

        var id: String { rawValue }

        var title: String {
            switch self {
            case .waves: return menuPanelL("menu.panel.sound.background.waves", "Waves")
            case .rain: return menuPanelL("menu.panel.sound.background.rain", "Rain")
            case .forest: return menuPanelL("menu.panel.sound.background.forest", "Forest")
            }
        }

        var symbol: String {
            switch self {
            case .waves: return "water.waves"
            case .rain: return "cloud.drizzle.fill"
            case .forest: return "leaf.fill"
            }
        }
    }

    private var contentHeight: CGFloat {
        max(Self.rhythmContentHeight, Self.soundsContentHeight, Self.settingsContentHeight)
    }

    private var panelHeight: CGFloat {
        Self.chromeHeight + contentHeight
    }

    private var resizeAnimation: Animation {
        .spring(response: 0.24, dampingFraction: 0.9)
    }

    private var shouldPulseStatus: Bool {
        model.statusKind == .running || model.statusKind == .onBreak || model.statusKind == .breakDue
    }

    var body: some View {
        VStack(spacing: 10) {
            controlsRow
            statusBar
            tabRow

            Group {
                if selectedTab == .rhythm {
                    rhythmTab
                } else if selectedTab == .sounds {
                    soundsTab
                } else {
                    settingsTab
                }
            }
            .frame(height: contentHeight, alignment: .top)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.bottom, 14)
        .padding(.top, 6)
        .frame(width: Self.panelWidth, height: panelHeight, alignment: .top)
        .background(panelBackdrop)
        .onAppear {
            reportPanelHeight(animated: false)
            if model.isPanelVisible {
                startAmbientAnimations()
            }
        }
        .onChange(of: model.statusKind) { _ in
            restartStatusPulseIfNeeded()
        }
        .onChange(of: model.isPanelVisible) { isVisible in
            if isVisible {
                startAmbientAnimations()
            } else {
                stopAmbientAnimations()
            }
        }
        .onDisappear {
            stopAmbientAnimations()
        }
    }

    private var panelBackdrop: some View {
        shellAuraOverlay
            .mask(
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.white, .white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                        )
                        .frame(height: 54)
                }
            )
    }

    private var shellAuraOverlay: some View {
        ZStack {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.pink.opacity(0.35), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 260, height: 260)
                    .blur(radius: 30)
                    .offset(x: auroraDrift ? 130 : -120, y: auroraDrift ? -100 : -20)

                Circle()
                    .fill(LinearGradient(colors: [Color.cyan.opacity(0.28), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 240, height: 240)
                    .blur(radius: 34)
                    .offset(x: auroraDrift ? -130 : 110, y: auroraDrift ? 90 : 10)

                Circle()
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.2), Color.clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 300, height: 300)
                    .blur(radius: 44)
                    .offset(x: auroraDrift ? 0 : 40, y: auroraDrift ? 40 : -80)
            }

            LinearGradient(
                colors: [.white.opacity(0.12), .white.opacity(0.04), .black.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .allowsHitTesting(false)
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button(action: { model.onToggleStartStop?() }) {
                Label(model.startStopTitle, systemImage: model.startStopSymbol)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .background(startButtonBackground)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.24), lineWidth: 0.8)
            )
            .contentShape(Capsule(style: .continuous))

            topActionButton(title: "+1", action: { model.onDeferOneMinute?() }, isEnabled: model.isRunning)
            topActionButton(title: "+5", action: { model.onDeferFiveMinutes?() }, isEnabled: model.isRunning)
            topActionButton(
                symbol: "moon.zzz.fill",
                action: { model.onToggleMutedMode?() },
                isEnabled: true,
                isSelected: model.mutedModeEnabled
            )
            topActionButton(symbol: "arrow.counterclockwise", action: { model.onResetTimer?() }, isEnabled: model.isRunning)
        }
    }

    private var startButtonBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1, green: 0.3, blue: 0.32), Color(red: 1, green: 0.22, blue: 0.37)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 120)
                .offset(x: shimmerTravel ? 220 : -150)
                .blendMode(.screen)
        }
        .clipShape(Capsule(style: .continuous))
    }

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                tabButton(tab, title: tab.title)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(0.18))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 0.7)
        )
    }

    /// Renders a segmented tab button with animated selection state.
    private func tabButton(_ tab: Tab, title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedTab = tab
            }
        } label: {
            ZStack {
                Capsule(style: .continuous)
                    .fill(
                        selectedTab == tab
                            ? LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [Color.clear, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )

                Text(title)
                    .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(selectedTab == tab ? 1 : 0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentTransition(.identity)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var rhythmTab: some View {
        VStack(spacing: 8) {
            frostedIsland {
                HStack(spacing: 8) {
                    presetButton(title: "20-20-20", presetID: "20-20-20")
                    presetButton(title: "45-15", presetID: "45-15")
                    presetTag(title: menuPanelL("menu.panel.preset.custom", "Custom"), isSelected: model.selectedPresetID == "custom")
                }

                HStack(spacing: 8) {
                    soundQuickToggle(
                        title: menuPanelL("menu.panel.sound.quick.alerts", "Alerts"),
                        systemImage: "bell.badge.fill",
                        isSelected: alertSoundsEnabled
                    ) {
                        alertSoundsEnabled.toggle()
                    }
                    soundQuickToggle(
                        title: menuPanelL("menu.panel.sound.quick.background", "Background"),
                        systemImage: "waveform",
                        isSelected: backgroundPauseSoundsEnabled
                    ) {
                        backgroundPauseSoundsEnabled.toggle()
                    }
                }
            }

            frostedIsland {
                valueAdjustRow(
                    title: menuPanelL("menu.panel.timer.focus_interval", "Focus interval"),
                    valueText: minutesText(model.intervalMinutes),
                    canDecrease: model.intervalMinutes > 1,
                    canIncrease: model.intervalMinutes < 180,
                    decrease: {
                        let value = max(1, model.intervalMinutes - 1)
                        model.intervalMinutes = value
                        model.onSetIntervalMinutes?(value)
                    },
                    increase: {
                        let value = min(180, model.intervalMinutes + 1)
                        model.intervalMinutes = value
                        model.onSetIntervalMinutes?(value)
                    }
                )

                valueAdjustRow(
                    title: menuPanelL("menu.panel.timer.break_length", "Break length"),
                    valueText: formatDuration(seconds: model.breakDurationSeconds),
                    canDecrease: model.breakDurationSeconds > 5,
                    canIncrease: model.breakDurationSeconds < 1800,
                    decrease: {
                        let value = max(5, model.breakDurationSeconds - 5)
                        model.breakDurationSeconds = value
                        model.onSetBreakDurationSeconds?(value)
                    },
                    increase: {
                        let value = min(1800, model.breakDurationSeconds + 5)
                        model.breakDurationSeconds = value
                        model.onSetBreakDurationSeconds?(value)
                    }
                )

                valueAdjustRow(
                    title: menuPanelL("menu.panel.timer.snooze", "Snooze"),
                    valueText: minutesText(model.snoozeMinutes),
                    canDecrease: model.snoozeMinutes > 1,
                    canIncrease: model.snoozeMinutes < 60,
                    decrease: {
                        let value = max(1, model.snoozeMinutes - 1)
                        model.snoozeMinutes = value
                        model.onSetSnoozeMinutes?(value)
                    },
                    increase: {
                        let value = min(60, model.snoozeMinutes + 1)
                        model.snoozeMinutes = value
                        model.onSetSnoozeMinutes?(value)
                    }
                )
            }

            frostedIsland {
                HStack(spacing: 8) {
                    quickShiftButton("-15", action: { model.onBringFifteenMinutesCloser?() }, isEnabled: model.isRunning)
                    quickShiftButton("-5", action: { model.onBringFiveMinutesCloser?() }, isEnabled: model.isRunning)
                    quickShiftButton("-1", action: { model.onBringOneMinuteCloser?() }, isEnabled: model.isRunning)
                    quickShiftButton("+1", action: { model.onDeferOneMinute?() }, isEnabled: model.isRunning)
                    quickShiftButton("+5", action: { model.onDeferFiveMinutes?() }, isEnabled: model.isRunning)
                    quickShiftButton("+15", action: { model.onDeferFifteenMinutes?() }, isEnabled: model.isRunning)
                }

                HStack(spacing: 8) {
                    actionButton(menuPanelL("menu.panel.action.break_now", "Break now"), action: { model.onTakeBreakNow?() }, isEnabled: model.isRunning)
                    actionButton(menuPanelL("menu.panel.action.skip_break", "Skip break"), action: { model.onSkipBreak?() }, isEnabled: model.isRunning)
                    actionButton(menuPanelL("menu.panel.action.restart", "Restart"), action: { model.onResetTimer?() }, isEnabled: model.isRunning)
                }
            }
        }
    }

    private var soundsTab: some View {
        VStack(spacing: 8) {
            compactFrostedIsland {
                soundCategoryBlock(
                    title: menuPanelL("menu.panel.sound.category.alerts", "Alerts"),
                    subtitle: menuPanelL("menu.panel.sound.category.alerts.subtitle", "Start and end cues"),
                    systemImage: "bell.badge.fill",
                    tint: .orange,
                    isEnabled: alertSoundsEnabled,
                    toggleAction: { alertSoundsEnabled.toggle() }
                ) {
                    ForEach(AlertSoundStyle.allCases) { style in
                        soundFamilyButton(
                            title: style.title,
                            systemImage: style.symbol,
                            isSelected: selectedAlertSound == style,
                            action: {
                                selectedAlertSound = style
                                alertSoundsEnabled = true
                            }
                        )
                    }
                }
            }

            compactFrostedIsland {
                soundCategoryBlock(
                    title: menuPanelL("menu.panel.sound.category.background", "Background"),
                    subtitle: menuPanelL("menu.panel.sound.category.background.subtitle", "During the pause"),
                    systemImage: "waveform",
                    tint: .cyan,
                    isEnabled: backgroundPauseSoundsEnabled,
                    toggleAction: { backgroundPauseSoundsEnabled.toggle() }
                ) {
                    ForEach(BackgroundSoundStyle.allCases) { style in
                        soundFamilyButton(
                            title: style.title,
                            systemImage: style.symbol,
                            isSelected: selectedBackgroundSound == style,
                            action: {
                                selectedBackgroundSound = style
                                backgroundPauseSoundsEnabled = true
                            }
                        )
                    }
                }
            }

            compactFrostedIsland {
                HStack(spacing: 8) {
                    soundPreviewButton(
                        title: menuPanelL("menu.panel.sound.preview.alert", "Play Alert"),
                        systemImage: "bell.fill"
                    ) {
                        alertSoundsEnabled = true
                    }
                    soundPreviewButton(
                        title: menuPanelL("menu.panel.sound.preview.background", "Play Background"),
                        systemImage: "waveform"
                    ) {
                        backgroundPauseSoundsEnabled = true
                    }
                }
            }
        }
    }

    private var settingsTab: some View {
        VStack(spacing: 10) {
            frostedIsland {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    settingTile(icon: "bolt.fill", title: menuPanelL("menu.panel.settings.active_time", "Active-time"), isOn: model.modeActiveEnabled) {
                        model.modeActiveEnabled.toggle()
                        model.onSetModeActiveEnabled?(model.modeActiveEnabled)
                    }
                    settingTile(icon: "power", title: menuPanelL("menu.panel.settings.launch_at_login", "Launch at login"), isOn: model.launchAtLoginEnabled) {
                        model.launchAtLoginEnabled.toggle()
                        model.onSetLaunchAtLoginEnabled?(model.launchAtLoginEnabled)
                    }
                    settingTile(icon: "calendar", title: menuPanelL("menu.panel.settings.schedule", "Schedule"), isOn: model.modeScheduleEnabled) {
                        model.modeScheduleEnabled.toggle()
                        model.onSetModeScheduleEnabled?(model.modeScheduleEnabled)
                    }
                    settingTile(icon: "menubar.rectangle", title: menuPanelL("menu.panel.settings.menu_bar_timer", "Menu bar timer"), isOn: model.menuBarTimerEnabled) {
                        model.menuBarTimerEnabled.toggle()
                        model.onSetMenuBarTimerEnabled?(model.menuBarTimerEnabled)
                    }
                    settingTile(icon: "play.circle", title: menuPanelL("menu.panel.settings.pause_on_media", "Pause on media"), isOn: model.mediaPauseEnabled) {
                        model.mediaPauseEnabled.toggle()
                        model.onSetMediaPauseEnabled?(model.mediaPauseEnabled)
                    }
                    settingTile(icon: "lock.open.trianglebadge.exclamationmark", title: menuPanelL("menu.panel.settings.reset_on_unlock", "Reset on unlock"), isOn: model.resetOnUnlock) {
                        model.resetOnUnlock.toggle()
                        model.onSetResetOnUnlock?(model.resetOnUnlock)
                    }
                }
            }

            frostedIsland {
                Text(menuPanelL("menu.panel.settings.start_resume_behavior", "Start/Resume button behavior"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    resumeStyleChip(
                        title: menuPanelL("menu.panel.settings.resume_behavior.resume", "Resume"),
                        isSelected: model.smartPauseResumeBehavior == .resumeTimer
                    ) {
                        model.smartPauseResumeBehavior = .resumeTimer
                        model.onSetSmartPauseResumeBehavior?(.resumeTimer)
                    }
                    resumeStyleChip(
                        title: menuPanelL("menu.panel.settings.resume_behavior.reset", "Reset"),
                        isSelected: model.smartPauseResumeBehavior == .resetTimer
                    ) {
                        model.smartPauseResumeBehavior = .resetTimer
                        model.onSetSmartPauseResumeBehavior?(.resetTimer)
                    }
                }
            }

            frostedIsland {
                valueAdjustRow(
                    title: menuPanelL("menu.panel.settings.smart_pause_cooldown", "Smart pause cooldown"),
                    valueText: minutesText(model.smartPauseCooldownMinutes),
                    canDecrease: model.smartPauseCooldownMinutes > 1,
                    canIncrease: model.smartPauseCooldownMinutes < 5,
                    decrease: {
                        let value = max(1, model.smartPauseCooldownMinutes - 1)
                        model.smartPauseCooldownMinutes = value
                        model.onSetSmartPauseCooldownMinutes?(value)
                    },
                    increase: {
                        let value = min(5, model.smartPauseCooldownMinutes + 1)
                        model.smartPauseCooldownMinutes = value
                        model.onSetSmartPauseCooldownMinutes?(value)
                    }
                )

                valueAdjustRow(
                    title: menuPanelL("menu.panel.settings.snooze_length", "Snooze length"),
                    valueText: minutesText(model.snoozeMinutes),
                    canDecrease: model.snoozeMinutes > 1,
                    canIncrease: model.snoozeMinutes < 60,
                    decrease: {
                        let value = max(1, model.snoozeMinutes - 1)
                        model.snoozeMinutes = value
                        model.onSetSnoozeMinutes?(value)
                    },
                    increase: {
                        let value = min(60, model.snoozeMinutes + 1)
                        model.snoozeMinutes = value
                        model.onSetSnoozeMinutes?(value)
                    }
                )
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            ZStack {
                if shouldPulseStatus {
                    Circle()
                        .stroke(model.statusKind.tint.opacity(0.55), lineWidth: 1.6)
                        .frame(width: 26, height: 26)
                        .scaleEffect(statusPulse ? 1.22 : 0.8)
                        .opacity(statusPulse ? 0 : 0.7)
                        .animation(
                            model.isPanelVisible
                                ? .easeOut(duration: 1.5).repeatForever(autoreverses: false)
                                : .none,
                            value: statusPulse
                        )
                }

                Image(systemName: model.statusKind.symbol)
                    .foregroundStyle(model.statusKind.tint)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.statusText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(model.statusKind.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                GlassMaterialView(material: .hudWindow)
                Color.white.opacity(0.08)
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 0.7)
        )
    }

    /// Starts long-running background animations once on initial appearance.
    private func startAmbientAnimations() {
        guard model.isPanelVisible else { return }
        guard auroraDrift == false, shimmerTravel == false else { return }
        withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
            auroraDrift = true
        }
        withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
            shimmerTravel = true
        }
        restartStatusPulseIfNeeded()
    }

    /// Stops infinite animations while the menu is hidden.
    private func stopAmbientAnimations() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            auroraDrift = false
            shimmerTravel = false
            statusPulse = false
        }
    }

    /// Restarts the visible status pulse after state or visibility changes.
    private func restartStatusPulseIfNeeded() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            statusPulse = false
        }

        guard model.isPanelVisible, shouldPulseStatus else { return }
        statusPulse = true
    }

    /// Builds the compact circular action buttons used in the top control row.
    private func topActionButton(
        title: String? = nil,
        symbol: String? = nil,
        action: @escaping () -> Void,
        isEnabled: Bool,
        isSelected: Bool = false
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(isEnabled ? 0.82 : 0.38)
                            : Color.white.opacity(isEnabled ? 0.22 : 0.1)
                    )
                Circle()
                    .strokeBorder(.white.opacity(0.26), lineWidth: 0.7)

                Group {
                    if let title {
                        Text(title)
                    } else if let symbol {
                        Image(systemName: symbol)
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    isSelected
                        ? Color.white.opacity(isEnabled ? 1 : 0.55)
                        : Color.primary.opacity(isEnabled ? 1 : 0.45)
                )
            }
            .frame(width: 38, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    /// Wraps content in the panel's shared frosted-glass container style.
    private func frostedIsland<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
        }
        .padding(10)
        .background(
            ZStack {
                GlassMaterialView(material: .hudWindow)
                LinearGradient(
                    colors: [.white.opacity(0.1), .white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }

    /// Tighter glass card used in the sounds tab so all content remains visible.
    private func compactFrostedIsland<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
        }
        .padding(8)
        .background(
            ZStack {
                GlassMaterialView(material: .hudWindow)
                LinearGradient(
                    colors: [.white.opacity(0.1), .white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
    }

    /// Renders a tappable settings toggle tile with current on/off state.
    private func settingTile(
        icon: String,
        title: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(isOn ? Color.accentColor : Color.white.opacity(0.14))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 0.6)
                    )
            }
            .foregroundStyle(isOn ? Color.primary : Color.primary.opacity(0.88))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? Color.white.opacity(0.3) : Color.white.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Renders one selectable smart-pause resume behavior chip.
    private func resumeStyleChip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.82))
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.34) : Color.white.opacity(0.15))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.24), lineWidth: 0.6)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Builds a full-width action button for break/session controls.
    private func actionButton(_ title: String, action: @escaping () -> Void, isEnabled: Bool) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(.primary.opacity(isEnabled ? 1 : 0.46))
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(isEnabled ? 0.21 : 0.1))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                )
                .contentShape(Capsule(style: .continuous))
        }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
    }

    /// Builds +/- quick-shift controls for adjusting next break timing.
    private func quickShiftButton(_ title: String, action: @escaping () -> Void, isEnabled: Bool) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .foregroundStyle(.primary.opacity(isEnabled ? 1 : 0.46))
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(isEnabled ? 0.2 : 0.1))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                )
                .contentShape(Capsule(style: .continuous))
        }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
    }

    /// Displays a value row with decrement/increment steppers.
    private func valueAdjustRow(
        title: String,
        valueText: String,
        canDecrease: Bool = true,
        canIncrease: Bool = true,
        decrease: @escaping () -> Void,
        increase: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))

            Spacer(minLength: 8)

            Text(valueText)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 84, alignment: .trailing)
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)

            HStack(spacing: 5) {
                miniStepButton(symbol: "minus", action: decrease, isEnabled: canDecrease)
                miniStepButton(symbol: "plus", action: increase, isEnabled: canIncrease)
            }
            .fixedSize()
        }
        .frame(height: 22)
    }

    /// Small circular stepper button used inside numeric rows.
    private func miniStepButton(symbol: String, action: @escaping () -> Void, isEnabled: Bool) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(isEnabled ? 0.2 : 0.11))
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary.opacity(isEnabled ? 0.94 : 0.36))
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
    }

    /// Selects and applies a built-in timing preset.
    private func presetButton(title: String, presetID: String) -> some View {
        Button {
            model.selectedPresetID = presetID
            model.onApplyPreset?(presetID)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(model.selectedPresetID == presetID ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.13))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Non-interactive visual tag used for the current custom preset state.
    private func presetTag(title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.13))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
            )
    }

    /// Compact toggle used in the rhythm tab for quick muting of sound families.
    private func soundQuickToggle(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.white.opacity(0.14))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.28), lineWidth: 0.6)
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.11))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Shared block for alert/background sound families with a quiet header and simple style buttons.
    private func soundCategoryBlock<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isEnabled: Bool,
        toggleAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(action: toggleAction) {
                    HStack(spacing: 5) {
                        Image(systemName: isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isEnabled ? menuPanelL("menu.panel.sound.toggle.on", "On") : menuPanelL("menu.panel.sound.toggle.off", "Muted"))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .foregroundStyle(isEnabled ? Color.primary : Color.primary.opacity(0.78))
                    .background(
                        Capsule(style: .continuous)
                            .fill(isEnabled ? Color.white.opacity(0.24) : Color.white.opacity(0.11))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                    )
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                content()
            }
            .opacity(isEnabled ? 1 : 0.58)
        }
    }

    /// Button used for selecting one alert/background sound family.
    private func soundFamilyButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.28) : Color.white.opacity(0.12))
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.82))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [Color.white.opacity(0.26), Color.white.opacity(0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.13), Color.white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.28 : 0.22), lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Preview-style action for testing one of the placeholder sound families.
    private func soundPreviewButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Formats seconds as a concise localized duration for panel rows.
    private func formatDuration(seconds: Int) -> String {
        let total = max(seconds, 0)
        let minutes = total / 60
        let remainder = total % 60
        if minutes == 0 {
            return String(
                format: menuPanelL("menu.panel.value.seconds_short_format", "%ds"),
                remainder
            )
        }
        if remainder == 0 {
            return minutesText(minutes)
        }
        return String(
            format: menuPanelL("menu.panel.value.minutes_seconds_short_format", "%dm %ds"),
            minutes,
            remainder
        )
    }

    /// Formats minutes using the localized short "x min" string.
    private func minutesText(_ minutes: Int) -> String {
        String(
            format: menuPanelL("menu.panel.value.minutes_format", "%d min"),
            minutes
        )
    }

    /// Reports the currently selected panel height so AppKit can keep the menu item in sync.
    private func reportPanelHeight(animated: Bool) {
        model.onPanelHeightChange?(panelHeight, animated)
    }
}

private struct GlassMaterialView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    /// Creates the AppKit visual-effect background used by panel cards.
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = .withinWindow
        return view
    }

    /// Keeps material/state synchronized during SwiftUI updates.
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.state = .active
    }
}
