import AppKit
import Sparkle
import SwiftUI

/// Borderless non-activating panel that can still become the key window for keyboard routing.
private final class ControlPanelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Manages lifecycle, menu bar UI, and top-level windows for the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var footerMenu: NSMenu?
    private var controlPanelPanel: ControlPanelPanel?
    private var panelHostingView: NSHostingView<MenuBarPanelView>?
    private var panelEventMonitor: Any?
    private var panelKeyMonitor: Any?
    private var lastPanelHideDate = Date.distantPast
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

    /// Builds the status item, footer menu, and control-panel panel.
    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Footer menu — shown on right-click (Settings / Updates / About / Quit)
        let menu = NSMenu()
        menu.showsStateColumn = false
        menu.delegate = self

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

        footerMenu = menu

        // Left-click shows the control-panel panel; right-click shows the footer menu.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusBarButtonClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseDown])

        controlPanelPanel = makeControlPanelPanel()
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

    /// Handles status bar button clicks: left-click toggles the panel, right-click shows the footer menu.
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseDown {
            if let menu = footerMenu {
                applyFooterKeyEquivalents()
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
            }
        } else {
            if controlPanelViewModel.isPanelVisible {
                hideControlPanelPanel()
            } else {
                showControlPanelPanel()
            }
        }
    }

    /// Builds the floating panel that hosts the aurora control panel.
    private func makeControlPanelPanel() -> ControlPanelPanel {
        let width = MenuBarPanelView.panelWidth
        let panel = ControlPanelPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: controlPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // NSVisualEffectView provides the vibrancy backdrop that .withinWindow GlassMaterialViews sample from.
        let vibrancy = NSVisualEffectView()
        vibrancy.material = .popover
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        panel.contentView = vibrancy
        // Set layer properties after the view enters the window hierarchy so the layer is stable.
        vibrancy.layer?.cornerRadius = 16
        vibrancy.layer?.cornerCurve = .continuous
        vibrancy.layer?.masksToBounds = true

        // Hosting view is a subview OF vibrancy — not a sibling — so .withinWindow compositing works correctly.
        configureControlPanelCallbacks()
        let panelView = MenuBarPanelView(model: controlPanelViewModel)
        let hostingView = NSHostingView(rootView: panelView)
        hostingView.frame = vibrancy.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        vibrancy.addSubview(hostingView)
        panelHostingView = hostingView

        controlPanelViewModel.onPanelHeightChange = { [weak self, weak panel] height, animated in
            self?.resizeControlPanelPanel(panel, height: height, animated: animated)
        }
        return panel
    }

    /// Positions and shows the control-panel panel below the status bar button.
    private func showControlPanelPanel() {
        guard Date().timeIntervalSince(lastPanelHideDate) > 0.15 else { return }
        guard let panel = controlPanelPanel,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        refreshControlPanelModel()
        updateCountdownTitle()

        let fullWidth = MenuBarPanelView.panelWidth
        let fullHeight = controlPanelHeight
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonRect.midX - fullWidth / 2
        let y = buttonRect.minY - fullHeight - 4

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonRect.origin) }) ?? NSScreen.main {
            x = max(screen.visibleFrame.minX + 4, min(x, screen.visibleFrame.maxX - fullWidth - 4))
        }

        // Full destination frame
        let fullFrame = NSRect(x: x, y: y, width: fullWidth, height: fullHeight)
        // Starting frame: 92% scale with top edge (maxY) pinned to the menu bar button
        let scale: CGFloat = 0.92
        let startFrame = NSRect(
            x: fullFrame.midX - fullWidth * scale / 2,
            y: fullFrame.maxY - fullHeight * scale,
            width: fullWidth * scale,
            height: fullHeight * scale
        )
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        // makeKeyAndOrderFront makes the panel the key window (receives keyboard events)
        // without activating the app, because the panel has .nonactivatingPanel style.
        panel.makeKeyAndOrderFront(nil)
        controlPanelViewModel.isPanelVisible = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(fullFrame, display: true)
        }
        refreshMenuUpdateTimerIfNeeded()

        // Dismiss when clicking outside the panel (global = events in other processes).
        panelEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hideControlPanelPanel()
        }

        // Route Cmd+,, Cmd+Q, and Escape through the panel (local = no Accessibility permission needed).
        panelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let cmdOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            if cmdOnly {
                switch event.charactersIgnoringModifiers {
                case self.settingsMenuShortcut:
                    self.showSettingsWindow(selecting: .general)
                    self.hideControlPanelPanel()
                    return nil
                case self.quitMenuShortcut:
                    NSApp.terminate(nil)
                    return nil
                default:
                    break
                }
            }
            if event.keyCode == 53 { // Escape
                self.hideControlPanelPanel()
                return nil
            }
            return event
        }
    }

    /// Hides the control-panel panel and tears down all event monitors.
    private func hideControlPanelPanel() {
        guard let panel = controlPanelPanel, panel.alphaValue > 0 else { return }
        let fullFrame = panel.frame  // captured while panel is still at full size

        controlPanelViewModel.isPanelVisible = false
        lastPanelHideDate = Date()
        refreshMenuUpdateTimerIfNeeded()
        // Remove monitors synchronously so no further events fire during the animation.
        if let monitor = panelEventMonitor { NSEvent.removeMonitor(monitor); panelEventMonitor = nil }
        if let monitor = panelKeyMonitor   { NSEvent.removeMonitor(monitor); panelKeyMonitor = nil }

        let scale: CGFloat = 0.92
        let collapseFrame = NSRect(
            x: fullFrame.midX - fullFrame.width * scale / 2,
            y: fullFrame.maxY - fullFrame.height * scale,
            width: fullFrame.width * scale,
            height: fullFrame.height * scale
        )
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(collapseFrame, display: true)
        }, completionHandler: {
            Task { @MainActor [weak panel] in
                panel?.orderOut(nil)
                panel?.setFrame(fullFrame, display: false)  // restore for next open
                panel?.alphaValue = 1
            }
        })
    }

    /// Resizes the control-panel panel when the SwiftUI view reports a tab-height change.
    private func resizeControlPanelPanel(_ panel: NSPanel?, height: CGFloat, animated: Bool) {
        guard let panel else { return }
        let normalizedHeight = max(height, MenuBarPanelView.defaultPanelHeight)
        let previousHeight = controlPanelHeight
        guard abs(previousHeight - normalizedHeight) > 0.5 else { return }
        controlPanelHeight = normalizedHeight

        let delta = normalizedHeight - previousHeight
        var newFrame = panel.frame
        newFrame.origin.y -= delta
        newFrame.size.height = normalizedHeight

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
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

    /// Returns true when the control panel, footer menu, or menu bar title needs a live countdown.
    private var shouldKeepMenuUpdateTimerRunning: Bool {
        if controlPanelViewModel.isPanelVisible || isMenuOpen {
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

    /// Refreshes key equivalents and countdown while the footer menu is open.
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        applyFooterKeyEquivalents()
        updateCountdownTitle()
        refreshMenuUpdateTimerIfNeeded()
    }

    /// Cleans up after the footer menu closes.
    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
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
