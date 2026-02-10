import AppKit

/// Tracks currently running app bundle identifiers.
final class RunningApplicationsMonitor {
    var onChange: ((Set<String>) -> Void)?

    private(set) var runningBundleIdentifiers: Set<String> = []

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

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appsDidChange() {
        evaluateRunningApps()
    }

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
