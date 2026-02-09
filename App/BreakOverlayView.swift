import SwiftUI

/// Full-screen SwiftUI overlay presented during a break.
struct BreakOverlayView: View {
    let showLockScreen: Bool
    let breakEndDate: Date
    let onLockScreen: () -> Void
    let onSnooze: () -> Void
    let onSkipHold: () -> Void
    @ObservedObject var holdState: HoldProgressState
    @ObservedObject var animationState: BreakOverlayAnimationState
    let holdDuration: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TimingSettingsKeys.snoozeMinutes) private var snoozeMinutes = 1
    @AppStorage(TimingSettingsKeys.waterReminderEnabled) private var waterReminderEnabled = false
    @AppStorage(TimingSettingsKeys.freshAirReminderEnabled) private var freshAirReminderEnabled = false
    @State private var backgroundVisible = false
    @State private var contentVisible = false
    @State private var showTitle = false
    @State private var showTimer = false
    @State private var showControls = false
    @State private var exitDimming = false

    static let entranceBackgroundDuration: TimeInterval = 0.35
    static let entranceContentDuration: TimeInterval = 0.32
    static let entranceStagger: TimeInterval = 0.08
    static let holdCompletionAnimationDuration: TimeInterval = 0.75
    static let skipCompletionDelay: TimeInterval = holdCompletionAnimationDuration + 0.25
    static let exitControlFadeDuration: TimeInterval = 0.22
    static let exitContentStagger: TimeInterval = 0.08
    static let exitContentFadeDelay: TimeInterval = 0.2
    static let exitContentDuration: TimeInterval = 0.7
    static let exitBackgroundDelay: TimeInterval = 0.28
    static let exitBackgroundDuration: TimeInterval = 0.7
    static let exitTotalDuration: TimeInterval = {
        let controlsEnd = exitContentStagger * 2 + exitControlFadeDuration
        let contentEnd = exitContentFadeDelay + exitContentDuration
        let backgroundEnd = exitContentFadeDelay + exitBackgroundDelay + exitBackgroundDuration
        return max(controlsEnd, contentEnd, backgroundEnd)
    }()

    /// Renders the overlay and orchestrates entrance animations.
    var body: some View {
        ZStack {
            VisualEffectBlurView()
                .opacity(backgroundVisible ? 1 : 0)
                .ignoresSafeArea()
            Color.black.opacity(0.32)
                .opacity(backgroundVisible ? 1 : 0)
                .ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.22),
                    Color.white.opacity(0.0)
                ]),
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .opacity(backgroundVisible ? (exitDimming ? 0 : 0.85) : 0)
            .scaleEffect(exitDimming ? 1.08 : 1)
            .blur(radius: 24)
            .ignoresSafeArea()
            GeometryReader { proxy in
                let maxTextWidth = max(proxy.size.width * 0.6, 320)
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                    ZStack {
                        Text(String(localized: "Overlay Title"))
                            .font(.system(size: 38, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.22))
                            .offset(x: 0.6, y: 0.6)
                            .blur(radius: 0.8)
                        Text(String(localized: "Overlay Title"))
                            .font(.system(size: 38, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }
                    .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 3)
                    Text(overlaySubtitle)
                        .font(.title2)
                        .foregroundStyle(Color.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: maxTextWidth)
                }
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 12)
                .scaleEffect(showTitle ? 1 : 0.98)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remainingSeconds = remainingSeconds(at: context.date)
                    VStack(spacing: 4) {
                        Text(String(localized: "Overlay Time Left"))
                            .font(.headline)
                            .foregroundStyle(Color.white.opacity(0.72))
                        Text(formattedRemaining(remainingSeconds))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.96))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(String(localized: "Overlay Time Left")) \(formattedRemaining(remainingSeconds))")
                    .animation(reduceMotion ? .none : .easeInOut(duration: 0.6), value: remainingSeconds)
                }
                .opacity(showTimer ? 1 : 0)
                .offset(y: showTimer ? 0 : 10)
                .scaleEffect(showTimer ? 1 : 0.99)

                VStack(spacing: 18) {
                    Button(snoozeLabel, action: onSnooze)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Color.white.opacity(0.22))
                        .foregroundStyle(Color.white)
                        .accessibilityHint(String(localized: "Snooze"))
                        .accessibilitySortPriority(3)
                        .focusable(true)

                    HoldToSkipButton(
                        progress: holdState.progress,
                        isCompleting: holdState.isCompleting,
                        isExiting: animationState.isExiting || exitDimming,
                        reduceMotion: reduceMotion
                    )
                        .accessibilityLabel(String(localized: "Overlay Hold To Skip"))
                        .accessibilityHint(String(localized: "Overlay Hold To Skip Hint"))
                        .accessibilitySortPriority(2)
                        .focusable(true)

                    if showLockScreen {
                        Button(String(localized: "Overlay Lock Screen"), action: onLockScreen)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(Color.white.opacity(0.32))
                            .foregroundStyle(Color.white)
                            .accessibilityHint(String(localized: "Overlay Lock Screen Detail"))
                            .accessibilitySortPriority(1)
                            .focusable(true)
                        Text(String(localized: "Overlay Lock Screen Detail"))
                            .font(.title3)
                            .foregroundStyle(Color.white.opacity(0.74))
                    }
                }
                .opacity(showControls ? 1 : 0)
                .offset(y: showControls ? 0 : 12)
                .scaleEffect(showControls ? 1 : 0.98)
                }
                .padding(.vertical, 38)
                .padding(.horizontal, 42)
                .frame(maxWidth: maxTextWidth)
                .accessibilityElement(children: .contain)
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .opacity(contentVisible ? (exitDimming ? 0 : 1) : 0)
                .scaleEffect(contentVisible ? (exitDimming ? 0.965 : 1) : 0.98)
                .blur(radius: contentVisible ? (exitDimming ? 10 : 0) : 6)
                .offset(y: exitDimming ? -12 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .task(id: breakEndDate) {
            await runEntranceAnimation()
        }
        .onChange(of: animationState.isExiting) { isExiting in
            guard isExiting else { return }
            Task { @MainActor in
                await runExitAnimation()
            }
        }
    }

    /// Chooses the subtitle text based on wellness settings.
    private var overlaySubtitle: String {
        WellnessReminderText.sentence(
            for: WellnessReminderState(
                hydrationEnabled: waterReminderEnabled,
                freshAirEnabled: freshAirReminderEnabled
            )
        )
    }

    /// Calculates remaining break seconds at a given timestamp.
    private func remainingSeconds(at date: Date) -> Int {
        let remaining = breakEndDate.timeIntervalSince(date)
        return max(Int(ceil(remaining)), 0)
    }

    /// Formats a seconds count as mm:ss or h:mm:ss.
    private func formattedRemaining(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Produces the localized snooze button label.
    private var snoozeLabel: String {
        let minutes = max(snoozeMinutes, 1)
        return String.localizedStringWithFormat(String(localized: "Snooze 1 min"), minutes)
    }

    @MainActor
    /// Staggers the intro animation for title, timer, and controls.
    private func runEntranceAnimation() async {
        if animationState.isExiting { return }
        backgroundVisible = false
        contentVisible = false
        showTitle = false
        showTimer = false
        showControls = false
        exitDimming = false
        guard !reduceMotion else {
            backgroundVisible = true
            contentVisible = true
            showTitle = true
            showTimer = true
            showControls = true
            return
        }
        await animate(after: 0.02, .easeOut(duration: Self.entranceBackgroundDuration)) {
            backgroundVisible = true
        }
        await animate(after: 0.04, .easeOut(duration: Self.entranceContentDuration)) {
            contentVisible = true
        }
        await animate(after: Self.entranceStagger, .easeOut(duration: 0.24)) {
            showTitle = true
        }
        await animate(after: Self.entranceStagger, .easeOut(duration: 0.26)) {
            showTimer = true
        }
        await animate(after: Self.entranceStagger, .easeOut(duration: 0.28)) {
            showControls = true
        }
    }

    @MainActor
    /// Helper for delaying and applying SwiftUI animations.
    private func animate(after delay: TimeInterval, _ animation: Animation, _ updates: @escaping () -> Void) async {
        if delay > 0 {
            let delayNanos = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanos)
        }
        withAnimation(animation) {
            updates()
        }
    }

    @MainActor
    private func runExitAnimation() async {
        guard backgroundVisible else { return }
        guard !reduceMotion else {
            contentVisible = false
            backgroundVisible = false
            return
        }
        let controlsFade = Task { @MainActor in
            await animate(after: 0, .easeInOut(duration: Self.exitControlFadeDuration)) {
                showControls = false
            }
        }
        let timerFade = Task { @MainActor in
            await animate(after: Self.exitContentStagger, .easeInOut(duration: Self.exitControlFadeDuration)) {
                showTimer = false
            }
        }
        let titleFade = Task { @MainActor in
            await animate(after: Self.exitContentStagger * 2, .easeInOut(duration: Self.exitControlFadeDuration)) {
                showTitle = false
            }
        }
        let contentFade = Task { @MainActor in
            await animate(after: Self.exitContentFadeDelay, .easeInOut(duration: Self.exitContentDuration)) {
                exitDimming = true
            }
        }
        let backgroundFade = Task { @MainActor in
            await animate(after: Self.exitContentFadeDelay + Self.exitBackgroundDelay, .easeInOut(duration: Self.exitBackgroundDuration)) {
                backgroundVisible = false
            }
        }
        _ = await (controlsFade.value, timerFade.value, titleFade.value, contentFade.value, backgroundFade.value)
    }
}

