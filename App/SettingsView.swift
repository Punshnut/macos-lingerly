import AppKit
import SwiftUI
import UniformTypeIdentifiers

private func l(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// SwiftUI form for configuring timing and enforcement settings.
struct SettingsView: View {
    let appState: AppStateController
    @State private var selection: SettingsSidebarItem? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section(l("settings.sidebar.section.basics")) {
                    sidebarRow(.general)
                    sidebarRow(.breakSchedule)
                }

                Section(l("settings.sidebar.section.focus_wellness")) {
                    sidebarRow(.smartPause)
                    sidebarRow(.wellness)
                }

                Section(l("settings.sidebar.section.personalize")) {
                    sidebarRow(.appearance)
                    sidebarRow(.sound)
                    sidebarRow(.widgets)
                }

                Section(l("settings.sidebar.section.advanced")) {
                    sidebarRow(.shortcuts)
                    sidebarRow(.automation)
                }

                Section(l("settings.sidebar.section.about")) {
                    sidebarRow(.about)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 210)
        } detail: {
            SettingsDetailView(selection: selection ?? .general, appState: appState)
        }
        .frame(minWidth: 900, minHeight: 580)
        .applySettingsToolbar()
        .background(SettingsWindowToolbarHider(selection: selection))
        .onChange(of: columnVisibility) { newValue in
            if newValue != .all {
                columnVisibility = .all
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: SettingsSidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .tag(item)
    }
}

private extension View {
    @ViewBuilder
    func applySettingsToolbar() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self.toolbar {
                ToolbarItem(placement: .navigation) {
                    EmptyView()
                }
            }
        }
    }
}

private struct SettingsWindowToolbarHider: NSViewRepresentable {
    let selection: SettingsSidebarItem?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            SettingsWindowToolbarHider.updateWindow(window, coordinator: context.coordinator)
        }
    }

    @MainActor
    private static func updateWindow(_ window: NSWindow, coordinator: Coordinator) {
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true

        guard let toolbar = window.toolbar else { return }
        toolbar.delegate = coordinator
        toolbar.showsBaselineSeparator = false

        let identifiersToRemove: Set<NSToolbarItem.Identifier> = [
            .toggleSidebar,
            .sidebarTrackingSeparator
        ]

        for (index, item) in toolbar.items.enumerated().reversed() {
            let identifier = item.itemIdentifier
            let rawValue = identifier.rawValue.lowercased()
            if identifiersToRemove.contains(identifier)
                || rawValue.contains("sidebar")
                || rawValue.contains("separator")
            {
                toolbar.removeItem(at: index)
            }
        }
        coordinator.ensurePlaceholderItem(in: toolbar)
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate {
        private let placeholderIdentifier = NSToolbarItem.Identifier("SettingsToolbarPlaceholder")

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [placeholderIdentifier]
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [placeholderIdentifier]
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            guard itemIdentifier == placeholderIdentifier else { return nil }
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let view = NSView()
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: 1),
                view.heightAnchor.constraint(equalToConstant: 1)
            ])
            item.view = view
            item.label = ""
            item.paletteLabel = ""
            return item
        }

        @MainActor
        func ensurePlaceholderItem(in toolbar: NSToolbar) {
            if toolbar.items.contains(where: { $0.itemIdentifier == placeholderIdentifier }) {
                return
            }
            toolbar.insertItem(withItemIdentifier: placeholderIdentifier, at: 0)
        }
    }
}

private enum SettingsSidebarItem: String, CaseIterable, Hashable {
    case general
    case breakSchedule
    case smartPause
    case wellness
    case appearance
    case sound
    case widgets
    case shortcuts
    case automation
    case about

    var title: String {
        switch self {
        case .general: return l("settings.sidebar.item.general")
        case .breakSchedule: return l("settings.sidebar.item.break_timing")
        case .smartPause: return l("settings.sidebar.item.auto_pause")
        case .wellness: return l("settings.sidebar.item.wellness")
        case .appearance: return l("settings.sidebar.item.appearance")
        case .sound: return l("settings.sidebar.item.sounds")
        case .widgets: return l("settings.sidebar.item.widgets")
        case .shortcuts: return l("settings.sidebar.item.shortcuts")
        case .automation: return l("settings.sidebar.item.automation")
        case .about: return l("settings.sidebar.item.about")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .breakSchedule: return "calendar"
        case .smartPause: return "pause.circle.fill"
        case .wellness: return "heart.circle.fill"
        case .appearance: return "paintbrush.fill"
        case .sound: return "speaker.wave.2.fill"
        case .widgets: return "square.grid.2x2.fill"
        case .shortcuts: return "command"
        case .automation: return "gearshape.2.fill"
        case .about: return "person.crop.circle.fill"
        }
    }
}

private struct SettingsDetailView: View {
    let selection: SettingsSidebarItem
    let appState: AppStateController

