import AppKit

/// Coordinates the timing engine, overlays, notifications, and menu bar state.
@MainActor
final class AppStateController {
    enum State: CaseIterable {
        case idle
        case running
        case breakDue
        case breakActive
    }

    enum NextBreakDisplay: Equatable {
        case inactive
        case paused
        case snoozing(seconds: Int)
        case breakDue
        case breakActive(seconds: Int)
        case running(seconds: Int)
    }

    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle {
        didSet { handleStateTransition() }
    }

    private(set) var isRunning = false
    var isPaused: Bool { isRunning && (isManuallyPaused || isSmartPaused) }

    private let activityMonitor = ActivityMonitor()
    private let settingsStore = TimingSettingsStore()
    private lazy var engine = TimingEngine(activityMonitor: activityMonitor, configuration: loadConfiguration())
    private let mediaPlaybackMonitor = MediaPlaybackMonitor()
    private let runningAppsMonitor = RunningApplicationsMonitor()
    private let fullscreenDetector = FullscreenDetector()
    private let overlayController = BreakOverlayController()
    private let notificationManager = NotificationManager.shared
    private let statsStore = StatsStore()
    private var pendingFullscreenBreak = false
    private var isSmartPaused = false
    private var smartPauseStartedAt: Date?
    private var smartPauseCooldownTimer: Timer?
    private var isManuallyPaused = false
    private var lastUserInactiveDate: Date?
    private var isMediaConditionActive = false
    private var isAppConditionActive = false

    private var pulsePhase: CGFloat = 0
    private var pulseTimer: Timer?
    private var snoozeTimer: Timer?
    private var snoozeEndDate: Date?
    private var snoozeWasRunning = false
    private var snoozeReturnToBreak = false
    private var defaultsObserver: NSObjectProtocol?
    private var reduceMotionObserver: NSObjectProtocol?
    private var reduceMotionEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var overlayVisibilityValidationTask: Task<Void, Never>?