/// Visual affordance for the "hold to skip" action.
private struct HoldToSkipButton: View {
    let progress: CGFloat
    let isCompleting: Bool
    let isExiting: Bool
    let reduceMotion: Bool

    /// Renders the progress ring and label.
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.26), lineWidth: 3)
                    .frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 40, height: 40)
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.0)
                        ]),
                        center: .center,
                        startRadius: 4,
                        endRadius: 26
                    ))
                    .frame(width: 40, height: 40)
                    .opacity(isCompleting ? 1 : 0)
                    .scaleEffect(isCompleting ? 0.2 : 1)
            }
            .scaleEffect(isCompleting ? 0.06 : 1)
            .opacity(isCompleting ? 0 : 1)
            .blur(radius: isCompleting ? 6 : 0)
            Text(String(localized: "Overlay Hold To Skip"))
                .font(.title2)
                .foregroundStyle(Color.white)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isCompleting ? 0.04 : 0.12))
        )
        .opacity(isExiting ? 0 : (isCompleting ? 0.35 : 1))
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.18), value: progress)
        .animation(reduceMotion ? .none : .easeInOut(duration: BreakOverlayView.holdCompletionAnimationDuration), value: isCompleting)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: isExiting)
    }
}

/// AppKit-backed blur view to match macOS fullscreen UI style.
private struct VisualEffectBlurView: NSViewRepresentable {
    /// Creates the NSVisualEffectView used in the overlay.
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    /// No-op: the blur view does not require dynamic updates.
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Coordinates exit animations for the overlay across all displays.
@MainActor
final class BreakOverlayAnimationState: ObservableObject {
    @Published var isExiting = false

