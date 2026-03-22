import SwiftUI

/// Full-screen SwiftUI overlay presented during a break.
struct BreakOverlayView: View {
    let showLockScreen: Bool
    let breakDuration: TimeInterval
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
    @AppStorage(TimingSettingsKeys.standUpReminderEnabled) private var standUpReminderEnabled = false
    @AppStorage(TimingSettingsKeys.workoutReminderEnabled) private var workoutReminderEnabled = false
    @AppStorage(TimingSettingsKeys.overlayStyle) private var overlayStyleRaw = OverlayStyle.modernTahoe.rawValue
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
                        if overlayStyle == .classic {
                            ZStack {
                                Text(String(localized: "Overlay Title"))
                                    .font(titleFont)
                                    .foregroundStyle(Color.white.opacity(0.22))
                                    .offset(x: 0.6, y: 0.6)
                                    .blur(radius: 0.8)
                                Text(String(localized: "Overlay Title"))
                                    .font(titleFont)
                                    .foregroundStyle(Color.white.opacity(0.95))
                            }
                            .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 3)
                        } else {
                            Text(String(localized: "Overlay Title"))
                                .font(titleFont)
                                .foregroundStyle(Color.white.opacity(0.96))
                        }
                        Text(overlaySubtitle)
                            .font(subtitleFont)
                            .foregroundStyle(Color.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: maxTextWidth)
                    }
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 12)
                    .scaleEffect(showTitle ? 1 : 0.98)

                OverlayCountdownRenderer(
                    breakDuration: breakDuration,
                    breakEndDate: breakEndDate,
                    font: countdownFont,
                    overlayStyle: overlayStyle
                )
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
                        .focusable(false)

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
                freshAirEnabled: freshAirReminderEnabled,
                standUpEnabled: standUpReminderEnabled,
                workoutEnabled: workoutReminderEnabled
            )
        )
    }

    private var overlayStyle: OverlayStyle {
        OverlayStyle(rawValue: overlayStyleRaw) ?? .classic
    }

    private var titleFont: Font {
        switch overlayStyle {
        case .classic:
            return .system(size: 38, weight: .semibold, design: .serif)
        case .modernTahoe:
            return .system(size: 36, weight: .semibold, design: .default)
        }
    }

    private var subtitleFont: Font {
        switch overlayStyle {
        case .classic:
            return .title2
        case .modernTahoe:
            return .system(size: 22, weight: .medium, design: .default)
        }
    }

    private var countdownFont: Font {
        switch overlayStyle {
        case .classic:
            return .system(size: 44, weight: .semibold, design: .serif)
        case .modernTahoe:
            return .system(size: 44, weight: .semibold, design: .rounded)
        }
    }

    /// Calculates remaining break seconds at a given timestamp.
    fileprivate static func remainingSeconds(breakDuration: TimeInterval, breakEndDate: Date, at date: Date) -> Int {
        // 1312 easter egg: freeze 13:12 for one extra second, then continue normally.
        let displayDate: Date
        if breakDuration >= 840 {
            let freezeStart = breakEndDate.addingTimeInterval(-792)
            let freezeEnd = freezeStart.addingTimeInterval(1)
            if date >= freezeStart && date < freezeEnd {
                displayDate = freezeStart
            } else if date >= freezeEnd {
                displayDate = date.addingTimeInterval(-1)
            } else {
                displayDate = date
            }
        } else {
            displayDate = date
        }

        let remaining = breakEndDate.timeIntervalSince(displayDate)
        return max(Int(ceil(remaining)), 0)
    }

    /// Formats a seconds count as mm:ss or h:mm:ss.
    fileprivate static func formattedRemaining(_ seconds: Int) -> String {
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
    /// Plays the staged exit animation used when dismissing the overlay.
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

private struct OverlayCountdownRenderer: View {
    let breakDuration: TimeInterval
    let breakEndDate: Date
    let font: Font
    let overlayStyle: OverlayStyle

    @State private var remainingSeconds: Int
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(breakDuration: TimeInterval, breakEndDate: Date, font: Font, overlayStyle: OverlayStyle) {
        self.breakDuration = breakDuration
        self.breakEndDate = breakEndDate
        self.font = font
        self.overlayStyle = overlayStyle
        _remainingSeconds = State(initialValue: BreakOverlayView.remainingSeconds(
            breakDuration: breakDuration,
            breakEndDate: breakEndDate,
            at: Date()
        ))
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(String(localized: "Overlay Time Left"))
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.72))
            CountdownView(
                totalSeconds: remainingSeconds,
                font: font,
                overlayStyle: overlayStyle
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(String(localized: "Overlay Time Left")) \(BreakOverlayView.formattedRemaining(remainingSeconds))")
        .onAppear {
            syncRemainingSeconds(for: Date())
        }
        .onReceive(timer) { date in
            syncRemainingSeconds(for: date)
        }
        .onChange(of: breakEndDate) { _ in
            syncRemainingSeconds(for: Date())
        }
    }

    private func syncRemainingSeconds(for date: Date) {
        let nextValue = BreakOverlayView.remainingSeconds(
            breakDuration: breakDuration,
            breakEndDate: breakEndDate,
            at: date
        )
        guard nextValue != remainingSeconds else { return }
        remainingSeconds = nextValue
    }
}

