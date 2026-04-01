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
        case muted(seconds: Int)
        case cooldown(seconds: Int)
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
    private var smartPauseCooldownEndDate: Date?
    private var isManuallyPaused = false
    private var lastUserInactiveDate: Date?
    private var isMediaConditionActive = false
    private var isAppConditionActive = false
    private var isScheduleConditionActive = false

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
    private var smartPauseScheduleTimer: Timer?
    private var lastMediaPauseEnabled: Bool
    private var lastPauseForAppsEnabled: Bool
    private var lastPauseForAppsRules: [PauseAppRule]
    private var lastSchedulePauseEnabled: Bool

    /// Wires engine callbacks, notification actions, and system observers.
    init() {
        Self.migrateLegacyFullscreenBehaviorValueIfNeeded()
        lastMediaPauseEnabled = settingsStore.mediaPauseEnabled
        lastPauseForAppsEnabled = settingsStore.pauseForAppsEnabled
        lastPauseForAppsRules = settingsStore.pauseForAppsRules
        lastSchedulePauseEnabled = settingsStore.smartPauseScheduleEnabled

        engine.onStateChange = { [weak self] engineState in
            guard let self else { return }
            if self.settingsStore.mutedModeEnabled, engineState == .breakDue || engineState == .breakActive {
                self.pendingFullscreenBreak = false
                self.overlayController.hide()
                self.notificationManager.clearBreakNotifications()
                self.engine.skipBreak()
                return
            }
            self.state = self.mapState(engineState)
        }
        engine.onBreakCompleted = { [weak self] duration in
            self?.statsStore.recordBreakCompleted(durationSeconds: duration)
        }
        engine.shouldStartBreak = { [weak self] in
            guard let self else { return true }
            if self.shouldAlwaysNotifyOnly() {
                self.pendingFullscreenBreak = true
                self.notificationManager.showBreakDueNotification()
                return false
            }
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
                if self.shouldAlwaysNotifyOnly() {
                    return
                }
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
                self.refreshSmartPauseAfterSettingsChange()
                self.refreshMutedModeState()
                if self.pendingFullscreenBreak && !self.shouldAlwaysNotifyOnly() && !self.shouldDeferForFullscreen() {
                    self.pendingFullscreenBreak = false
                    self.engine.attemptStartBreak()
                }
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

        refreshSmartPauseMonitoring()
    }

    @MainActor deinit {
        smartPauseScheduleTimer?.invalidate()
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

    /// Sets the tick interval on the underlying engine (e.g., 1s for foreground, 5s for background).
    func setTickInterval(_ interval: TimeInterval) {
        engine.tickInterval = interval
    }

    /// Stops timing and clears overlays/timers.
    func stop() {
        guard isRunning else { return }
        clearSnooze()
        cancelSmartPauseCooldown()
        stopSmartPauseScheduleTimer()
        isManuallyPaused = true
        engine.pause()
        overlayController.hide()
        isSmartPaused = false
        smartPauseStartedAt = nil
        refreshSmartPauseMonitoring()
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

    /// Delays the next break by the provided number of minutes.
    func deferNextBreak(byMinutes minutes: Int) {
        guard isRunning, state == .running else { return }
        let seconds = max(minutes, 0) * 60
        guard seconds > 0 else { return }
        engine.applyUnlockGrace(seconds: seconds)
        onStateChange?(state)
    }

    /// Brings the next break closer by the provided number of minutes.
    func bringNextBreakCloser(byMinutes minutes: Int) {
        guard isRunning, state == .running else { return }
        let seconds = TimeInterval(max(minutes, 0) * 60)
        guard seconds > 0 else { return }
        engine.advance(by: seconds)
        onStateChange?(state)
    }

    /// Pauses the timer without resetting counters.
    func pauseTimer() {
        guard isRunning else { return }
        clearSnooze()
        cancelSmartPauseCooldown()
        stopSmartPauseScheduleTimer()
        isManuallyPaused = true
        engine.pause()
        refreshSmartPauseMonitoring()
        onStateChange?(state)
    }

    /// Resumes the timer if it was paused.
    func resumeTimer() {
        guard isRunning else { return }
        isManuallyPaused = false
        refreshSmartPauseMonitoring()
        if canResumeImmediatelyFromSmartPauseCooldown {
            resumeImmediatelyFromSmartPauseCooldown()
            onStateChange?(state)
            return
        }
        cancelSmartPauseCooldown()
        applySmartPauseState()
        if !isSmartPaused {
            engine.resume(resetCounters: false)
        }
        onStateChange?(state)
    }

    /// Applies muted mode immediately when the toggle changes.
    func refreshMutedModeState() {
        guard settingsStore.mutedModeEnabled else { return }
        let hadPendingFullscreenBreak = pendingFullscreenBreak
        pendingFullscreenBreak = false
        overlayController.hide()
        notificationManager.clearBreakNotifications()
        if hadPendingFullscreenBreak || state == .breakDue || state == .breakActive {
            engine.skipBreak()
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
            refreshSmartPauseMonitoring()
        }
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(durationMinutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resumeAfterSnooze()
            }
        }
    }

    /// Skips the current or pending break and records analytics.
    func skipBreak(shouldHideOverlay: Bool = true) {
        pendingFullscreenBreak = false
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

        if isManuallyPaused {
            return .paused
        }

        if isSmartPaused, let cooldownRemaining = smartPauseCooldownRemainingSeconds(at: date), cooldownRemaining > 0 {
            return .cooldown(seconds: cooldownRemaining)
        }

        if isSmartPaused {
            return .paused
        }

        let remaining = engine.timeUntilNextBreak(at: date) ?? 0
        if settingsStore.mutedModeEnabled {
            return .muted(seconds: remaining)
        }
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

    /// Returns a short smart-pause code for UI labels, for example "PM" or "PS".
    /// Falls back to the base auto-pause code while cooldown is active.
    func smartPauseCode() -> String? {
        guard isRunning, isSmartPaused else { return nil }

        let baseCode = String(localized: "smart_pause.code.base", defaultValue: "P")
        let mediaCode = String(localized: "smart_pause.code.media", defaultValue: "M")
        let appsCode = String(localized: "smart_pause.code.apps", defaultValue: "X")
        let scheduleCode = String(localized: "smart_pause.code.schedule", defaultValue: "S")

        var reasons = ""
        if isMediaConditionActive { reasons += mediaCode }
        if isAppConditionActive { reasons += appsCode }
        if isScheduleConditionActive { reasons += scheduleCode }

        return baseCode + reasons
    }

    /// Runs side effects when the engine state changes.
    private func handleStateTransition() {
        refreshSmartPauseMonitoring()
        switch state {
        case .idle, .running, .breakDue:
            overlayVisibilityValidationTask?.cancel()
            overlayVisibilityValidationTask = nil
            stopPulse()
            overlayController.hide()
        case .breakActive:
            startPulse()
            if shouldAlwaysNotifyOnly() {
                NSLog("Lingerly break routing: notification-only mode active")
                pendingFullscreenBreak = true
                notificationManager.showBreakDueNotification()
                engine.deferActiveBreakAsDue()
                return
            }
            if !shouldDeferForFullscreen() {
                NSLog("Lingerly break routing: presenting fullscreen overlay")
                let startedWhileFullscreen = fullscreenDetector.isFullscreen
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
                scheduleFullscreenOverlayFallbackIfSuppressed(startedWhileFullscreen: startedWhileFullscreen)
            }
        }
        onStateChange?(state)
    }

    /// Falls back to a due notification when fullscreen overlay rendering is suppressed by the system.
    private func scheduleFullscreenOverlayFallbackIfSuppressed(startedWhileFullscreen: Bool) {
        overlayVisibilityValidationTask?.cancel()
        overlayVisibilityValidationTask = nil
        guard startedWhileFullscreen else { return }

        overlayVisibilityValidationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                guard let self else { return }
                guard self.state == .breakActive else { return }
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

    /// Applies unlock behavior when the user returns after inactivity.
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

    /// Re-evaluates all smart-pause sources from current runtime state.
    private func refreshSmartPause() {
        refreshSmartPauseMonitoring()
        applySmartPauseState()
    }

    /// Re-evaluates smart pause after defaults changes.
    private func refreshSmartPauseAfterSettingsChange() {
        let previousMediaConditionActive = isMediaConditionActive
        let previousAppConditionActive = isAppConditionActive
        let previousScheduleConditionActive = isScheduleConditionActive

        let newMediaPauseEnabled = settingsStore.mediaPauseEnabled
        let newPauseForAppsEnabled = settingsStore.pauseForAppsEnabled
        let newPauseForAppsRules = settingsStore.pauseForAppsRules
        let newSchedulePauseEnabled = settingsStore.smartPauseScheduleEnabled
        let newSchedulePausePeriods = settingsStore.smartPauseSchedulePeriods
        let runningBundleIDs = runningAppsMonitor.runningBundleIdentifiers
        let previousTrackedAppIDs = Set(lastPauseForAppsRules.map { $0.bundleIdentifier.lowercased() })
        let newTrackedAppIDs = Set(newPauseForAppsRules.map { $0.bundleIdentifier.lowercased() })
        let appRulesChanged = previousTrackedAppIDs != newTrackedAppIDs

        let mediaSourceDisabledWhileActive = previousMediaConditionActive && lastMediaPauseEnabled && !newMediaPauseEnabled
        let appSourceDisabledWhileActive = previousAppConditionActive && (
            (lastPauseForAppsEnabled && !newPauseForAppsEnabled) ||
            (appRulesChanged && !appConditionIsActive(
                runningBundleIDs: runningBundleIDs,
                pauseForAppsEnabled: newPauseForAppsEnabled,
                pauseForAppsRules: newPauseForAppsRules
            ))
        )
        let scheduleSourceDisabledWhileActive = previousScheduleConditionActive && (
            (lastSchedulePauseEnabled && !newSchedulePauseEnabled) ||
            (newSchedulePauseEnabled && smartPauseTriggeredBySchedule(at: Date(), periods: newSchedulePausePeriods) == false)
        )
        let shouldBypassCooldown = mediaSourceDisabledWhileActive || appSourceDisabledWhileActive || scheduleSourceDisabledWhileActive

        lastMediaPauseEnabled = newMediaPauseEnabled
        lastPauseForAppsEnabled = newPauseForAppsEnabled
        lastPauseForAppsRules = newPauseForAppsRules
        lastSchedulePauseEnabled = newSchedulePauseEnabled
        refreshSmartPauseMonitoring()

        applySmartPauseState(bypassCooldownIfConditionsCleared: shouldBypassCooldown)
    }

    /// Enables smart-pause monitors only while they can affect the current runtime state.
    private func refreshSmartPauseMonitoring(at date: Date = Date()) {
        let shouldObserveMedia = shouldObserveSmartPauseSources && settingsStore.mediaPauseEnabled
        mediaPlaybackMonitor.setMonitoringEnabled(shouldObserveMedia)
        isMediaConditionActive = shouldObserveMedia && mediaPlaybackMonitor.isPlaying

        let shouldObserveApps = shouldObserveSmartPauseSources
            && settingsStore.pauseForAppsEnabled
            && !settingsStore.pauseForAppsRules.isEmpty
        runningAppsMonitor.setMonitoringEnabled(shouldObserveApps)
        isAppConditionActive = shouldObserveApps && appConditionIsActive(
            runningBundleIDs: runningAppsMonitor.runningBundleIdentifiers,
            pauseForAppsEnabled: settingsStore.pauseForAppsEnabled,
            pauseForAppsRules: settingsStore.pauseForAppsRules
        )

        if shouldObserveSmartPauseSources {
            refreshSmartPauseScheduleSource(at: date)
        } else {
            stopSmartPauseScheduleTimer()
            isScheduleConditionActive = false
            lastSchedulePauseEnabled = settingsStore.smartPauseScheduleEnabled
        }
    }

    /// True when smart-pause sources can currently influence timing.
    private var shouldObserveSmartPauseSources: Bool {
        isRunning && state == .running && !isManuallyPaused && snoozeEndDate == nil
    }

    /// Pauses/resumes the engine according to current smart-pause sources.
    private func applySmartPauseState(bypassCooldownIfConditionsCleared: Bool = false) {
        let shouldPause = isMediaConditionActive || isAppConditionActive || isScheduleConditionActive
        if shouldPause {
            cancelSmartPauseCooldown()
            guard isRunning, state == .running, !isManuallyPaused, !isSmartPaused else { return }
            engine.pause()
            isSmartPaused = true
            smartPauseStartedAt = Date()
            onStateChange?(state)
            return
        }

        if isManuallyPaused {
            cancelSmartPauseCooldown()
            isSmartPaused = false
            smartPauseStartedAt = nil
            return
        }

        guard isRunning, state == .running, isSmartPaused else { return }
        if bypassCooldownIfConditionsCleared {
            resumeFromSmartPauseAfterCooldown()
            return
        }
        guard smartPauseCooldownTimer == nil else { return }
        let cooldownSeconds = TimeInterval(max(settingsStore.smartPauseCooldownMinutes, 1) * 60)
        smartPauseCooldownEndDate = Date().addingTimeInterval(cooldownSeconds)
        smartPauseCooldownTimer = Timer.scheduledTimer(withTimeInterval: cooldownSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resumeFromSmartPauseAfterCooldown()
            }
        }
        onStateChange?(state)
    }

    /// Returns true when any configured tracked app is currently running.
    private func appConditionIsActive(
        runningBundleIDs: Set<String>,
        pauseForAppsEnabled: Bool,
        pauseForAppsRules: [PauseAppRule]
    ) -> Bool {
        guard pauseForAppsEnabled else { return false }
        let trackedIDs = Set(pauseForAppsRules.map { $0.bundleIdentifier.lowercased() })
        return !trackedIDs.isEmpty && !trackedIDs.isDisjoint(with: runningBundleIDs)
    }

    /// Recomputes schedule-based pause state and restarts polling when needed.
    private func refreshSmartPauseScheduleSource(at date: Date = Date()) {
        let isEnabled = settingsStore.smartPauseScheduleEnabled
        let periods = settingsStore.smartPauseSchedulePeriods
        isScheduleConditionActive = isEnabled && smartPauseTriggeredBySchedule(at: date, periods: periods)
        lastSchedulePauseEnabled = isEnabled
        restartSmartPauseScheduleTimerIfNeeded()
    }

    /// Evaluates active/inactive schedule periods at a specific timestamp.
    private func smartPauseTriggeredBySchedule(at date: Date, periods: [SmartPauseSchedulePeriod]) -> Bool {
        guard !periods.isEmpty else { return false }

        var hasActivePeriod = false
        var matchedActive = false
        var matchedInactive = false

        for period in periods {
            if period.mode == .active {
                hasActivePeriod = true
            }
            guard period.contains(date) else { continue }
            if period.mode == .inactive {
                matchedInactive = true
            } else {
                matchedActive = true
            }
        }

        if matchedInactive {
            return true
        }
        if hasActivePeriod {
            return !matchedActive
        }
        return false
    }

    /// Starts periodic schedule reevaluation while schedule-based pause is enabled.
    private func restartSmartPauseScheduleTimerIfNeeded() {
        stopSmartPauseScheduleTimer()
        let periods = settingsStore.smartPauseSchedulePeriods
        guard isRunning, settingsStore.smartPauseScheduleEnabled, !periods.isEmpty else { return }
        guard let nextBoundary = nextSmartPauseScheduleBoundary(after: Date(), periods: periods) else { return }

        let interval = max(nextBoundary.timeIntervalSinceNow, 1)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = Date()
                self.refreshSmartPauseScheduleSource(at: now)
                self.applySmartPauseState()
                self.restartSmartPauseScheduleTimerIfNeeded()
            }
        }
        timer.tolerance = min(max(interval * 0.1, 1), 15)
        smartPauseScheduleTimer = timer
    }

    /// Stops periodic schedule reevaluation.
    private func stopSmartPauseScheduleTimer() {
        smartPauseScheduleTimer?.invalidate()
        smartPauseScheduleTimer = nil
    }

    /// Restores the pre-snooze flow and optionally re-enters a deferred break.
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

    /// Clears all snooze timers and related state flags.
    private func clearSnooze() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        snoozeEndDate = nil
        snoozeWasRunning = false
        snoozeReturnToBreak = false
    }

    /// Cancels any pending smart-pause cooldown countdown.
    private func cancelSmartPauseCooldown() {
        smartPauseCooldownTimer?.invalidate()
        smartPauseCooldownTimer = nil
        smartPauseCooldownEndDate = nil
    }

    /// Returns true when a manual resume should bypass an already-started cooldown.
    private var canResumeImmediatelyFromSmartPauseCooldown: Bool {
        guard smartPauseCooldownTimer != nil else { return false }
        return !isMediaConditionActive && !isAppConditionActive && !isScheduleConditionActive
    }

    /// Resumes the existing timer immediately instead of starting a fresh cooldown.
    private func resumeImmediatelyFromSmartPauseCooldown() {
        cancelSmartPauseCooldown()
        guard isRunning, state == .running, isSmartPaused, !isManuallyPaused else { return }
        engine.resume(resetCounters: false)
        isSmartPaused = false
        smartPauseStartedAt = nil
        onStateChange?(state)
    }

    /// Resumes from smart pause using the configured resume behavior.
    private func resumeFromSmartPauseAfterCooldown() {
        cancelSmartPauseCooldown()
        guard isRunning, state == .running, isSmartPaused, !isManuallyPaused else { return }
        guard !isMediaConditionActive, !isAppConditionActive, !isScheduleConditionActive else { return }

        let behavior = settingsStore.smartPauseResumeBehavior
        engine.resume(resetCounters: behavior == .resetTimer)
        isSmartPaused = false
        smartPauseStartedAt = nil
        onStateChange?(state)
    }

    /// Returns the next schedule boundary that can change the smart-pause result.
    private func nextSmartPauseScheduleBoundary(
        after date: Date,
        periods: [SmartPauseSchedulePeriod],
        calendar: Calendar = .current
    ) -> Date? {
        guard !periods.isEmpty else { return nil }

        let startOfDay = calendar.startOfDay(for: date)
        var nextBoundary: Date?

        for dayOffset in 0...7 {
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay),
                let followingDay = calendar.date(byAdding: .day, value: 1, to: day)
            else {
                continue
            }

            let weekday = calendar.component(.weekday, from: day)

            for period in periods where !period.weekdays.isEmpty && period.weekdays.contains(weekday) {
                if let startBoundary = boundaryDate(forMinute: period.startMinute, on: day, calendar: calendar) {
                    nextBoundary = earlierBoundary(after: date, candidate: startBoundary, current: nextBoundary)
                }

                if let endBoundary = schedulePeriodEndBoundary(
                    for: period,
                    startDay: day,
                    followingDay: followingDay,
                    calendar: calendar
                ) {
                    nextBoundary = earlierBoundary(after: date, candidate: endBoundary, current: nextBoundary)
                }
            }
        }

        return nextBoundary
    }

    /// Chooses the earlier future boundary when several candidates exist.
    private func earlierBoundary(after referenceDate: Date, candidate: Date, current: Date?) -> Date? {
        guard candidate > referenceDate else { return current }
        guard let current else { return candidate }
        return min(current, candidate)
    }

    /// Builds a boundary Date from a minute-of-day on a specific day.
    private func boundaryDate(
        forMinute minuteOfDay: Int,
        on day: Date,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        components.second = 0
        return calendar.date(from: components)
    }

    /// Returns the timestamp when a schedule period stops applying for the given start day.
    private func schedulePeriodEndBoundary(
        for period: SmartPauseSchedulePeriod,
        startDay: Date,
        followingDay: Date,
        calendar: Calendar
    ) -> Date? {
        if period.startMinute == period.endMinute {
            return calendar.startOfDay(for: followingDay)
        }

        if period.startMinute < period.endMinute {
            return boundaryDate(forMinute: period.endMinute, on: startDay, calendar: calendar)
        }

        return boundaryDate(forMinute: period.endMinute, on: followingDay, calendar: calendar)
    }

    /// Returns remaining smart-pause cooldown seconds, if cooldown is active.
    private func smartPauseCooldownRemainingSeconds(at date: Date = Date()) -> Int? {
        guard let endDate = smartPauseCooldownEndDate else { return nil }
        return max(Int(ceil(endDate.timeIntervalSince(date))), 0)
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
        if shouldAlwaysNotifyOnly() { return true }
        let behavior = fullscreenBehaviorPreference()
        if behavior == .interrupt { return false }
        return fullscreenDetector.isFullscreen
    }

    /// Reads fullscreen behavior with compatibility for legacy raw values.
    private func fullscreenBehaviorPreference() -> FullscreenBehavior {
        let defaults = UserDefaults.standard
        let raw = (defaults.string(forKey: OnboardingKeys.fullscreenBehavior) ?? FullscreenBehavior.notify.rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if raw == FullscreenBehavior.interrupt.rawValue || raw == "overlay" {
            return .interrupt
        }
        return .notify
    }

    /// Migrates legacy stored fullscreen behavior values to current raw values.
    private static func migrateLegacyFullscreenBehaviorValueIfNeeded() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: OnboardingKeys.fullscreenBehavior)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return }

        if raw == "overlay" {
            defaults.set(FullscreenBehavior.interrupt.rawValue, forKey: OnboardingKeys.fullscreenBehavior)
        } else if raw == "notification" {
            defaults.set(FullscreenBehavior.notify.rawValue, forKey: OnboardingKeys.fullscreenBehavior)
        }
    }

    /// Checks onboarding settings to see if lock screen option is enabled.
    private func isLockScreenAllowed() -> Bool {
        return UserDefaults.standard.bool(forKey: OnboardingKeys.allowLockScreen)
    }

    /// Returns whether break prompts should always use notifications only.
    private func shouldAlwaysNotifyOnly() -> Bool {
        UserDefaults.standard.bool(forKey: OnboardingKeys.alwaysNotificationOnly)
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
