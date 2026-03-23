import AppKit
import Sparkle
import SwiftUI

private final class ControlPanelMenuContainerView: NSView {
    let hostingView: NSHostingView<MenuBarPanelView>

    init(rootView: MenuBarPanelView, size: NSSize) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: NSRect(origin: .zero, size: size))
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        setPanelSize(size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        frame.size
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    func setPanelSize(_ size: NSSize) {
        setFrameSize(size)
        hostingView.frame = bounds
        invalidateIntrinsicContentSize()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

/// Manages lifecycle, menu bar UI, and top-level windows for the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var controlPanelItem: NSMenuItem?
    private var controlPanelContainerView: ControlPanelMenuContainerView?
    private var controlPanelHeight: CGFloat = MenuBarPanelView.defaultPanelHeight
    private let settingsStore = TimingSettingsStore()
    private let launchAtLoginController = LaunchAtLoginController()
    private let controlPanelViewModel = MenuBarPanelViewModel()
    private let menuBarTimerFixedWidth: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let sample = "88:88:88" as NSString
        let textWidth = ceil(sample.size(withAttributes: [.font: font]).width)
        return NSStatusItem.squareLength + textWidth + 18
    }()
    private lazy var updaterController: SPUStandardUpdaterController? = {
        guard Self.isSparkleConfigurationValid() else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()
    let appState = AppStateController()
    let settingsNavigationState = SettingsNavigationState()
    private var settingsItem: NSMenuItem?
    private var checkForUpdatesItem: NSMenuItem?
    private var aboutItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var menuUpdateTimer: DispatchSourceTimer?
    private var isMenuOpen = false
    private var hotkeyManager: GlobalHotkeyManager?
    private var defaultsObserver: NSObjectProtocol?
    private let settingsMenuShortcut = ","
    private let quitMenuShortcut = "q"
    
    var isUpdaterAvailable: Bool {
        updaterController != nil
    }

    /// Boots the menu bar UI and starts the timing engine.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        hotkeyManager = GlobalHotkeyManager { [weak self] action in
            self?.handleHotkeyAction(action)
        }
        hotkeyManager?.reload()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hotkeyManager?.reload()
                self?.applyMenuBarStatusWidth()
                self?.updateCountdownTitle()
            }
        }
        appState.onStateChange = { [weak self] _ in
            self?.refreshStatusUI()
        }
        appState.start()
        refreshStatusUI()
        refreshMenuUpdateTimerIfNeeded()
        showOnboardingIfNeeded()
    }

    /// Keeps the menu bar app alive when settings/onboarding windows close.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Presents the onboarding flow on first launch.
    private func showOnboardingIfNeeded() {
        let completed = UserDefaults.standard.bool(forKey: OnboardingKeys.completed)
        guard !completed else { return }

        let onboardingView = OnboardingView { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }

        let hosting = NSHostingController(rootView: onboardingView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Onboarding Window Title")
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    /// Builds the status item and its menu actions.
    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.showsStateColumn = false

        configureControlPanelCallbacks()
        let controlPanelItem = NSMenuItem()
        self.controlPanelItem = controlPanelItem
        controlPanelItem.view = makeControlPanelView()
        menu.addItem(controlPanelItem)

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings..."),
            action: #selector(openSettings(_:)),
            keyEquivalent: settingsMenuShortcut
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        let settingsImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsImage?.isTemplate = true
        settingsItem.image = settingsImage
        menu.addItem(settingsItem)
        self.settingsItem = settingsItem

        let checkForUpdatesItem = NSMenuItem(
            title: String(localized: "Check for Updates..."),
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.keyEquivalentModifierMask = []
        checkForUpdatesItem.target = self
        let updateImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        updateImage?.isTemplate = true
        checkForUpdatesItem.image = updateImage
        checkForUpdatesItem.isEnabled = isUpdaterAvailable
        menu.addItem(checkForUpdatesItem)
        self.checkForUpdatesItem = checkForUpdatesItem

        let aboutItem = NSMenuItem(
            title: String(localized: "menu.about.title", defaultValue: "About Lingerly"),
            action: #selector(openAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.keyEquivalentModifierMask = []
        aboutItem.target = self
        let aboutImage = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        aboutImage?.isTemplate = true
        aboutItem.image = aboutImage
        menu.addItem(aboutItem)
        self.aboutItem = aboutItem

        let quitItem = NSMenuItem(
            title: String(localized: "Quit Lingerly"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: quitMenuShortcut
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = NSApp
        menu.addItem(quitItem)
        self.quitItem = quitItem

        applyFooterKeyEquivalents()
        menu.delegate = self
        statusItem.menu = menu
        self.statusItem = statusItem
        applyMenuBarStatusWidth()
    }

    /// Keeps footer keyboard equivalents in sync with the status menu items.
    private func applyFooterKeyEquivalents() {
        settingsItem?.keyEquivalent = settingsMenuShortcut
        settingsItem?.keyEquivalentModifierMask = [.command]
        checkForUpdatesItem?.keyEquivalent = ""
        checkForUpdatesItem?.keyEquivalentModifierMask = []
        aboutItem?.keyEquivalent = ""
        aboutItem?.keyEquivalentModifierMask = []
        quitItem?.keyEquivalent = quitMenuShortcut
        quitItem?.keyEquivalentModifierMask = [.command]
    }

    /// Syncs menu bar icon and menu enablement with app state.
    private func refreshStatusUI() {
        updateStatusIconImage()
        updateCountdownTitle()
    }

    /// Renders the status item icon for the current app state.
    private func updateStatusIconImage() {
        statusItem?.button?.image = appState.currentIconImage()
    }

    /// Toggles between start, pause, and resume based on current timer state.
    private func toggleStartStop() {
        if !appState.isRunning {
            appState.start()
        } else if appState.isPaused {
            appState.resumeTimer()
        } else {
            appState.pauseTimer()
        }
    }

    /// Opens the settings window from the status menu.
    @objc private func openSettings(_ sender: Any?) {
        showSettingsWindow(selecting: .general)
    }

    /// Opens Sparkle's update check window.
    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }

    /// Opens the settings window focused on the About tab.
    @objc private func openAbout(_ sender: Any?) {
        showSettingsWindow(selecting: .about)
    }

    /// Creates (if needed) and brings forward the settings window.
    private func showSettingsWindow(selecting selection: SettingsSidebarItem = .general) {
        settingsNavigationState.selection = selection

        if settingsWindow == nil {
            let hostingView = NSHostingView(
                rootView: SettingsView(appState: appState, navigationState: settingsNavigationState)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "Settings")
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbarStyle = .unifiedCompact
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            hostingView.autoresizingMask = [.width, .height]
            window.contentView = hostingView
            window.contentMinSize = NSSize(width: 360, height: 360)
            window.contentMaxSize = NSSize(width: 360, height: 360)
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let window = settingsWindow {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.centerWindow(window)
                if window.alphaValue < 1 {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.12
                        window.animator().alphaValue = 1
                    }
                }
            }
        }
    }

    /// Centers a window on the screen under the mouse, falling back to main screen.
    private func centerWindow(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? window.screen
            ?? NSScreen.main
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let windowFrame = window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - (windowFrame.width / 2),
            y: visibleFrame.midY - (windowFrame.height / 2)
        )
        window.setFrameOrigin(origin)
    }

    /// Wraps the SwiftUI menu panel in an AppKit hosting view for NSMenu embedding.
    private func makeControlPanelView() -> NSView {
        let panelView = MenuBarPanelView(model: controlPanelViewModel)
        let initialSize = NSSize(width: MenuBarPanelView.panelWidth, height: controlPanelHeight)
        let container = ControlPanelMenuContainerView(rootView: panelView, size: initialSize)
        controlPanelContainerView = container
        controlPanelViewModel.onPanelHeightChange = { [weak self] height, animated in
            self?.updateControlPanelHeight(height, animated: animated)
        }
        return container
    }

    /// Keeps the menu panel item and its menu window aligned with the selected tab height.
    private func updateControlPanelHeight(_ height: CGFloat, animated: Bool) {
        let normalizedHeight = max(height, MenuBarPanelView.defaultPanelHeight)
        let previousHeight = controlPanelHeight
        guard abs(previousHeight - normalizedHeight) > 0.5 else { return }

        controlPanelHeight = normalizedHeight

        let newSize = NSSize(width: MenuBarPanelView.panelWidth, height: normalizedHeight)
        let delta = normalizedHeight - previousHeight
        guard let container = controlPanelContainerView else { return }

        guard animated, let menuWindow = container.window else {
            applyControlPanelViewSize(newSize)
            if let menuWindow = container.window {
                var frame = menuWindow.frame
                frame.origin.y -= delta
                frame.size.height += delta
                menuWindow.setFrame(frame, display: true)
                applyControlPanelMenuWindowStyling(menuWindow)
            }
            return
        }

        var windowFrame = menuWindow.frame
        windowFrame.origin.y -= delta
        windowFrame.size.height += delta

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            container.animator().setFrameSize(newSize)
            menuWindow.animator().setFrame(windowFrame, display: true)
        } completionHandler: {
            DispatchQueue.main.async { [weak self] in
                self?.applyControlPanelViewSize(newSize)
                self?.applyControlPanelMenuWindowStyling(menuWindow)
            }
        }
    }

    /// Applies the concrete NSHostingView size after animated or immediate height changes.
    private func applyControlPanelViewSize(_ size: NSSize) {
        guard let container = controlPanelContainerView else { return }
        container.setPanelSize(size)
        controlPanelItem?.view?.needsLayout = true
    }

    /// Styles the stock NSMenu tracking window so exposed chrome matches the custom panel in both appearances.
    private func applyControlPanelMenuWindowStyling(_ menuWindow: NSWindow) {
        menuWindow.backgroundColor = controlPanelMenuBackgroundColor(for: menuWindow.effectiveAppearance)
    }

    /// Returns a subtle dynamic menu window tint that blends with the panel instead of AppKit's default strip.
    private func controlPanelMenuBackgroundColor(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return NSColor(
                red: 0.20,
                green: 0.15,
                blue: 0.26,
                alpha: 1
            )
        }

        return NSColor(
            red: 0.94,
            green: 0.90,
            blue: 0.95,
            alpha: 1
        )
    }

    /// Wires menu panel actions to app state mutations and UI refreshes.
    private func configureControlPanelCallbacks() {
        controlPanelViewModel.onToggleStartStop = { [weak self] in
            self?.toggleStartStop()
            self?.refreshStatusUI()
        }
        controlPanelViewModel.onDeferOneMinute = { [weak self] in
            self?.appState.deferNextBreak(byMinutes: 1)
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onDeferFiveMinutes = { [weak self] in
            self?.appState.deferNextBreak(byMinutes: 5)
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onDeferFifteenMinutes = { [weak self] in
            self?.appState.deferNextBreak(byMinutes: 15)
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onBringOneMinuteCloser = { [weak self] in
            self?.appState.bringNextBreakCloser(byMinutes: 1)
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onBringFiveMinutesCloser = { [weak self] in
            self?.appState.bringNextBreakCloser(byMinutes: 5)
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onBringFifteenMinutesCloser = { [weak self] in
            self?.appState.bringNextBreakCloser(byMinutes: 15)
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onToggleMutedMode = { [weak self] in
            guard let self else { return }
            self.settingsStore.mutedModeEnabled.toggle()
            self.appState.refreshMutedModeState()
            self.updateCountdownTitle()
        }
        controlPanelViewModel.onTakeBreakNow = { [weak self] in
            self?.appState.takeBreakNow()
            self?.refreshStatusUI()
        }
        controlPanelViewModel.onResetTimer = { [weak self] in
            self?.appState.resetTimer()
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onSkipBreak = { [weak self] in
            self?.appState.skipBreak()
            self?.refreshStatusUI()
        }
        controlPanelViewModel.onSetIntervalMinutes = { [weak self] value in
            self?.settingsStore.intervalMinutes = max(1, min(value, 180))
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onSetBreakDurationSeconds = { [weak self] value in
            self?.settingsStore.breakDurationSeconds = max(5, min(value, 1800))
        }
        controlPanelViewModel.onSetSnoozeMinutes = { value in
            UserDefaults.standard.set(max(1, min(value, 60)), forKey: TimingSettingsKeys.snoozeMinutes)
        }
        controlPanelViewModel.onApplyPreset = { [weak self] presetID in
            guard
                let self,
                let preset = TimingPresets.preset(for: presetID)
            else { return }
            self.settingsStore.applyPreset(preset)
            self.updateCountdownTitle()
        }
        controlPanelViewModel.onSetModeActiveEnabled = { [weak self] enabled in
            self?.settingsStore.modeActiveEnabled = enabled
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onSetModeScheduleEnabled = { [weak self] enabled in
            self?.settingsStore.modeScheduleEnabled = enabled
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onSetMenuBarTimerEnabled = { [weak self] enabled in
            self?.settingsStore.menuBarTimerEnabled = enabled
            self?.applyMenuBarStatusWidth()
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onSetMediaPauseEnabled = { [weak self] enabled in
            self?.settingsStore.mediaPauseEnabled = enabled
        }
        controlPanelViewModel.onSetResetOnUnlock = { [weak self] enabled in
            self?.settingsStore.resetOnUnlock = enabled
        }
        controlPanelViewModel.onSetLaunchAtLoginEnabled = { [weak self] enabled in
            self?.launchAtLoginController.setEnabled(enabled)
            self?.refreshStatusUI()
        }
        controlPanelViewModel.onSetSmartPauseCooldownMinutes = { [weak self] value in
            self?.settingsStore.smartPauseCooldownMinutes = value
        }
        controlPanelViewModel.onSetSmartPauseResumeBehavior = { [weak self] behavior in
            let normalized: SmartPauseResumeBehavior = (behavior == .resetTimer) ? .resetTimer : .resumeTimer
            self?.settingsStore.smartPauseResumeBehavior = normalized
            self?.updateCountdownTitle()
        }
        controlPanelViewModel.onOpenSettings = { [weak self] in
            self?.showSettingsWindow(selecting: .general)
        }
    }

    /// Copies live app/settings values into the menu panel view model.
    private func refreshControlPanelModel(statusTitle: String? = nil) {
        launchAtLoginController.refresh()
        controlPanelViewModel.isRunning = appState.isRunning
        controlPanelViewModel.isPaused = appState.isPaused
        controlPanelViewModel.intervalMinutes = settingsStore.intervalMinutes
        controlPanelViewModel.breakDurationSeconds = settingsStore.breakDurationSeconds
        controlPanelViewModel.snoozeMinutes = Self.currentSnoozeMinutes()
        controlPanelViewModel.modeActiveEnabled = settingsStore.modeActiveEnabled
        controlPanelViewModel.modeScheduleEnabled = settingsStore.modeScheduleEnabled
        controlPanelViewModel.menuBarTimerEnabled = settingsStore.menuBarTimerEnabled
        controlPanelViewModel.mediaPauseEnabled = settingsStore.mediaPauseEnabled
        controlPanelViewModel.resetOnUnlock = settingsStore.resetOnUnlock
        controlPanelViewModel.mutedModeEnabled = settingsStore.mutedModeEnabled
        controlPanelViewModel.launchAtLoginEnabled = launchAtLoginController.isEnabled
        controlPanelViewModel.smartPauseCooldownMinutes = settingsStore.smartPauseCooldownMinutes
        controlPanelViewModel.smartPauseResumeBehavior = settingsStore.smartPauseResumeBehavior
        controlPanelViewModel.selectedPresetID = selectedPresetID()

        switch appState.nextBreakDisplay(at: Date()) {
        case .inactive:
            controlPanelViewModel.statusKind = .idle
        case .paused:
            controlPanelViewModel.statusKind = .paused
        case .muted:
            controlPanelViewModel.statusKind = .muted
        case .cooldown:
            controlPanelViewModel.statusKind = .cooldown
        case .snoozing:
            controlPanelViewModel.statusKind = .snoozing
        case .breakDue:
            controlPanelViewModel.statusKind = .breakDue
        case .breakActive:
            controlPanelViewModel.statusKind = .onBreak
        case .running:
            controlPanelViewModel.statusKind = .running
        }
        if let statusTitle {
            controlPanelViewModel.statusText = statusTitle
        }
    }

    /// Returns the preset id matching the current interval/duration, or `custom`.
    private func selectedPresetID() -> String {
        let currentInterval = settingsStore.intervalMinutes
        let currentBreakSeconds = settingsStore.breakDurationSeconds
        for preset in TimingPresets.all
        where preset.intervalMinutes == currentInterval && preset.breakDurationSeconds == currentBreakSeconds {
            return preset.id
        }
        return "custom"
    }

    /// Starts a timer to keep the countdown label current.
    private func startMenuUpdateTimer() {
        guard menuUpdateTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.updateCountdownTitle()
        }
        timer.resume()
        menuUpdateTimer = timer
    }

    /// Starts or stops countdown refreshes depending on whether visible UI needs live updates.
    private func refreshMenuUpdateTimerIfNeeded() {
        if shouldKeepMenuUpdateTimerRunning {
            startMenuUpdateTimer()
        } else {
            stopMenuUpdateTimer()
        }
    }

    /// Returns true when the menu panel or menu bar title needs a live countdown.
    private var shouldKeepMenuUpdateTimerRunning: Bool {
        if isMenuOpen {
            return true
        }

        guard settingsStore.menuBarTimerEnabled, appState.isRunning else {
            return false
        }

        switch appState.nextBreakDisplay(at: Date()) {
        case .running, .muted, .snoozing, .breakActive:
            return true
        case .inactive, .paused, .cooldown, .breakDue:
            return false
        }
    }

    /// Updates countdown text for both the panel status bar and menu bar title.
    private func updateCountdownTitle() {
        let title = menuCountdownTitle(at: Date())
        refreshControlPanelModel(statusTitle: title)
        let menuBarTitle = menuBarCountdownTitle(from: title)
        updateMenuBarButtonTitle(menuBarTitle)
        refreshMenuUpdateTimerIfNeeded()
    }

    /// Builds the human-readable status line shown in the control panel.
    private func menuCountdownTitle(at date: Date) -> String {
        switch appState.nextBreakDisplay(at: date) {
        case .inactive:
            return String(localized: "Timer stopped")
        case .paused:
            let remaining = appState.pausedCountdownSeconds(at: date) ?? 0
            let countdown = AppStateController.formattedCountdown(remaining)
            let pausedTitle = String(format: String(localized: "Timer paused at %@"), countdown)
            return decorateForSmartPauseIfNeeded(pausedTitle)
        case .muted(let seconds):
            let remaining = AppStateController.formattedCountdown(seconds)
            return String(
                format: String(localized: "menu.status.muted_format", defaultValue: "Muted %@"),
                remaining
            )
        case .cooldown(let seconds):
            let remaining = AppStateController.formattedCountdown(seconds)
            let cooldownTitle = String(format: String(localized: "Cooldown %@"), remaining)
            return decorateForSmartPauseIfNeeded(cooldownTitle)
        case .snoozing(let seconds):
            let remaining = AppStateController.formattedCountdown(seconds)
            return String(format: String(localized: "Snoozing for %@"), remaining)
        case .breakDue:
            return String(localized: "Break due now")
        case .breakActive(let seconds):
            let remaining = AppStateController.formattedCountdown(seconds)
            return String(format: String(localized: "On break %@"), remaining)
        case .running(let seconds):
            let remaining = AppStateController.formattedCountdown(seconds)
            return String(format: String(localized: "Next pause in %@"), remaining)
        }
    }

    /// Prefixes status text with a smart-pause source code when active.
    private func decorateForSmartPauseIfNeeded(_ title: String) -> String {
        guard let smartPauseCode = appState.smartPauseCode() else { return title }
        return String(
            format: String(localized: "smart_pause.menu.prefix_format", defaultValue: "(%@) %@"),
            smartPauseCode,
            title
        )
    }

    /// Computes the compact menu bar timer title based on current display state.
    private func menuBarCountdownTitle(from _: String) -> String {
        let enabled = settingsStore.menuBarTimerEnabled
        guard enabled && appState.isRunning else { return "" }
        switch appState.nextBreakDisplay(at: Date()) {
        case .running(let seconds):
            return AppStateController.formattedCountdown(seconds)
        case .muted(let seconds):
            return AppStateController.formattedCountdown(seconds)
        case .snoozing(let seconds):
            return AppStateController.formattedCountdown(seconds)
        case .breakActive(let seconds):
            return AppStateController.formattedCountdown(seconds)
        case .breakDue, .paused, .cooldown, .inactive:
            return ""
        }
    }

    /// Applies fixed width when timer text is enabled to avoid menu bar jitter.
    private func applyMenuBarStatusWidth() {
        guard let statusItem else { return }
        let timerEnabled = settingsStore.menuBarTimerEnabled
        statusItem.length = timerEnabled ? menuBarTimerFixedWidth : NSStatusItem.variableLength
    }

    /// Updates the menu bar button title using monospaced digits for stability.
    private func updateMenuBarButtonTitle(_ title: String) {
        guard let button = statusItem?.button else { return }
        button.title = ""
        guard !title.isEmpty else {
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .paragraphStyle: style
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    /// Refreshes state and starts per-second updates while the menu is open.
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        controlPanelViewModel.isPanelVisible = true
        applyFooterKeyEquivalents()
        updateCountdownTitle()
        if let menuWindow = controlPanelContainerView?.window {
            applyControlPanelMenuWindowStyling(menuWindow)
        }
        refreshMenuUpdateTimerIfNeeded()
    }

    /// Refreshes the status text when the menu closes.
    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        controlPanelViewModel.isPanelVisible = false
        updateCountdownTitle()
        refreshMenuUpdateTimerIfNeeded()
    }

    /// Tears down the open-menu countdown timer if present.
    private func stopMenuUpdateTimer() {
        menuUpdateTimer?.cancel()
        menuUpdateTimer = nil
    }

    /// Maps global hotkey actions to controller commands and UI refreshes.
    private func handleHotkeyAction(_ action: GlobalHotkeyManager.Action) {
        switch action {
        case .startStop:
            toggleStartStop()
        case .resetTimer:
            appState.resetTimer()
        case .lingerALittle:
            appState.takeBreakNow()
        case .snoozePrompt:
            appState.snoozeIfBreakPromptVisible()
        }
        refreshStatusUI()
        updateCountdownTitle()
    }

    /// Reads snooze minutes from defaults with a minimum of one.
    private static func currentSnoozeMinutes() -> Int {
        let value = UserDefaults.standard.integer(forKey: TimingSettingsKeys.snoozeMinutes)
        return max(value, 1)
    }
    
    /// Validates required Sparkle feed settings before enabling update checks.
    private static func isSparkleConfigurationValid() -> Bool {
        guard
            let info = Bundle.main.infoDictionary,
            let feedURL = (info["SUFeedURL"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let publicKey = (info["SUPublicEDKey"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !feedURL.isEmpty,
            !publicKey.isEmpty,
            Data(base64Encoded: publicKey) != nil
        else {
            return false
        }
        return true
    }
}