private struct CountdownView: View {
    let totalSeconds: Int
    let font: Font
    let overlayStyle: OverlayStyle

    var body: some View {
        let clampedSeconds = min(max(totalSeconds, 0), 3599)
        let minutes = clampedSeconds / 60
        let seconds = clampedSeconds % 60
        let minuteText = "\(minutes)"
        let secondText = String(format: "%02d", seconds)

        HStack(spacing: 0) {
            MorphingDigits(
                text: minuteText,
                placeholder: "59",
                font: font,
                overlayStyle: overlayStyle,
                alignment: .trailing,
                profiles: [.standard, .standard]
            )
            colonText
            MorphingDigits(
                text: secondText,
                placeholder: "59",
                font: font,
                overlayStyle: overlayStyle,
                alignment: .leading,
                profiles: [.standard, .gentle]
            )
        }
    }

    @ViewBuilder
    private var colonText: some View {
        switch overlayStyle {
        case .classic:
            Text(":")
                .font(font)
                .foregroundStyle(Color.white.opacity(0.96))
                .tracking(0.6)
        case .modernTahoe:
            Text(":")
                .font(font)
                .foregroundStyle(Color.white.opacity(0.96))
        }
    }
}

private enum DigitAlignment {
    case leading
    case trailing
}

private enum DigitMorphProfile {
    case gentle
    case standard
}

private struct MorphingDigits: View {
    let text: String
    let placeholder: String
    let font: Font
    let overlayStyle: OverlayStyle
    let alignment: DigitAlignment
    let profiles: [DigitMorphProfile]

    var body: some View {
        HStack(spacing: digitSpacing) {
            ForEach(Array(slotValues.enumerated()), id: \.offset) { index, value in
                MorphingDigitSlot(
                    value: value,
                    font: font,
                    overlayStyle: overlayStyle,
                    profile: profile(for: index)
                )
                .accessibilityHidden(value == nil)
            }
        }
    }

    private var slotValues: [Character?] {
        let characters = Array(text)
        let count = max(placeholder.count, characters.count)
        let padding = Array<Character?>(repeating: nil, count: max(count - characters.count, 0))

        switch alignment {
        case .leading:
            return characters.map(Optional.some) + padding
        case .trailing:
            return padding + characters.map(Optional.some)
        }
    }

    private func profile(for index: Int) -> DigitMorphProfile {
        guard profiles.indices.contains(index) else { return .standard }
        return profiles[index]
    }

    private var digitSpacing: CGFloat {
        switch overlayStyle {
        case .classic:
            return 0.6
        case .modernTahoe:
            return 0
        }
    }
}

private struct MorphingDigitSlot: View {
    let value: Character?
    let font: Font
    let overlayStyle: OverlayStyle
    let profile: DigitMorphProfile

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settledValue: Character?
    @State private var incomingValue: Character?
    @State private var outgoingValue: Character?
    @State private var morphProgress: CGFloat = 1
    @State private var isTransitioning = false
    @State private var cleanupTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            styledText("8")
                .opacity(0)
                .accessibilityHidden(true)

