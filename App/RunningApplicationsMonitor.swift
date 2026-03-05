import AppKit

/// Tracks currently running app bundle identifiers.
final class RunningApplicationsMonitor {
    var onChange: ((Set<String>) -> Void)?

    private(set) var runningBundleIdentifiers: Set<String> = []

    /// Subscribes to app launch/termination events and performs initial scan.
    init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(appsDidChange),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(appsDidChange),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        evaluateRunningApps()
    }

    /// Removes workspace observers.
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Re-evaluates the running app set after workspace notifications.
    @objc private func appsDidChange() {
        evaluateRunningApps()
    }

    /// Publishes lowercased bundle identifiers when the set changes.
    private func evaluateRunningApps() {
        let identifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap { app in
                app.bundleIdentifier?.lowercased()
            }
        )
        guard identifiers != runningBundleIdentifiers else { return }
        runningBundleIdentifiers = identifiers
        onChange?(identifiers)
    }
}
