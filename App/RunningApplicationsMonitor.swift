import AppKit

/// Tracks currently running app bundle identifiers.
final class RunningApplicationsMonitor {
    var onChange: ((Set<String>) -> Void)?

    private(set) var runningBundleIdentifiers: Set<String> = []
    private var monitoringEnabled = false

    /// Creates the monitor in an idle state.
    init() {
    }

    /// Enables or disables workspace observation for tracked apps.
    func setMonitoringEnabled(_ enabled: Bool) {
        guard enabled != monitoringEnabled else {
            if enabled {
                evaluateRunningApps()
            }
            return
        }

        monitoringEnabled = enabled
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    /// Subscribes to app launch/termination events and performs an initial scan.
    private func startMonitoring() {
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

    /// Removes workspace observers and clears the tracked app set.
    private func stopMonitoring() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        guard !runningBundleIdentifiers.isEmpty else { return }
        runningBundleIdentifiers = []
        onChange?([])
    }

    /// Removes workspace observers.
    deinit {
        stopMonitoring()
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