            styledText(layerText(for: outgoingValue))
                .opacity(layerOpacity(for: outgoingValue, amount: outgoingOpacity))
                .scaleEffect(x: outgoingScaleX, y: outgoingScaleY)
                .offset(y: outgoingOffsetY)
                .blur(radius: outgoingBlur)

            styledText(layerText(for: activeValue))
                .opacity(layerOpacity(for: activeValue, amount: incomingOpacity))
                .scaleEffect(x: incomingScaleX, y: incomingScaleY)
                .offset(y: incomingOffsetY)
                .blur(radius: incomingBlur)
        }
        .compositingGroup()
        .clipped()
        .onAppear {
            settleImmediately(to: value)
        }
        .onChange(of: reduceMotion) { isEnabled in
            guard isEnabled else { return }
            settleImmediately(to: value)
        }
        .onChange(of: value) { newValue in
            animate(to: newValue)
        }
        .onDisappear {
            cleanupTask?.cancel()
        }
    }

    private var activeValue: Character? {
        isTransitioning ? incomingValue : settledValue
    }

    private var incomingOpacity: Double {
        if !isTransitioning {
            return activeValue == nil ? 0 : 1
        }
        guard activeValue != nil else { return 0 }
        let reveal = Double(incomingRevealProgress)
        guard outgoingValue != nil else { return reveal }
        return max(reveal, Double(tuning.incomingOpacityFloor))
    }

    private var outgoingOpacity: Double {
        guard isTransitioning, outgoingValue != nil else { return 0 }
        let fade = Double(1 - outgoingFadeProgress)
        guard incomingValue != nil else { return fade }
        let hold = Double(tuning.outgoingOpacityFloor * (1 - shapeProgress))
        return max(fade, hold)
    }

    private var incomingScaleX: CGFloat {
        guard isTransitioning else { return 1 }
        return lerp(tuning.incomingStartScaleX, 1, shapeProgress)
    }

    private var incomingScaleY: CGFloat {
        guard isTransitioning else { return 1 }
        return lerp(tuning.incomingStartScaleY, 1, shapeProgress)
    }

    private var outgoingScaleX: CGFloat {
        guard isTransitioning else { return 1 }
        return lerp(1, tuning.outgoingEndScaleX, shapeProgress)
    }

    private var outgoingScaleY: CGFloat {
        guard isTransitioning else { return 1 }
        return lerp(1, tuning.outgoingEndScaleY, shapeProgress)
    }

    private var incomingOffsetY: CGFloat {
        guard isTransitioning else { return 0 }
        return tuning.incomingTravelY * (1 - shapeProgress)
    }

    private var outgoingOffsetY: CGFloat {
        guard isTransitioning else { return 0 }
        return -(tuning.outgoingTravelY * shapeProgress)
    }

    private var incomingBlur: CGFloat {
        guard isTransitioning, activeValue != nil else { return 0 }
        return tuning.incomingMaxBlur * (1 - shapeProgress)
    }

    private var outgoingBlur: CGFloat {
        guard isTransitioning, outgoingValue != nil else { return 0 }
        return tuning.outgoingMaxBlur * shapeProgress
    }

    private var shapeProgress: CGFloat {
        eased(morphProgress)
    }

    private var incomingRevealProgress: CGFloat {
        eased(remap(morphProgress, start: tuning.incomingRevealStart, end: 1))
    }

    private var outgoingFadeProgress: CGFloat {
        eased(remap(morphProgress, start: tuning.outgoingFadeStart, end: tuning.outgoingFadeEnd))
    }

    private var tuning: DigitMorphTuning {
        switch profile {
        case .gentle:
            return DigitMorphTuning(
                animation: .timingCurve(0.18, 0.82, 0.22, 1, duration: 0.36),
                settleDelay: 500_000_000,
                incomingStartScaleX: 1.035,
                incomingStartScaleY: 0.975,
                outgoingEndScaleX: 0.97,
                outgoingEndScaleY: 1.035,
                incomingTravelY: 1.4,
                outgoingTravelY: 1.2,
                incomingMaxBlur: 0.18,
                outgoingMaxBlur: 0.22,
                incomingOpacityFloor: 0.12,
                outgoingOpacityFloor: 0.2,
                incomingRevealStart: 0.14,
                outgoingFadeStart: 0.08,
                outgoingFadeEnd: 0.74
            )
        case .standard:
            return DigitMorphTuning(
                animation: .timingCurve(0.16, 0.84, 0.24, 1, duration: 0.42),
                settleDelay: 560_000_000,
                incomingStartScaleX: 1.075,
                incomingStartScaleY: 0.94,
                outgoingEndScaleX: 0.9,
                outgoingEndScaleY: 1.08,
                incomingTravelY: 3.6,
                outgoingTravelY: 2.9,
                incomingMaxBlur: 0.45,
                outgoingMaxBlur: 0.55,
                incomingOpacityFloor: 0.1,
                outgoingOpacityFloor: 0.22,
                incomingRevealStart: 0.18,
                outgoingFadeStart: 0.1,
                outgoingFadeEnd: 0.8
            )
        }
    }

    @MainActor
    private func animate(to newValue: Character?) {
        cleanupTask?.cancel()
        let currentTarget = activeValue
        guard currentTarget != newValue else { return }

        guard !reduceMotion else {
            settleImmediately(to: newValue)
            return
        }

        outgoingValue = currentTarget
        incomingValue = newValue
        isTransitioning = true
        morphProgress = 0

        withAnimation(tuning.animation) {
            morphProgress = 1
        }

        let finalValue = newValue
        cleanupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: tuning.settleDelay)
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                settledValue = finalValue
                incomingValue = finalValue
                outgoingValue = nil
                morphProgress = 1
                isTransitioning = false
            }
        }
    }

    @MainActor
    private func settleImmediately(to newValue: Character?) {
        cleanupTask?.cancel()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            settledValue = newValue
            incomingValue = newValue
            outgoingValue = nil
            morphProgress = 1
            isTransitioning = false
        }
    }

    private func layerText(for value: Character?) -> String {
        value.map(String.init) ?? "8"
    }

    private func layerOpacity(for value: Character?, amount: Double) -> Double {
        guard value != nil else { return 0 }
        return amount
    }

    private func remap(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        return min(max((value - start) / (end - start), 0), 1)
    }

    private func eased(_ value: CGFloat) -> CGFloat {
        value * value * (3 - (2 * value))
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ amount: CGFloat) -> CGFloat {
        start + ((end - start) * amount)
    }

    @ViewBuilder
    private func styledText(_ value: String) -> some View {
        switch overlayStyle {
        case .classic:
            Text(value)
                .font(font)
                .foregroundStyle(Color.white.opacity(0.96))
                .tracking(0.6)
        case .modernTahoe:
            Text(value)
                .font(font)
                .foregroundStyle(Color.white.opacity(0.96))
                .monospacedDigit()
        }
    }
}

private struct DigitMorphTuning {
    let animation: Animation
    let settleDelay: UInt64
    let incomingStartScaleX: CGFloat
    let incomingStartScaleY: CGFloat
    let outgoingEndScaleX: CGFloat
    let outgoingEndScaleY: CGFloat
    let incomingTravelY: CGFloat
    let outgoingTravelY: CGFloat
    let incomingMaxBlur: CGFloat
    let outgoingMaxBlur: CGFloat
    let incomingOpacityFloor: CGFloat
    let outgoingOpacityFloor: CGFloat
    let incomingRevealStart: CGFloat
    let outgoingFadeStart: CGFloat
    let outgoingFadeEnd: CGFloat
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

    /// No runtime updates are required for this blur view.
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Coordinates exit animations for the overlay across all displays.
@MainActor
final class BreakOverlayAnimationState: ObservableObject {
    @Published var isExiting = false

    /// Clears any in-progress exit state.
    func reset() {
        isExiting = false
    }

    /// Marks the overlay as exiting to trigger coordinated fade-out animations.
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
