import AppKit
import CoreGraphics

/// Detects whether the frontmost app is currently fullscreen.
final class FullscreenDetector {
    private(set) var isFullscreen = false {
        didSet {
            if oldValue != isFullscreen {
                onChange?(isFullscreen)
            }
        }
    }

    var onChange: ((Bool) -> Void)?

    /// Subscribes to workspace events and evaluates fullscreen state.
    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(activeAppChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(activeAppChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        evaluate()
    }

    /// Removes notification observers.
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Reevaluates fullscreen state when the active app or space changes.
    @objc private func activeAppChanged() {
        evaluate()
    }

    /// Recomputes the fullscreen flag for the frontmost application.
    func evaluate() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            isFullscreen = false
            return
        }
        isFullscreen = isFullscreenFrontmost(appPID: app.processIdentifier)
    }

    /// Returns true when a visible window matches a screen's bounds.
    private func isFullscreenFrontmost(appPID: pid_t) -> Bool {
        let screenFrames = NSScreen.screens.map(\.frame)
        guard !screenFrames.isEmpty else { return false }
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == appPID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            guard let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool, isOnscreen else { continue }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            if screenFrames.contains(where: { nearlyEqual(bounds, $0, tolerance: 2) }) {
                return true
            }
        }
        return false
    }

    /// Compares rectangles with a tolerance to account for rounding.
    private func nearlyEqual(_ rectA: CGRect, _ rectB: CGRect, tolerance: CGFloat) -> Bool {
        abs(rectA.minX - rectB.minX) <= tolerance &&
        abs(rectA.minY - rectB.minY) <= tolerance &&
        abs(rectA.width - rectB.width) <= tolerance &&
        abs(rectA.height - rectB.height) <= tolerance
    }
}
