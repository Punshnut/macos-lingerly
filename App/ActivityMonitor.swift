import AppKit

/// Tracks session and screen lock state to determine user activity.
final class ActivityMonitor {
    private(set) var isSessionActive = true
    private(set) var isScreenLocked = false

    var onUserActiveChange: ((Bool) -> Void)?

    private var lastUserActive = true

    /// True when the user session is active and the screen is unlocked.
    var isUserActive: Bool {
        isSessionActive && !isScreenLocked
    }

    /// Subscribes to workspace and distributed notifications for session changes.
    init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionDidResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    /// Removes observers on teardown.
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Marks the session as active.
    @objc private func sessionDidBecomeActive() {
        isSessionActive = true
        notifyUserActiveChange()
    }

    /// Marks the session as inactive.
    @objc private func sessionDidResignActive() {
        isSessionActive = false
        notifyUserActiveChange()
    }

    /// Marks the screen as locked.
    @objc private func screenLocked() {
        isScreenLocked = true
        notifyUserActiveChange()
    }

    /// Marks the screen as unlocked.
    @objc private func screenUnlocked() {
        isScreenLocked = false
        notifyUserActiveChange()
    }

    /// Emits user-active changes only when the computed state actually flips.
    private func notifyUserActiveChange() {
        let current = isUserActive
        guard current != lastUserActive else { return }
        lastUserActive = current
        onUserActiveChange?(current)
    }
}