    var body: some View {
        switch selection {
        case .general:
            GeneralSettingsView(appState: appState)
        case .breakSchedule:
            BreakScheduleSettingsView()
        case .smartPause:
            SmartPauseSettingsView()
        case .wellness:
            WellnessSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .sound:
            PlaceholderSettingsView(
                title: l("settings.placeholder.sounds.title"),
                subtitle: l("settings.placeholder.sounds.subtitle"),
                detail: l("settings.placeholder.sounds.detail")
            )
        case .widgets:
            PlaceholderSettingsView(
                title: l("settings.placeholder.widgets.title"),
                subtitle: l("settings.placeholder.widgets.subtitle"),
                detail: l("settings.placeholder.widgets.detail")
            )
        case .shortcuts:
            ShortcutsSettingsView()
        case .automation:
            AutomationSettingsView()
        case .about:
            AboutMeView()
        }
    }
}

private struct GeneralSettingsView: View {
    let appState: AppStateController
    @AppStorage(TimingSettingsKeys.presetId) private var presetId = "20-20-20"

    var body: some View {
        SettingsScrollView(
            title: l("settings.general.title"),
            subtitle: l("settings.general.subtitle")
        ) {
            SettingsCard(l("settings.overview.card.title"), subtitle: l("settings.overview.card.subtitle")) {
                SettingsRow(
                    icon: "dial.high",
                    title: l("settings.overview.preset.title"),
                    subtitle: l("settings.overview.preset.subtitle")
                ) {
                    Text(presetLabel)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                SettingsDivider()

                SettingsRow(
                    icon: "hourglass",
                    title: l("settings.general.next_pause.title"),
                    subtitle: l("settings.general.next_pause.subtitle")
                ) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let display = appState.nextBreakDisplay(at: context.date)
                        let (value, isSecondary) = nextPauseValue(for: display)
                        Text(value)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(isSecondary ? .secondary : .primary)
                            .monospacedDigit()
                    }
                }

                SettingsDivider()

                SettingsRow(
                    icon: "hand.tap.fill",
                    title: l("settings.general.actions.title"),
                    subtitle: l("settings.general.actions.subtitle")
                ) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let isRunning = appState.isRunning
                        HStack(spacing: 10) {
                            Button(String(localized: "Overlay Title")) {
                                appState.takeBreakNow()
                            }
                            Button(String(localized: "Reset Timer")) {
                                appState.resetTimer()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!isRunning)
                    }
                }

                SettingsDivider()

                SettingsRow(
                    icon: "sparkles",
                    title: l("settings.general.updates.title"),
                    subtitle: l("settings.general.updates.subtitle")
                ) {
                    let updaterAvailable = (NSApp.delegate as? AppDelegate)?.isUpdaterAvailable ?? false
                    Button(String(localized: "Check for Updates...")) {
                        (NSApp.delegate as? AppDelegate)?.checkForUpdates(nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!updaterAvailable)
                }
            }
        }
    }

    private var presetLabel: String {
        switch presetId {
        case "20-20-20":
            return l("settings.general.timing_preset.option_20_20_20")
        case "45-15":
            return l("settings.general.timing_preset.option_45_15")
        default:
            return l("settings.general.timing_preset.option_custom")
        }
    }

    private func nextPauseValue(for display: AppStateController.NextBreakDisplay) -> (String, Bool) {
        switch display {
        case .running(let seconds):
            return (AppStateController.formattedCountdown(seconds), false)
        case .breakActive(let seconds):
            let remaining = AppStateController.formattedCountdown(seconds)
            return (String(format: String(localized: "On break %@"), remaining), false)
        case .breakDue:
            return (String(localized: "Break due now"), true)
        case .paused:
            return (String(localized: "Timer paused"), true)
        case .snoozing(let seconds):
            let remaining = AppStateController.formattedCountdown(seconds)
            return (String(format: String(localized: "Snoozing for %@"), remaining), false)
        case .inactive:
            return (String(localized: "Timer stopped"), true)
        }
    }
}

private struct BreakScheduleSettingsView: View {
    @AppStorage(TimingSettingsKeys.presetId) private var presetId = "20-20-20"
    @AppStorage(TimingSettingsKeys.intervalMinutes) private var reminderIntervalMinutes = 20
    @AppStorage(TimingSettingsKeys.breakDurationSeconds) private var breakDurationSeconds = 20
    @AppStorage(TimingSettingsKeys.snoozeMinutes) private var snoozeMinutes = 1
    @State private var showingCustomPreset = false
    @State private var customFocusHours = 0
    @State private var customFocusMinutes = 20
    @State private var customBreakMinutes = 5
    @State private var customBreakSeconds = 0

