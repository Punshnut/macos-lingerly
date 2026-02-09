import Foundation

/// Core timing state machine for breaks and reminder schedules.
@MainActor
final class TimingEngine {
    enum State: Equatable {
        case idle
        case running
        case breakDue
        case breakActive
    }

    /// Inputs that control how the engine schedules breaks.
    struct Configuration: Equatable {
        var intervalMinutes: Int
        var breakDurationSeconds: Int
        var modes: TimingModes
        var scheduleTimes: [ScheduleTime]
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    var onStateChange: ((State) -> Void)?
    var shouldStartBreak: (() -> Bool)?
    var onBreakCompleted: ((Int) -> Void)?

    private let activityMonitor: ActivityMonitor
    private var config: Configuration

    private var tickTimer: Timer?
    private var dueTimer: Timer?
    private var breakTimer: Timer?
    private var pendingBreak = false
    private var isPaused = false
    private var breakEndDate: Date?

    private var wallElapsedSeconds: TimeInterval = 0
    private var activeElapsedSeconds: TimeInterval = 0
    private var lastTickDate = Date()
    private var lastScheduleFire: [ScheduleTime: DateComponents] = [:]

    private let dueGraceSeconds: TimeInterval = 4

    /// Creates an engine with the given activity monitor and configuration.
    init(activityMonitor: ActivityMonitor, configuration: Configuration) {
        self.activityMonitor = activityMonitor
        self.config = configuration
    }

    /// Applies updated configuration without resetting state.
    func updateConfiguration(_ configuration: Configuration) {
        config = configuration
    }

    /// Starts the timing loop from an idle state.
    func start() {
        guard state == .idle else { return }
        resetCounters()
        isPaused = false
        state = .running
        startTicking()
    }

    /// Stops all timers and returns to idle.
    func stop() {
        invalidateTimers()
        isPaused = false
        state = .idle
    }

    /// Resets counters and returns to idle, clearing pending break state.
    func reset() {
        invalidateTimers()
        pendingBreak = false
        isPaused = false
        breakEndDate = nil
        resetCounters()
        state = .idle
    }

    /// Begins the 1-second tick loop.
    private func startTicking() {
        lastTickDate = Date()
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    /// Accumulates elapsed time and triggers breaks as needed.
    private func tick() {
        guard state == .running, !isPaused else { return }

        let now = Date()
        let delta = now.timeIntervalSince(lastTickDate)
        lastTickDate = now

        if config.modes.contains(.interval) {
            wallElapsedSeconds += delta
        }

        if config.modes.contains(.activeTime), activityMonitor.isUserActive {
            activeElapsedSeconds += delta
        }

        if shouldTriggerSchedule(at: now) || shouldTriggerInterval() {
            triggerBreak()
        }
    }

    /// Pauses tick accumulation without resetting counters.
    func pause() {
        guard state == .running, !isPaused else { return }
        isPaused = true
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// Resumes ticking, optionally resetting counters.
    func resume(resetCounters: Bool) {
        guard state == .running, isPaused else { return }
        if resetCounters {
            self.resetCounters()
        } else {
            lastTickDate = Date()
        }
        isPaused = false
        startTicking()
    }

    /// Evaluates interval/active-time thresholds.
    private func shouldTriggerInterval() -> Bool {
        let threshold = TimeInterval(max(config.intervalMinutes, 1) * 60)
        return TimingEvaluator.shouldTriggerInterval(
            wallElapsed: wallElapsedSeconds,
            activeElapsed: activeElapsedSeconds,
            threshold: threshold,
            modes: config.modes
        )
    }

    /// Returns true when a configured schedule time is reached.
    private func shouldTriggerSchedule(at date: Date) -> Bool {
        guard config.modes.contains(.schedule) else { return false }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        for time in config.scheduleTimes {
            if components.hour == time.hour && components.minute == time.minute {
                let dayKey = DateComponents(year: components.year, month: components.month, day: components.day)
                if lastScheduleFire[time] != dayKey {
                    lastScheduleFire[time] = dayKey
                    return true
                }
            }
        }
        return false
    }

    /// Marks a break as due and starts the grace timer.
    private func triggerBreak() {
        state = .breakDue
        pendingBreak = true
        dueTimer?.invalidate()
        dueTimer = Timer.scheduledTimer(withTimeInterval: dueGraceSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.attemptStartBreak()
            }
        }
    }

    /// Starts an active break and schedules its end.
    private func startBreak() {
        state = .breakActive
        pendingBreak = false
        breakTimer?.invalidate()
        let duration = TimeInterval(max(config.breakDurationSeconds, 5))
        breakEndDate = Date().addingTimeInterval(duration)
        breakTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.endBreak()
            }
        }
    }

    /// Ends the active break and returns to running state.
    private func endBreak() {
        onBreakCompleted?(max(config.breakDurationSeconds, 0))
        breakEndDate = nil
        resetCounters()
        state = .running
    }

    /// Starts a break if one is pending and not vetoed by the caller.
    func attemptStartBreak() {
        guard pendingBreak else { return }
        if shouldStartBreak?() ?? true {
            startBreak()
        }
    }

