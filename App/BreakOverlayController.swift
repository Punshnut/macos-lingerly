import AppKit
import SwiftUI

/// Owns and manages the full-screen break overlay windows across displays.
@MainActor
final class BreakOverlayController {
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var mouseMonitor: Any?
    private let holdDuration: TimeInterval = 1.2
    private let skipCompletionDelay: TimeInterval = BreakOverlayView.skipCompletionDelay
    private var onSkipHold: (() -> Void)?
    private let holdState = HoldProgressState()
    private let animationState = BreakOverlayAnimationState()
    private var previousFrontmostApp: NSRunningApplication?
    private var exitTask: Task<Void, Never>?
    private var isSkipSequenceActive = false

    /// Heuristic visibility check used for fullscreen fallback handling.
    var isLikelyVisible: Bool {
        windows.contains { window in
            window.isVisible && window.occlusionState.contains(.visible)
        }
    }

    /// Presents (or updates) an overlay window on every screen.
    func show(
        allowLockScreen: Bool,
        breakDuration: TimeInterval,
        onLockScreen: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onSkipHold: @escaping () -> Void
    ) {
        self.onSkipHold = onSkipHold
        exitTask?.cancel()
        animationState.reset()
        isSkipSequenceActive = false
        if previousFrontmostApp == nil {
            previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        }
        let breakEndDate = Date().addingTimeInterval(max(breakDuration, 1))
        let screens = NSScreen.screens
        if windows.isEmpty || windows.count != screens.count {
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
            windows = screens.map { screen in
                let contentView = BreakOverlayView(
                    showLockScreen: allowLockScreen,
                    breakDuration: breakDuration,
                    breakEndDate: breakEndDate,
                    onLockScreen: onLockScreen,
                    onSnooze: onSnooze,
                    onSkipHold: onSkipHold,
                    holdState: holdState,
                    animationState: animationState,
                    holdDuration: holdDuration
                )
                let hosting = NSHostingController(rootView: contentView)
                hosting.view.frame = screen.frame
                hosting.view.autoresizingMask = [.width, .height]

                let window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentViewController = hosting
                window.isReleasedWhenClosed = false
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
                window.backgroundColor = .clear
                window.isOpaque = false
                window.ignoresMouseEvents = false
                window.isMovable = false
                window.setFrame(screen.frame, display: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return window
            }
        } else {
            for (index, screen) in screens.enumerated() {
                if index >= windows.count {
                    continue
                }
                let window = windows[index]
                if let hosting = window.contentViewController as? NSHostingController<BreakOverlayView> {
                    hosting.rootView = BreakOverlayView(
                        showLockScreen: allowLockScreen,
                        breakDuration: breakDuration,
                        breakEndDate: breakEndDate,
                        onLockScreen: onLockScreen,
                        onSnooze: onSnooze,
                        onSkipHold: onSkipHold,
                        holdState: holdState,
                        animationState: animationState,
                        holdDuration: holdDuration
                    )
                }
                window.setFrame(screen.frame, display: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        holdState.reset()
        installKeyMonitor()
    }

    /// Hides all overlay windows and resets hold state.
    func hide(animated: Bool = true) {
        if isSkipSequenceActive { return }
        removeKeyMonitor()
        holdState.reset()
        exitTask?.cancel()
        guard animated else {
            closeWindows()
            return
        }
        animationState.startExit()
        let delayNanos = UInt64(BreakOverlayView.exitTotalDuration * 1_000_000_000)
        exitTask = Task { [weak self] in
            if delayNanos > 0 {
                try? await Task.sleep(nanoseconds: delayNanos)
            }
            await MainActor.run {
                self?.closeWindows()
            }
        }
    }

    /// Captures spacebar holds for the "hold to skip" gesture.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if self.handleSpaceEvent(event) { return nil }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in
                _ = self?.handleSpaceEvent(event)
            }
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            self.handleMouseEvent(event)
            return event
        }
    }

    /// Stops listening to keyboard events.
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// Returns true when the event is consumed by the hold-to-skip handler.
    private func handleSpaceEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 else { return false }
        if event.type == .keyDown {
            holdState.startHold(source: .space, duration: holdDuration, completionDelay: skipCompletionDelay) { [weak self] in
                self?.beginSkipSequence()
            }
        } else if event.type == .keyUp {
            holdState.cancelHold(source: .space)
        }
        return true
    }

    private func handleMouseEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            holdState.startHold(source: .click, duration: holdDuration, completionDelay: skipCompletionDelay) { [weak self] in
                self?.beginSkipSequence()
            }
        } else if event.type == .leftMouseUp {
            holdState.cancelHold(source: .click)
        }
    }

    private func beginSkipSequence() {
        guard !isSkipSequenceActive else { return }
        isSkipSequenceActive = true
        removeKeyMonitor()
        exitTask?.cancel()
        animationState.startExit()
        let delayNanos = UInt64(BreakOverlayView.exitTotalDuration * 1_000_000_000)
        exitTask = Task { [weak self] in
            if delayNanos > 0 {
                try? await Task.sleep(nanoseconds: delayNanos)
            }
            await MainActor.run {
                self?.closeWindows()
                self?.isSkipSequenceActive = false
                self?.onSkipHold?()
            }
        }
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        previousFrontmostApp?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        previousFrontmostApp = nil
    }
}