    var body: some View {
        SettingsScrollView(
            title: l("settings.placeholder.break_timing.title"),
            subtitle: l("settings.placeholder.break_timing.subtitle")
        ) {
            SettingsCard(l("settings.general.card.break_timing.title"), subtitle: l("settings.general.card.break_timing.subtitle")) {
                SettingsRow(
                    icon: "clock.badge",
                    title: l("settings.general.timing_preset.title"),
                    subtitle: l("settings.general.timing_preset.subtitle")
                ) {
                    PresetSegmentedControl(
                        selection: $presetId,
                        labels: [
                            l("settings.general.timing_preset.option_20_20_20"),
                            l("settings.general.timing_preset.option_45_15"),
                            l("settings.general.timing_preset.option_custom")
                        ],
                        ids: ["20-20-20", "45-15", "custom"],
                        onReselect: {
                            if presetId == "custom" && !showingCustomPreset {
                                openCustomPreset()
                            }
                        }
                    )
                    .frame(maxWidth: 240)
                }

                SettingsDivider()

                SettingsRow(
                    icon: "zzz",
                    title: l("settings.general.snooze_length.title"),
                    subtitle: l("settings.general.snooze_length.subtitle")
                ) {
                    HStack(spacing: 12) {
                        Slider(value: snoozeMinutesBinding, in: 1...9, step: 1)
                            .frame(width: 180)
                        Text(String(format: l("settings.general.snooze_length.value"), snoozeMinutes))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }

                SettingsDivider()

                SettingsRow(
                    icon: "timer",
                    title: l("settings.general.current_cycle.title"),
                    subtitle: l("settings.general.current_cycle.subtitle")
                ) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: l("settings.general.current_cycle.focus"), reminderIntervalMinutes))
                            .font(.callout.weight(.semibold))
                        Text(String(format: l("settings.general.current_cycle.break"), formattedBreakDuration(breakDurationSeconds)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: presetId) { newValue in
            applyPreset(newValue)
            if newValue == "custom" {
                openCustomPreset()
            }
        }
        .onChange(of: breakDurationSeconds) { newValue in
            let clamped = clampBreakSeconds(newValue)
            if clamped != newValue {
                breakDurationSeconds = clamped
            }
        }
        .sheet(isPresented: $showingCustomPreset) {
            CustomPresetSheet(
                focusHours: $customFocusHours,
                focusMinutes: $customFocusMinutes,
                    breakMinutes: $customBreakMinutes,
                    breakSeconds: $customBreakSeconds,
                    onCancel: { showingCustomPreset = false },
                    onSave: {
                        applyCustomPreset()
                        showingCustomPreset = false
                }
            )
        }
    }

    private func openCustomPreset() {
        loadCustomPreset()
        showingCustomPreset = true
    }

    private func applyPreset(_ id: String) {
        switch id {
        case "20-20-20":
            reminderIntervalMinutes = 20
            breakDurationSeconds = 20
        case "45-15":
            reminderIntervalMinutes = 45
            breakDurationSeconds = 900
        default:
            break
        }
    }

    private func loadCustomPreset() {
        let focusTotalMinutes = max(reminderIntervalMinutes, 1)
        customFocusHours = focusTotalMinutes / 60
        customFocusMinutes = focusTotalMinutes % 60

        let clampedBreakSeconds = clampBreakSeconds(breakDurationSeconds)
        customBreakMinutes = clampedBreakSeconds / 60
        customBreakSeconds = clampedBreakSeconds % 60
    }

    private func applyCustomPreset() {
        let focusTotalMinutes = max(1, customFocusHours * 60 + customFocusMinutes)
        let breakTotalSeconds = max(1, customBreakMinutes * 60 + customBreakSeconds)
        reminderIntervalMinutes = focusTotalMinutes
        breakDurationSeconds = clampBreakSeconds(breakTotalSeconds)
    }

    private func formattedBreakDuration(_ seconds: Int) -> String {
        let totalSeconds = clampBreakSeconds(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func clampBreakSeconds(_ seconds: Int) -> Int {
        min(max(seconds, 1), 3599)
    }

    private var snoozeMinutesBinding: Binding<Double> {
        Binding(
            get: { Double(snoozeMinutes) },
            set: { snoozeMinutes = Int($0.rounded()) }
        )
    }
}

private struct CustomPresetSheet: View {
    @Binding var focusHours: Int
    @Binding var focusMinutes: Int
    @Binding var breakMinutes: Int
    @Binding var breakSeconds: Int
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l("settings.custom_preset.title"))
                .font(.title2.weight(.semibold))

            durationRow(
                title: l("settings.custom_preset.focus"),
                hours: $focusHours,
                minutes: $focusMinutes,
                maxHours: 12
            )

            durationRow(
                title: l("settings.custom_preset.break"),
                minutes: $breakMinutes,
                seconds: $breakSeconds,
                maxMinutes: 59
            )

            HStack(spacing: 12) {
                Button(l("settings.custom_preset.cancel"), action: onCancel)
                Spacer(minLength: 12)
                Button(l("settings.custom_preset.save"), action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 320)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func durationRow(
        title: String,
        hours: Binding<Int>,
        minutes: Binding<Int>,
        maxHours: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            HStack(spacing: 12) {
                Stepper(
                    value: hours,
                    in: 0...maxHours,
                    step: 1
                ) {
                    Text("\(hours.wrappedValue) \(l("settings.custom_preset.hours"))")
                        .frame(width: 70, alignment: .leading)
                }
                .frame(width: 140, alignment: .leading)
                .controlSize(.small)

                Stepper(
                    value: minutes,
                    in: 0...59,
                    step: 1
                ) {
                    Text("\(minutes.wrappedValue) \(l("settings.custom_preset.minutes"))")
                        .frame(width: 70, alignment: .leading)
                }
                .frame(width: 140, alignment: .leading)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func durationRow(
        title: String,
        minutes: Binding<Int>,
        seconds: Binding<Int>,
        maxMinutes: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            HStack(spacing: 12) {
                Stepper(
                    value: minutes,
                    in: 0...maxMinutes,
                    step: 1
                ) {
                    Text("\(minutes.wrappedValue) \(l("settings.custom_preset.minutes"))")
                        .frame(width: 70, alignment: .leading)
                }
                .frame(width: 140, alignment: .leading)
                .controlSize(.small)

                Stepper(
                    value: seconds,
                    in: 0...59,
                    step: 1
                ) {
                    Text("\(seconds.wrappedValue) \(l("settings.custom_preset.seconds"))")
                        .frame(width: 70, alignment: .leading)
                }
                .frame(width: 140, alignment: .leading)
                .controlSize(.small)
            }
        }
    }
}

private struct PresetSegmentedControl: NSViewRepresentable {
    @Binding var selection: String
    let labels: [String]
    let ids: [String]
    let onReselect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded
        control.controlSize = .regular
        control.setLabel("", forSegment: 0)
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
        }
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if labels.count == nsView.segmentCount {
            for (index, label) in labels.enumerated() {
                if nsView.label(forSegment: index) != label {
                    nsView.setLabel(label, forSegment: index)
                }
            }
        }
        if let index = ids.firstIndex(of: selection) {
            if nsView.selectedSegment != index {
                nsView.selectedSegment = index
            }
        } else {
            nsView.selectedSegment = -1
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PresetSegmentedControl

        init(_ parent: PresetSegmentedControl) {
            self.parent = parent
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard index >= 0, index < parent.ids.count else { return }
            let id = parent.ids[index]
            if id == parent.selection {
                parent.onReselect()
            } else {
                parent.selection = id
            }
        }
    }
}

private struct SmartPauseSettingsView: View {
    @AppStorage(OnboardingKeys.fullscreenBehavior) private var fullscreenBehaviorRaw = FullscreenBehavior.notify.rawValue
    @AppStorage(OnboardingKeys.alwaysNotificationOnly) private var alwaysNotificationOnly = false
    @AppStorage(TimingSettingsKeys.mediaPauseEnabled) private var mediaPauseEnabled = false
    @AppStorage(TimingSettingsKeys.pauseForAppsEnabled) private var pauseForAppsEnabled = false
    @AppStorage(TimingSettingsKeys.smartPauseResumeBehavior) private var smartPauseResumeBehaviorRaw = SmartPauseResumeBehavior.resumeTimer.rawValue
    @AppStorage(TimingSettingsKeys.smartPauseCooldownMinutes) private var smartPauseCooldownMinutes = 1
    @AppStorage(TimingSettingsKeys.resetOnUnlock) private var resetOnUnlock = false
    @State private var pauseAppRules: [PauseAppRule] = []
    private let settingsStore = TimingSettingsStore()

    var body: some View {
        SettingsScrollView(
            title: l("settings.placeholder.auto_pause.title"),
            subtitle: l("settings.placeholder.auto_pause.subtitle")
        ) {
            SettingsCard(l("settings.enforcement.card.title"), subtitle: l("settings.enforcement.card.subtitle")) {
                SettingsToggleRow(
                    icon: "bell.badge",
                    title: l("settings.break_prompt.notification_only.title"),
                    subtitle: l("settings.break_prompt.notification_only.subtitle"),
                    isOn: $alwaysNotificationOnly
                )
            }

            SettingsCard(l("settings.fullscreen.card.title"), subtitle: l("settings.fullscreen.card.subtitle")) {
                SettingsRow(
                    icon: "rectangle.inset.filled.on.rectangle",
                    title: l("settings.fullscreen.interruption.title"),
                    subtitle: l("settings.fullscreen.interruption.subtitle")
                ) {
                    Picker("", selection: $fullscreenBehaviorRaw) {
                        Text(l("settings.fullscreen.interruption.option_notify")).tag(FullscreenBehavior.notify.rawValue)
                        Text(l("settings.fullscreen.interruption.option_interrupt")).tag(FullscreenBehavior.interrupt.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    .disabled(alwaysNotificationOnly)
                }
            }

            SettingsCard(l("settings.unlock.card.title"), subtitle: l("settings.unlock.card.subtitle")) {
                SettingsToggleRow(
                    icon: "lock.open.fill",
                    title: l("settings.unlock.reset.title"),
                    subtitle: l("settings.unlock.reset.subtitle"),
                    isOn: $resetOnUnlock
                )
            }

            SettingsCard(l("settings.media.card.title"), subtitle: l("settings.media.card.subtitle")) {
                SettingsToggleRow(
                    icon: "play.circle.fill",
                    title: l("settings.media.pause.title"),
                    subtitle: l("settings.media.pause.subtitle"),
                    isOn: $mediaPauseEnabled
                )
            }

            SettingsCard(l("settings.pause_apps.card.title"), subtitle: l("settings.pause_apps.card.subtitle")) {
                SettingsToggleRow(
                    icon: "app.badge",
                    title: l("settings.pause_apps.toggle.title"),
                    subtitle: l("settings.pause_apps.toggle.subtitle"),
                    isOn: $pauseForAppsEnabled
                )

                SettingsDivider()

                PauseAppsListEditor(
                    rules: $pauseAppRules,
                    isEnabled: pauseForAppsEnabled
                )
            }

            SettingsCard(l("settings.pause_behavior.card.title"), subtitle: l("settings.pause_behavior.card.subtitle")) {
                SettingsRow(
                    icon: "arrow.clockwise.circle",
                    title: l("settings.pause_behavior.title"),
                    subtitle: l("settings.pause_behavior.subtitle")
                ) {
                    Picker("", selection: $smartPauseResumeBehaviorRaw) {
                        Text(l("settings.pause_behavior.option_resume")).tag(SmartPauseResumeBehavior.resumeTimer.rawValue)
                        Text(l("settings.pause_behavior.option_reset")).tag(SmartPauseResumeBehavior.resetTimer.rawValue)
                        Text(l("settings.pause_behavior.option_countdown")).tag(SmartPauseResumeBehavior.countDownDuringPause.rawValue)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240)
                    .disabled(!hasAnySmartPauseSource)
                }

                SettingsDivider()

                SettingsRow(
                    icon: "hourglass",
                    title: l("settings.pause_behavior.cooldown.title"),
                    subtitle: l("settings.pause_behavior.cooldown.subtitle")
                ) {
                    HStack(spacing: 12) {
                        Slider(value: smartPauseCooldownMinutesBinding, in: 1...5, step: 1)
                            .frame(width: 180)
                        Text(String(format: l("settings.pause_behavior.cooldown.value"), smartPauseCooldownMinutes))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
        .onAppear {
            pauseAppRules = settingsStore.pauseForAppsRules
            smartPauseResumeBehaviorRaw = settingsStore.smartPauseResumeBehavior.rawValue
        }
        .onChange(of: pauseAppRules) { newRules in
            settingsStore.pauseForAppsRules = newRules
        }
    }

    private var hasAnySmartPauseSource: Bool {
        mediaPauseEnabled || (pauseForAppsEnabled && !pauseAppRules.isEmpty)
    }

    private var smartPauseCooldownMinutesBinding: Binding<Double> {
        Binding(
            get: { Double(smartPauseCooldownMinutes) },
            set: { smartPauseCooldownMinutes = max(1, min(Int($0.rounded()), 5)) }
        )
    }
}

private struct PauseAppsListEditor: View {
    @Binding var rules: [PauseAppRule]
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(l("settings.pause_apps.list.title"))
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(l("settings.pause_apps.add_button")) {
                    addAppRule()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isEnabled)
            }

            if rules.isEmpty {
                Text(l("settings.pause_apps.list.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.bottom, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(rules) { rule in
                        PauseAppRuleRow(rule: rule, isEnabled: isEnabled) {
                            removeRule(rule)
                        }
                        if rule.id != rules.last?.id {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(.leading, 48)
        .opacity(isEnabled ? 1 : 0.6)
    }

    private func addAppRule() {
        let panel = NSOpenPanel()
        panel.title = l("settings.pause_apps.panel.title")
        panel.prompt = l("settings.pause_apps.panel.add")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }

        let displayName =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
            url.deletingPathExtension().lastPathComponent

        let newRule = PauseAppRule(
            bundleIdentifier: identifier,
            displayName: displayName,
            bundlePath: bundle.bundlePath
        )

        upsert(newRule)
    }

    private func upsert(_ rule: PauseAppRule) {
        let key = rule.bundleIdentifier.lowercased()
        rules.removeAll { $0.bundleIdentifier.lowercased() == key }
        rules.append(rule)
        rules.sort { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func removeRule(_ rule: PauseAppRule) {
        let key = rule.bundleIdentifier.lowercased()
        rules.removeAll { $0.bundleIdentifier.lowercased() == key }
    }
}

private struct PauseAppRuleRow: View {
    let rule: PauseAppRule
    let isEnabled: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(rule.displayName)
                    .font(.callout)
                    .lineLimit(1)
                Text(rule.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var appIcon: NSImage {
        if let bundlePath = rule.bundlePath,
           FileManager.default.fileExists(atPath: bundlePath) {
            return NSWorkspace.shared.icon(forFile: bundlePath)
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
    }
}

private struct WellnessSettingsView: View {
    @AppStorage(TimingSettingsKeys.waterReminderEnabled) private var waterReminderEnabled = false
    @AppStorage(TimingSettingsKeys.freshAirReminderEnabled) private var freshAirReminderEnabled = false
    @AppStorage(TimingSettingsKeys.standUpReminderEnabled) private var standUpReminderEnabled = false
    @AppStorage(TimingSettingsKeys.workoutReminderEnabled) private var workoutReminderEnabled = false

    var body: some View {
        SettingsScrollView(
            title: l("settings.placeholder.wellness.title"),
            subtitle: l("settings.placeholder.wellness.subtitle")
        ) {
            SettingsCard(l("settings.wellness.card.title"), subtitle: l("settings.wellness.card.subtitle")) {
                SettingsToggleRow(
                    icon: "drop.fill",
                    title: l("settings.wellness.hydration.title"),
                    subtitle: l("settings.wellness.hydration.subtitle"),
                    isOn: $waterReminderEnabled
                )

                SettingsDivider()

                SettingsToggleRow(
                    icon: "wind",
                    title: l("settings.wellness.fresh_air.title"),
                    subtitle: l("settings.wellness.fresh_air.subtitle"),
                    isOn: $freshAirReminderEnabled
                )

                SettingsDivider()

                SettingsToggleRow(
                    icon: "figure.walk",
                    title: l("settings.wellness.stand_up.title"),
                    subtitle: l("settings.wellness.stand_up.subtitle"),
                    isOn: $standUpReminderEnabled
                )

                SettingsDivider()

                SettingsToggleRow(
                    icon: "figure.strengthtraining.traditional",
                    title: l("settings.wellness.workout.title"),
                    subtitle: l("settings.wellness.workout.subtitle"),
                    isOn: $workoutReminderEnabled
                )
            }
        }
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(TimingSettingsKeys.menuBarTimerEnabled) private var menuBarTimerEnabled = false
    @AppStorage(TimingSettingsKeys.overlayStyle) private var overlayStyleRaw = OverlayStyle.modernTahoe.rawValue
    @AppStorage(OnboardingKeys.allowLockScreen) private var allowLockScreen = false

    var body: some View {
        SettingsScrollView(
            title: l("settings.placeholder.appearance.title"),
            subtitle: l("settings.placeholder.appearance.subtitle")
        ) {
            SettingsCard(l("settings.appearance.card.title"), subtitle: l("settings.appearance.card.subtitle")) {
                SettingsToggleRow(
                    icon: "menubar.rectangle",
                    title: l("settings.general.menubar_timer.title"),
                    subtitle: l("settings.general.menubar_timer.subtitle"),
                    badge: l("settings.badge.beta"),
                    isOn: $menuBarTimerEnabled
                )
            }

            SettingsCard(l("settings.appearance.overlay.card.title"), subtitle: l("settings.appearance.overlay.card.subtitle")) {
                SettingsRow(
                    icon: "rectangle.inset.filled.on.rectangle",
                    title: l("settings.appearance.overlay.style.title"),
                    subtitle: l("settings.appearance.overlay.style.subtitle"),
                    badge: l("settings.badge.beta")
                ) {
                    Picker("", selection: $overlayStyleRaw) {
                        Text(l("settings.appearance.overlay.style.option_classic")).tag(OverlayStyle.classic.rawValue)
                        Text(l("settings.appearance.overlay.style.option_modern")).tag(OverlayStyle.modernTahoe.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }

                SettingsDivider()

                SettingsToggleRow(
                    icon: "lock.fill",
                    title: l("settings.enforcement.lock_screen.title"),
                    subtitle: l("settings.enforcement.lock_screen.subtitle"),
                    isOn: $allowLockScreen
                )
            }

            SettingsCard(l("settings.placeholder.card.title")) {
                SettingsRow(
                    icon: "sparkles",
                    title: l("settings.placeholder.appearance.detail"),
                    subtitle: l("settings.placeholder.card.subtitle")
                ) {
                    Text(l("settings.placeholder.badge"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(LinearGradient(colors: [
                                Color(red: 0.62, green: 0.73, blue: 0.96),
                                Color(red: 0.78, green: 0.64, blue: 0.94)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct ShortcutsSettingsView: View {
    @AppStorage(TimingSettingsKeys.hotkeyStartStop) private var startStopShortcut = ""
    @AppStorage(TimingSettingsKeys.hotkeyResetTimer) private var resetTimerShortcut = ""
    @AppStorage(TimingSettingsKeys.hotkeyLingerALittle) private var lingerALittleShortcut = ""
    @AppStorage(TimingSettingsKeys.hotkeySnoozePrompt) private var snoozePromptShortcut = ""

    var body: some View {
        SettingsScrollView(
            title: l("settings.shortcuts.title"),
            subtitle: l("settings.shortcuts.subtitle")
        ) {
            SettingsCard(
                l("settings.shortcuts.card.title"),
                subtitle: l("settings.shortcuts.card.subtitle")
            ) {
                SettingsRow(
                    icon: "playpause.fill",
                    title: l("settings.shortcuts.start_stop.title"),
                    subtitle: l("settings.shortcuts.start_stop.subtitle")
                ) {
                    HotkeyRecorderField(shortcutValue: $startStopShortcut)
                        .frame(width: 220)
                }

                SettingsDivider()

                SettingsRow(
                    icon: "arrow.counterclockwise.circle.fill",
                    title: l("settings.shortcuts.reset_timer.title"),
                    subtitle: l("settings.shortcuts.reset_timer.subtitle")
                ) {
                    HotkeyRecorderField(shortcutValue: $resetTimerShortcut)
                        .frame(width: 220)
                }

                SettingsDivider()

                SettingsRow(
                    icon: "sparkles",
                    title: l("settings.shortcuts.linger.title"),
                    subtitle: l("settings.shortcuts.linger.subtitle")
                ) {
                    HotkeyRecorderField(shortcutValue: $lingerALittleShortcut)
                        .frame(width: 220)
                }

                SettingsDivider()

                SettingsRow(
                    icon: "moon.zzz.fill",
                    title: l("settings.shortcuts.snooze_prompt.title"),
                    subtitle: l("settings.shortcuts.snooze_prompt.subtitle")
                ) {
                    HotkeyRecorderField(shortcutValue: $snoozePromptShortcut)
                        .frame(width: 220)
                }
            }
        }
    }
}

private struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var shortcutValue: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onShortcutChange = { [weak coordinator = context.coordinator] shortcut in
            coordinator?.apply(shortcut: shortcut)
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        context.coordinator.parent = self
        nsView.shortcut = HotkeyShortcut(serialized: shortcutValue)
    }

    @MainActor
    final class Coordinator {
        var parent: HotkeyRecorderField

        init(parent: HotkeyRecorderField) {
            self.parent = parent
        }

        func apply(shortcut: HotkeyShortcut?) {
            parent.shortcutValue = shortcut?.serialized ?? ""
        }
    }
}

private final class HotkeyRecorderView: NSView {
    var onShortcutChange: ((HotkeyShortcut?) -> Void)?
    var shortcut: HotkeyShortcut? {
        didSet { updateLabel() }
    }

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 34)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            // Esc cancels recording without changing the stored shortcut.
            window?.makeFirstResponder(nil)
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            shortcut = nil
            onShortcutChange?(nil)
            window?.makeFirstResponder(nil)
            return
        }

        guard let captured = HotkeyShortcut.from(event: event) else {
            NSSound.beep()
            return
        }

        shortcut = captured
        onShortcutChange?(captured)
        window?.makeFirstResponder(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let roundedRect = NSBezierPath(roundedRect: bounds, xRadius: 11, yRadius: 11)
        let isFocused = window?.firstResponder === self
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let baseTop: NSColor
        let baseBottom: NSColor
        if isDarkMode {
            baseTop = NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.29, alpha: 0.92)
            baseBottom = NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.24, alpha: 0.92)
        } else {
            baseTop = NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.98, alpha: 0.9)
            baseBottom = NSColor(calibratedRed: 0.83, green: 0.87, blue: 0.95, alpha: 0.9)
        }
        let gradient = NSGradient(starting: baseTop, ending: baseBottom)
        gradient?.draw(in: roundedRect, angle: 90)

        let borderColor: NSColor
        if isFocused {
            borderColor = NSColor.controlAccentColor.withAlphaComponent(isDarkMode ? 0.95 : 0.85)
        } else {
            borderColor = NSColor.labelColor.withAlphaComponent(isDarkMode ? 0.30 : 0.18)
        }
        borderColor.setStroke()
        roundedRect.lineWidth = isFocused ? 2 : 1
        roundedRect.stroke()

        super.draw(dirtyRect)
    }

    private func setup() {
        wantsLayer = false
        translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateLabel()
    }

    private func updateLabel() {
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let shortcut {
            label.stringValue = shortcut.displayString
            label.textColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.92)
                : NSColor(calibratedWhite: 0.08, alpha: 0.92)
        } else {
            label.stringValue = l("settings.shortcuts.recorder.placeholder")
            label.textColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.55)
                : NSColor(calibratedWhite: 0.12, alpha: 0.48)
        }
        needsDisplay = true
    }
}

private struct PlaceholderSettingsView: View {
    let title: String
    let subtitle: String
    let detail: String

    var body: some View {
        SettingsScrollView(title: title, subtitle: subtitle) {
            SettingsCard(l("settings.placeholder.card.title")) {
                SettingsRow(
                    icon: "sparkles",
                    title: detail,
                    subtitle: l("settings.placeholder.card.subtitle")
                ) {
                    Text(l("settings.placeholder.badge"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(LinearGradient(colors: [
                                Color(red: 0.62, green: 0.73, blue: 0.96),
                                Color(red: 0.78, green: 0.64, blue: 0.94)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct AutomationSettingsView: View {
    var body: some View {
        SettingsScrollView(
            title: l("settings.automation.title"),
            subtitle: l("settings.automation.subtitle")
        ) {
            SettingsCard(l("settings.automation.card.title"), subtitle: l("settings.automation.card.subtitle")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(l("settings.automation.body"))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        AutomationActionRow(icon: "pause.circle.fill", title: l("settings.automation.action.pause"))
                        AutomationActionRow(icon: "play.circle.fill", title: l("settings.automation.action.resume"))
                        AutomationActionRow(icon: "forward.end.circle.fill", title: l("settings.automation.action.skip"))
                        AutomationActionRow(icon: "moon.zzz.fill", title: l("settings.automation.action.snooze"))
                        AutomationActionRow(icon: "arrow.counterclockwise.circle.fill", title: l("settings.automation.action.reset"))
                    }

                    Text(l("settings.automation.footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AutomationActionRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout.weight(.semibold))
        }
    }
}

private struct AboutMeView: View {
    var body: some View {
        SettingsScrollView(
            title: l("settings.about.title"),
            subtitle: l("settings.about.subtitle")
        ) {
            SettingsCard(l("settings.about.card.title")) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [
                                Color(red: 0.32, green: 0.42, blue: 0.86),
                                Color(red: 0.62, green: 0.34, blue: 0.78)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "sparkles")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                    }
                    .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(l("settings.about.created_by"))
                            .font(.title3.weight(.semibold))
                        Text(l("settings.about.copyright"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

            SettingsCard(l("settings.about.support.title"), subtitle: l("settings.about.support.subtitle")) {
                HStack(alignment: .center, spacing: 12) {
                    Text(l("settings.about.support.body"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 10) {
                        GitHubButton()
                        KoFiButton()
                    }
                }
            }
        }
    }
}

private struct SettingsScrollView<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            SettingsBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsHeader(title: title, subtitle: subtitle)
                    content
                }
                .padding(24)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 12)
            }
        }
    }
}

private struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 16, x: 0, y: 10)
    }

    private var cardFill: some ShapeStyle {
        if colorScheme == .light {
            return AnyShapeStyle(Color.white.opacity(0.78))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderColor: Color {
        colorScheme == .light ? Color.white.opacity(0.5) : Color.white.opacity(0.08)
    }

    private var shadowColor: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.black.opacity(0.18)
    }
}

private struct SettingsRow<Accessory: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: String? = nil
    @ViewBuilder let accessory: Accessory

    init(icon: String, title: String, subtitle: String, badge: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SettingsIcon(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.primary.opacity(0.08))
                            )
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            accessory
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: String? = nil
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SettingsIcon(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.primary.opacity(0.08))
                            )
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.accentColor)
                .disabled(!isEnabled)
        }
        .padding(.vertical, 2)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct SettingsIcon: View {
    let systemName: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(iconGradient)
            Image(systemName: systemName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 34, height: 34)
    }

    private var iconGradient: LinearGradient {
        if colorScheme == .light {
            return LinearGradient(colors: [
                Color(red: 0.18, green: 0.52, blue: 0.86),
                Color(red: 0.23, green: 0.78, blue: 0.68)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [
            Color(red: 0.25, green: 0.32, blue: 0.52),
            Color(red: 0.46, green: 0.3, blue: 0.62)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct SettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
            .padding(.leading, 48)
    }

    private var dividerColor: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.08)
    }
}

private struct SettingsBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .light {
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 0.95, blue: 0.97),
                        Color(red: 0.9, green: 0.92, blue: 0.96),
                        Color(red: 0.86, green: 0.89, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.11, blue: 0.13),
                        Color(red: 0.12, green: 0.12, blue: 0.16),
                        Color(red: 0.08, green: 0.1, blue: 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct KoFiButton: View {
    private let destination = URL(string: "https://ko-fi.com/janfeuerbacher")!

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                Text(l("settings.about.kofi_button"))
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.92, green: 0.32, blue: 0.38),
                        Color(red: 0.96, green: 0.52, blue: 0.36)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct GitHubButton: View {
    @Environment(\.colorScheme) private var colorScheme
    private let destination = URL(string: "https://github.com/Punshnut/macos-lingerly")!

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.slash.chevron.right")
                Text(l("settings.about.github_button"))
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: githubColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var githubColors: [Color] {
        if colorScheme == .light {
            return [
                Color(red: 0.28, green: 0.3, blue: 0.35),
                Color(red: 0.2, green: 0.22, blue: 0.27)
            ]
        }
        return [
            Color(red: 0.2, green: 0.22, blue: 0.26),
            Color(red: 0.14, green: 0.16, blue: 0.19)
        ]
    }
}