    /// Cancels a pending/active break and resets counters.
    func skipBreak() {
        pendingBreak = false
        dueTimer?.invalidate()
        dueTimer = nil
        breakTimer?.invalidate()
        breakTimer = nil
        breakEndDate = nil
        resetCounters()
        state = .running
    }

    /// Starts a break immediately when running.
    func startBreakNow() {
        guard state == .running else { return }
        pendingBreak = false
        dueTimer?.invalidate()
        dueTimer = nil
        startBreak()
    }

    /// Marks a break as due without starting it yet.
    func markBreakDue() {
        guard state == .running else { return }
        pendingBreak = true
        dueTimer?.invalidate()
        dueTimer = nil
        state = .breakDue
    }

    /// Clears pending breaks and resets counters without stopping the engine.
    func resetCycle() {
        pendingBreak = false
        dueTimer?.invalidate()
        dueTimer = nil
        breakTimer?.invalidate()
        breakTimer = nil
        breakEndDate = nil
        resetCounters()
        if state == .breakDue || state == .breakActive {
            state = .running
        }
    }

    /// Returns seconds remaining in the active break, if any.
    func breakRemainingSeconds(at date: Date = Date()) -> Int? {
        guard state == .breakActive, let breakEndDate else { return nil }
        let remaining = breakEndDate.timeIntervalSince(date)
        return max(Int(ceil(remaining)), 0)
    }

    /// Applies a post-unlock grace period by extending the next break window.
    func applyUnlockGrace(seconds: Int) {
        guard state != .idle else { return }
        let threshold = TimeInterval(max(config.intervalMinutes, 1) * 60)
        let grace = min(TimeInterval(max(seconds, 0)), threshold)

        if state != .running {
            pendingBreak = false
            dueTimer?.invalidate()
            dueTimer = nil
            breakTimer?.invalidate()
            breakTimer = nil
            breakEndDate = nil
            state = .running
        }

        if config.modes.contains(.interval) {
            if wallElapsedSeconds >= threshold {
                wallElapsedSeconds = max(threshold - grace, 0)
            } else {
                wallElapsedSeconds = max(wallElapsedSeconds - grace, 0)
            }
        }

        if config.modes.contains(.activeTime) {
            if activeElapsedSeconds >= threshold {
                activeElapsedSeconds = max(threshold - grace, 0)
            } else {
                activeElapsedSeconds = max(activeElapsedSeconds - grace, 0)
            }
        }

        lastTickDate = Date()
    }

    /// Returns seconds remaining until the next scheduled/interval break.
    func timeUntilNextBreak(at date: Date = Date()) -> Int? {
        guard state == .running else { return nil }
        let threshold = TimeInterval(max(config.intervalMinutes, 1) * 60)
        var candidates: [TimeInterval] = []
        let delta = runningDeltaSinceLastTick(at: date)
        let wallElapsed = wallElapsedSeconds + (config.modes.contains(.interval) ? delta : 0)
        let activeElapsed = activeElapsedSeconds + (config.modes.contains(.activeTime) && activityMonitor.isUserActive ? delta : 0)

        if config.modes.contains(.interval) {
            candidates.append(max(threshold - wallElapsed, 0))
        }

        if config.modes.contains(.activeTime) {
            candidates.append(max(threshold - activeElapsed, 0))
        }

        if config.modes.contains(.schedule), let scheduleInterval = nextScheduleInterval(from: date) {
            candidates.append(max(scheduleInterval, 0))
        }

        guard let minimum = candidates.min() else { return nil }
        return Int(ceil(minimum))
    }

    /// Approximates elapsed time since the last tick while still running.
    private func runningDeltaSinceLastTick(at date: Date) -> TimeInterval {
        guard state == .running, !isPaused else { return 0 }
        let delta = date.timeIntervalSince(lastTickDate)
        return max(delta, 0)
    }

    /// Finds the next scheduled break interval from a reference date.
    private func nextScheduleInterval(from date: Date) -> TimeInterval? {
        guard !config.scheduleTimes.isEmpty else { return nil }
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        var minimumInterval: TimeInterval?

        for time in config.scheduleTimes {
            var candidateComponents = dayComponents
            candidateComponents.hour = time.hour
            candidateComponents.minute = time.minute
            candidateComponents.second = 0
            guard var candidateDate = calendar.date(from: candidateComponents) else { continue }
            if candidateDate <= date {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: candidateDate) else { continue }
                candidateDate = nextDay
            }
            let interval = candidateDate.timeIntervalSince(date)
            minimumInterval = min(minimumInterval ?? interval, interval)
        }

        return minimumInterval
    }

    /// Resets elapsed-time counters and tick baseline.
    private func resetCounters() {
        wallElapsedSeconds = 0
        activeElapsedSeconds = 0
        lastTickDate = Date()
    }

    /// Invalidates all timers owned by the engine.
    private func invalidateTimers() {
        tickTimer?.invalidate()
        tickTimer = nil
        dueTimer?.invalidate()
        dueTimer = nil
        breakTimer?.invalidate()
        breakTimer = nil
        breakEndDate = nil
    }
}