    func reset() {
        isExiting = false
    }

    func startExit() {
        guard !isExiting else { return }
        isExiting = true
    }
}

/// Tracks and publishes hold progress for skip interactions.
@MainActor
final class HoldProgressState: ObservableObject {
    enum Source {
        case space
        case click
    }

    @Published var progress: CGFloat = 0
    @Published var isCompleting: Bool = false

    private var activeSource: Source?
    private var timer: Timer?
    private var startDate: Date?
    private var duration: TimeInterval = 1.2
    private var completionDelay: TimeInterval = 0
    private var onComplete: (() -> Void)?
    private var completionTask: Task<Void, Never>?
    private var isLocked: Bool = false

    /// Starts a timed hold gesture, completing once progress reaches 1.0.
    func startHold(source: Source, duration: TimeInterval, completionDelay: TimeInterval = 0, onComplete: @escaping () -> Void) {
        if let activeSource, activeSource != source { return }
        if isLocked { return }
        if timer != nil { return }
        self.activeSource = source
        self.duration = max(duration, 0.1)
        self.completionDelay = max(completionDelay, 0)
        self.onComplete = onComplete
        startDate = Date()
        progress = 0
        isCompleting = false
        completionTask?.cancel()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    /// Cancels a hold gesture for the matching input source.
    func cancelHold(source: Source) {
        guard activeSource == source else { return }
        guard !isCompleting else { return }
        reset()
    }

    /// Resets progress state and clears timers.
    func reset() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        activeSource = nil
        progress = 0
        isCompleting = false
        isLocked = false
        completionDelay = 0
        onComplete = nil
        completionTask?.cancel()
        completionTask = nil
    }

    /// Advances the hold progress and fires completion when done.
    private func tick() {
        guard let startDate else { return }
        let elapsed = Date().timeIntervalSince(startDate)
        let nextProgress = min(elapsed / duration, 1)
        progress = CGFloat(nextProgress)
        if nextProgress >= 1 {
            let completion = onComplete
            timer?.invalidate()
            timer = nil
            isLocked = true
            if completionDelay > 0 {
                isCompleting = true
                completionTask?.cancel()
                completionTask = Task { [weak self] in
                    guard let self else { return }
                    let delayNanos = UInt64(self.completionDelay * 1_000_000_000)
                    if delayNanos > 0 {
                        try? await Task.sleep(nanoseconds: delayNanos)
                    }
                    await MainActor.run {
                        completion?()
                    }
                }
            } else {
                completion?()
            }
        }
    }
}