    /// Wires engine callbacks, notification actions, and system observers.
    init() {
        engine.onStateChange = { [weak self] engineState in
            self?.state = self?.mapState(engineState) ?? .idle
        }
        engine.onBreakCompleted = { [weak self] duration in
            self?.statsStore.recordBreakCompleted(durationSeconds: duration)
        }
        engine.shouldStartBreak = { [weak self] in
            guard let self else { return true }
            if self.shouldDeferForFullscreen() {
                if !self.pendingFullscreenBreak {
                    self.pendingFullscreenBreak = true
                    self.notificationManager.showBreakDueNotification()
                }
                return false
            }
            return true
        }

        activityMonitor.onUserActiveChange = { [weak self] isActive in
            Task { @MainActor in
                self?.handleUserActiveChange(isActive: isActive)
            }
        }

        notificationManager.onSnooze = { [weak self] in
            self?.snooze(minutes: Self.currentSnoozeMinutes())
        }
        notificationManager.onSkipRequest = { [weak self] in
            self?.notificationManager.showConfirmSkipNotification()
        }
        notificationManager.onConfirmSkip = { [weak self] in
            self?.skipBreak()
        }
        notificationManager.onCancelSkip = { }

        fullscreenDetector.onChange = { [weak self] isFullscreen in
            guard let self else { return }
            if !isFullscreen && self.pendingFullscreenBreak {
                self.pendingFullscreenBreak = false
                self.engine.attemptStartBreak()
            } else if isFullscreen && self.state == .breakActive && self.shouldDeferForFullscreen() {
                self.overlayController.hide()
                if !self.pendingFullscreenBreak {
                    self.pendingFullscreenBreak = true
                    self.notificationManager.showBreakDueNotification()
                }
            }
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.engine.updateConfiguration(self.loadConfiguration())
                self.refreshSmartPause()
            }
        }

        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reduceMotionEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                if self.reduceMotionEnabled {
                    self.stopPulse()
                } else if self.state == .breakActive {
                    self.startPulse()
                }
            }
        }

        mediaPlaybackMonitor.onChange = { [weak self] isPlaying in
            Task { @MainActor in
                self?.handleMediaPlaybackChange(isPlaying: isPlaying)
            }
        }

        runningAppsMonitor.onChange = { [weak self] runningBundleIDs in
            Task { @MainActor in
                self?.handleRunningAppsChange(runningBundleIDs: runningBundleIDs)
            }
        }
    }

    @MainActor deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = reduceMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Starts timing and transitions the app into running state.
    func start() {
        clearSnooze()
        cancelSmartPauseCooldown()
        isRunning = true
        isManuallyPaused = false
        engine.updateConfiguration(loadConfiguration())
        engine.start()
        refreshSmartPause()
        onStateChange?(state)
    }

    /// Stops timing and clears overlays/timers.
    func stop() {
        guard isRunning else { return }
        clearSnooze()
        cancelSmartPauseCooldown()
        isManuallyPaused = true
        engine.pause()
        overlayController.hide()
        isSmartPaused = false
        smartPauseStartedAt = nil
        onStateChange?(state)
    }

    /// Triggers an immediate break if the engine is running.
    func takeBreakNow() {
        guard isRunning else { return }
        engine.startBreakNow()
    }

    /// Resets the current timer cycle without stopping the app.
    func resetTimer() {
        guard isRunning else { return }
        clearSnooze()
        cancelSmartPauseCooldown()
        engine.resetCycle()
        overlayController.hide()
        onStateChange?(state)
    }

    /// Pauses the timer without resetting counters.
    func pauseTimer() {
        guard isRunning else { return }
        clearSnooze()
        cancelSmartPauseCooldown()
        isManuallyPaused = true
        engine.pause()
        onStateChange?(state)
    }

    /// Resumes the timer if it was paused.
    func resumeTimer() {
        guard isRunning else { return }
        isManuallyPaused = false
        cancelSmartPauseCooldown()
        applySmartPauseState()
        if !isSmartPaused {
            engine.resume(resetCounters: false)
        }
        onStateChange?(state)
    }

    /// Snoozes using the currently configured duration.
    func snoozeDefault() {
        snooze(minutes: Self.currentSnoozeMinutes())
    }

    /// Snoozes only when a break prompt is currently visible to the user.
    func snoozeIfBreakPromptVisible() {
        guard isBreakPromptVisible else { return }
        snoozeDefault()
    }

    /// Pauses timing for a fixed duration, then resumes if previously running.
    func snooze(minutes: Int) {
        let wasRunning = isRunning
        let durationMinutes = max(minutes, 1)
        snoozeWasRunning = wasRunning
        snoozeReturnToBreak = state == .breakActive || state == .breakDue
        snoozeEndDate = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
        statsStore.recordSnooze()
        pendingFullscreenBreak = false
        snoozeTimer?.invalidate()
        if wasRunning {
            if state == .breakActive || state == .breakDue {
                engine.skipBreak()
            }
            overlayController.hide()
            engine.pause()
        }
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(durationMinutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resumeAfterSnooze()
            }
        }
    }

    /// Skips the current or pending break and records analytics.
    func skipBreak(shouldHideOverlay: Bool = true) {
        if isRunning {
            engine.skipBreak()
        } else {
            state = .idle
        }
        statsStore.recordSkip()
        if shouldHideOverlay {
            overlayController.hide()
        }
    }

    /// Renders the menu bar icon for the current state and pulse phase.
    func currentIconImage() -> NSImage {
        let display = nextBreakDisplay()
        return StatusIconRenderer.image(nextDisplay: display, pulse: pulsePhase)
    }

    /// Returns the next break status for UI display.
    func nextBreakDisplay(at date: Date = Date()) -> NextBreakDisplay {
        guard isRunning else { return .inactive }

        if let snoozeEndDate {
            let remaining = snoozeEndDate.timeIntervalSince(date)
            if remaining > 0 {
                return .snoozing(seconds: max(Int(ceil(remaining)), 0))
            }
        }

        if state == .breakActive {
            let remaining = engine.breakRemainingSeconds(at: date) ?? 0
            return .breakActive(seconds: remaining)
        }

        if state == .breakDue {
            return .breakDue
        }

        if isManuallyPaused || isSmartPaused {
            return .paused
        }

        let remaining = engine.timeUntilNextBreak(at: date) ?? 0
        return .running(seconds: remaining)
    }

    /// Formats a seconds count as mm:ss or h:mm:ss.
    static func formattedCountdown(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Returns the paused countdown value shown in menu context, if available.
    func pausedCountdownSeconds(at date: Date = Date()) -> Int? {
        guard isRunning, isPaused else { return nil }
        return engine.timeUntilNextBreak(at: date)
    }

    /// Runs side effects when the engine state changes.
    private func handleStateTransition() {
        switch state {
        case .idle, .running, .breakDue:
            overlayVisibilityValidationTask?.cancel()
            overlayVisibilityValidationTask = nil
            stopPulse()
            overlayController.hide()
        case .breakActive:
            startPulse()
            if !shouldDeferForFullscreen() {
                let breakDuration = TimeInterval(max(settingsStore.breakDurationSeconds, 5))
                overlayController.show(
                    allowLockScreen: isLockScreenAllowed(),
                    breakDuration: breakDuration,
                    onLockScreen: { [weak self] in
                        self?.lockScreenRequested()
                    },
                    onSnooze: { [weak self] in
                        self?.snooze(minutes: Self.currentSnoozeMinutes())
                    },
                    onSkipHold: { [weak self] in
                        self?.skipBreak(shouldHideOverlay: false)
                    }
                )
                scheduleFullscreenOverlayFallbackIfSuppressed()
            }
        }
        onStateChange?(state)
    }

    /// Falls back to a due notification when fullscreen overlay rendering is suppressed by the system.
    private func scheduleFullscreenOverlayFallbackIfSuppressed() {
        overlayVisibilityValidationTask?.cancel()
        overlayVisibilityValidationTask = nil
        guard fullscreenDetector.isFullscreen else { return }

        overlayVisibilityValidationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                guard let self else { return }
                guard self.state == .breakActive else { return }
                guard self.fullscreenDetector.isFullscreen else { return }
                guard !self.shouldDeferForFullscreen() else { return }
                guard !self.overlayController.isLikelyVisible else { return }

                self.overlayController.hide(animated: false)
                self.engine.deferActiveBreakAsDue()
                self.pendingFullscreenBreak = true
                self.notificationManager.showBreakDueNotification()
            }
        }
    }

    /// Updates media playback pause condition.
    private func handleMediaPlaybackChange(isPlaying: Bool) {
        isMediaConditionActive = settingsStore.mediaPauseEnabled && isPlaying
        applySmartPauseState()
    }

    /// Updates app-based pause condition from the running app set.
    private func handleRunningAppsChange(runningBundleIDs: Set<String>) {
        guard settingsStore.pauseForAppsEnabled else {
            isAppConditionActive = false
            applySmartPauseState()
            return
        }

        let trackedIDs = Set(settingsStore.pauseForAppsRules.map { $0.bundleIdentifier.lowercased() })
        isAppConditionActive = !trackedIDs.isEmpty && !trackedIDs.isDisjoint(with: runningBundleIDs)
        applySmartPauseState()
    }

    private func handleUserActiveChange(isActive: Bool) {
        if isActive {
            let inactiveDuration = lastUserInactiveDate.map { Date().timeIntervalSince($0) }
            lastUserInactiveDate = nil

            guard isRunning else { return }

            if settingsStore.resetOnUnlock {
                resetTimer()
                return
            }

            guard let inactiveDuration else { return }
            let threshold = TimeInterval(max(settingsStore.intervalMinutes, 1) * 60)
            guard inactiveDuration <= threshold else { return }
            engine.applyUnlockGrace(seconds: 120)
        } else {
            lastUserInactiveDate = Date()
        }
    }

    /// Re-evaluates smart pause behavior after settings changes.
    private func refreshSmartPause() {
        handleMediaPlaybackChange(isPlaying: mediaPlaybackMonitor.isPlaying)
        handleRunningAppsChange(runningBundleIDs: runningAppsMonitor.runningBundleIdentifiers)
    }

    private func applySmartPauseState() {
        let shouldPause = isMediaConditionActive || isAppConditionActive
        if shouldPause {
            cancelSmartPauseCooldown()
            guard isRunning, state == .running, !isManuallyPaused, !isSmartPaused else { return }
            engine.pause()
            isSmartPaused = true
            smartPauseStartedAt = Date()
            return
        }

        if isManuallyPaused {
            cancelSmartPauseCooldown()
            isSmartPaused = false
            smartPauseStartedAt = nil
            return
        }

        guard isRunning, state == .running, isSmartPaused else { return }
        guard smartPauseCooldownTimer == nil else { return }
        let cooldownSeconds = TimeInterval(max(settingsStore.smartPauseCooldownMinutes, 1) * 60)
        smartPauseCooldownTimer = Timer.scheduledTimer(withTimeInterval: cooldownSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resumeFromSmartPauseAfterCooldown()
            }
        }
    }

    private func resumeAfterSnooze() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        let shouldResume = snoozeWasRunning
        let shouldStartBreak = snoozeReturnToBreak
        snoozeWasRunning = false
        snoozeReturnToBreak = false
        snoozeEndDate = nil

        guard shouldResume else { return }

        applySmartPauseState()
        if isSmartPaused || isManuallyPaused {
            return
        }

        engine.resume(resetCounters: false)

        guard shouldStartBreak else { return }
        if shouldDeferForFullscreen() {
            pendingFullscreenBreak = true
            notificationManager.showBreakDueNotification()
            engine.markBreakDue()
        } else {
            engine.startBreakNow()
        }
    }

    private func clearSnooze() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        snoozeEndDate = nil
        snoozeWasRunning = false
        snoozeReturnToBreak = false
    }

    private func cancelSmartPauseCooldown() {
        smartPauseCooldownTimer?.invalidate()
        smartPauseCooldownTimer = nil
    }

    private func resumeFromSmartPauseAfterCooldown() {
        cancelSmartPauseCooldown()
        guard isRunning, state == .running, isSmartPaused, !isManuallyPaused else { return }
        guard !isMediaConditionActive, !isAppConditionActive else { return }

        let pausedDuration = Date().timeIntervalSince(smartPauseStartedAt ?? Date())
        let behavior = settingsStore.smartPauseResumeBehavior
        if behavior == .countDownDuringPause {
            engine.advance(by: pausedDuration)
        }
        engine.resume(resetCounters: behavior == .resetTimer)
        isSmartPaused = false
        smartPauseStartedAt = nil
    }

    /// Starts a subtle pulse for the menu bar icon during active breaks.
    private func startPulse() {
        guard !reduceMotionEnabled else { return }
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pulsePhase = self.pulsePhase == 0 ? 1 : 0
                self.onStateChange?(self.state)
            }
        }
    }

    /// Stops the menu bar icon pulse and resets its phase.
    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulsePhase = 0
    }

    /// Maps the timing engine state to the UI state enum.
    private func mapState(_ engineState: TimingEngine.State) -> State {
        switch engineState {
        case .idle:
            return .idle
        case .running:
            return .running
        case .breakDue:
            return .breakDue
        case .breakActive:
            return .breakActive
        }
    }

    /// Determines whether breaks should be deferred while fullscreen apps are active.
    private func shouldDeferForFullscreen() -> Bool {
        let behaviorRaw = UserDefaults.standard.string(forKey: OnboardingKeys.fullscreenBehavior) ?? FullscreenBehavior.notify.rawValue
        let behavior = FullscreenBehavior(rawValue: behaviorRaw) ?? .notify
        if behavior == .interrupt { return false }
        return fullscreenDetector.isFullscreen
    }

    /// Checks onboarding settings to see if lock screen enforcement is enabled.
    private func isLockScreenAllowed() -> Bool {
        let styleRaw = UserDefaults.standard.string(forKey: OnboardingKeys.enforcementStyle) ?? EnforcementStyle.gentle.rawValue
        let style = EnforcementStyle(rawValue: styleRaw) ?? .gentle
        if style != .firm { return false }
        return UserDefaults.standard.bool(forKey: OnboardingKeys.allowLockScreen)
    }

    /// Locks the screen if the current policy allows it.
    private func lockScreenRequested() {
        guard isLockScreenAllowed() else { return }
        LockScreenController.lockScreen()
    }

    /// Builds a fresh timing configuration from persisted settings.
    private func loadConfiguration() -> TimingEngine.Configuration {
        TimingEngine.Configuration(
            intervalMinutes: settingsStore.intervalMinutes,
            breakDurationSeconds: settingsStore.breakDurationSeconds,
            modes: settingsStore.timingModes(),
            scheduleTimes: settingsStore.scheduleTimes
        )
    }

    /// Reads the current snooze duration from user defaults with a safe minimum.
    private static func currentSnoozeMinutes() -> Int {
        let value = UserDefaults.standard.integer(forKey: TimingSettingsKeys.snoozeMinutes)
        return max(value, 1)
    }

    private var isBreakPromptVisible: Bool {
        state == .breakDue || state == .breakActive || pendingFullscreenBreak
    }
}
