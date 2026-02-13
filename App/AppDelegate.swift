import AppKit
import Sparkle
import SwiftUI

/// Manages lifecycle, menu bar UI, and top-level windows for the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private lazy var updaterController: SPUStandardUpdaterController? = {
        guard Self.isSparkleConfigurationValid() else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()
    let appState = AppStateController()
    private var startStopItem: NSMenuItem?
    private var countdownItem: NSMenuItem?
    private var countdownLabel: NSTextField?
    private var takeBreakNowItem: NSMenuItem?
    private var resetTimerItem: NSMenuItem?
    private var settingsItem: NSMenuItem?
    private var checkForUpdatesItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var menuUpdateTimer: DispatchSourceTimer?
    private var isMenuOpen = false
    
    var isUpdaterAvailable: Bool {
        updaterController != nil
    }

    /// Boots the menu bar UI and starts the timing engine.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        appState.onStateChange = { [weak self] _ in
            self?.refreshStatusUI()
        }
        appState.start()
        refreshStatusUI()
        startMenuUpdateTimer()
        showOnboardingIfNeeded()
    }

    /// Keep the menu bar app alive when settings/onboarding windows close.
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

        let startStopItem = NSMenuItem(
            title: String(localized: "Start"),
            action: #selector(handleStartStop(_:)),
            keyEquivalent: ""
        )
        startStopItem.target = self
        menu.addItem(startStopItem)
        self.startStopItem = startStopItem

        let countdownItem = NSMenuItem(
            title: String(localized: "Timer stopped"),
            action: nil,
            keyEquivalent: ""
        )
        countdownItem.isEnabled = false
        countdownItem.view = makeCountdownView(initialTitle: countdownItem.title)
        menu.addItem(countdownItem)
        self.countdownItem = countdownItem

        let takeBreakNowItem = NSMenuItem(
            title: String(localized: "Overlay Title"),
            action: #selector(handleTakeBreakNow(_:)),
            keyEquivalent: ""
        )
        takeBreakNowItem.target = self
        menu.addItem(takeBreakNowItem)
        self.takeBreakNowItem = takeBreakNowItem

        let resetTimerItem = NSMenuItem(
            title: String(localized: "Reset Timer"),
            action: #selector(handleResetTimer(_:)),
            keyEquivalent: ""
        )
        resetTimerItem.target = self
        menu.addItem(resetTimerItem)
        self.resetTimerItem = resetTimerItem

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings..."),
            action: #selector(openSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.keyEquivalentModifierMask = []
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

        let quitItem = NSMenuItem(
            title: String(localized: "Quit Lingerly"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quitItem.keyEquivalentModifierMask = []
        quitItem.target = NSApp
        menu.addItem(quitItem)
        self.quitItem = quitItem

        menu.delegate = self
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func clearFooterKeyEquivalents() {
        settingsItem?.keyEquivalent = ""
        settingsItem?.keyEquivalentModifierMask = []
        checkForUpdatesItem?.keyEquivalent = ""
        checkForUpdatesItem?.keyEquivalentModifierMask = []
        quitItem?.keyEquivalent = ""
        quitItem?.keyEquivalentModifierMask = []
    }

    /// Syncs menu bar icon and menu enablement with app state.
    private func refreshStatusUI() {
        guard let button = statusItem?.button else { return }
        button.image = appState.currentIconImage()
        updateStartStopTitle()
        updateCountdownTitle()
        let isRunning = appState.isRunning
        takeBreakNowItem?.isEnabled = isRunning
        resetTimerItem?.isEnabled = isRunning
    }

    /// Updates the menu title for Start/Stop based on run state.
    private func updateStartStopTitle() {
        let title = (!appState.isRunning || appState.isPaused) ? String(localized: "Start") : String(localized: "Stop")
        startStopItem?.title = title
    }

    /// Toggles the timing engine on/off from the status menu.
    @objc private func handleStartStop(_ sender: Any?) {
        if !appState.isRunning {
            appState.start()
        } else if appState.isPaused {
            appState.resumeTimer()
        } else {
            appState.pauseTimer()
        }
    }

    /// Forces an immediate break, bypassing the normal schedule.
    @objc private func handleTakeBreakNow(_ sender: Any?) {
        appState.takeBreakNow()
    }

    /// Resets the timer countdown from the status menu.
    @objc private func handleResetTimer(_ sender: Any?) {
        appState.resetTimer()
        updateCountdownTitle()
    }

    /// Opens the settings window from the status menu.
    @objc private func openSettings(_ sender: Any?) {
        showSettingsWindow()
    }

    /// Opens Sparkle's update check window.
    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }

    /// Terminates the app.
    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    /// Creates (if needed) and brings forward the settings window.
    private func showSettingsWindow() {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: SettingsView(appState: appState))
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

    /// Starts a timer to keep the countdown label current.
    private func startMenuUpdateTimer() {
        stopMenuUpdateTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.updateCountdownTitle()
        }
        timer.resume()
        menuUpdateTimer = timer
    }

    /// Updates the countdown label in the status menu.
    private func updateCountdownTitle() {
        let title = menuCountdownTitle(at: Date())
        if isMenuOpen {
            countdownItem?.title = title
            countdownLabel?.stringValue = title
            if let item = countdownItem {
                statusItem?.menu?.itemChanged(item)
            }
        }
        statusItem?.button?.title = menuBarCountdownTitle(from: title)
        statusItem?.button?.image = appState.currentIconImage()
        updateStartStopTitle()
    }

    private func menuCountdownTitle(at date: Date) -> String {
        switch appState.nextBreakDisplay(at: date) {
        case .inactive:
            return String(localized: "Timer stopped")
        case .paused:
            let remaining = appState.pausedCountdownSeconds(at: date) ?? 0
            let countdown = AppStateController.formattedCountdown(remaining)
            return String(format: String(localized: "Timer paused at %@"), countdown)
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

    private func menuBarCountdownTitle(from menuTitle: String) -> String {
        let enabled = UserDefaults.standard.bool(forKey: TimingSettingsKeys.menuBarTimerEnabled)
        guard enabled && appState.isRunning else { return "" }
        switch appState.nextBreakDisplay(at: Date()) {
        case .running(let seconds):
            return AppStateController.formattedCountdown(seconds)
        case .snoozing(let seconds):
            return AppStateController.formattedCountdown(seconds)
        case .breakActive(let seconds):
            return AppStateController.formattedCountdown(seconds)
        case .breakDue, .paused, .inactive:
            return ""
        }
    }

    private func makeCountdownView(initialTitle: String) -> NSView {
        let label = NSTextField(labelWithString: initialTitle)
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 22)
        ])
        countdownLabel = label
        return container
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        clearFooterKeyEquivalents()
        updateCountdownTitle()
        startMenuUpdateTimer()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        updateCountdownTitle()
    }

    private func stopMenuUpdateTimer() {
        menuUpdateTimer?.cancel()
        menuUpdateTimer = nil
    }
    
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
