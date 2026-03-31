import AppKit
import Foundation

/// Detects rapid repeated restarts (crash loops) and prompts the user to file a GitHub issue.
///
/// Call `recordLaunchAndCheck()` once at startup. It stores launch timestamps across restarts
/// using UserDefaults and shows an alert when 3+ launches occur within 60 seconds.
final class CrashLoopDetector {
    private static let timestampsKey = "com.punshnut.lingerly.launchTimestamps"
    private static let windowSeconds: TimeInterval = 60
    private static let threshold = 3
    private static let issuesURL = "https://github.com/Punshnut/macos-lingerly/issues/new"

    static func recordLaunchAndCheck() {
        let now = Date().timeIntervalSince1970
        var timestamps = (UserDefaults.standard.array(forKey: timestampsKey) as? [Double]) ?? []

        // Drop entries outside the detection window.
        timestamps = timestamps.filter { now - $0 < windowSeconds }
        timestamps.append(now)
        UserDefaults.standard.set(timestamps, forKey: timestampsKey)

        guard timestamps.count >= threshold else { return }

        NSLog("Lingerly: crash loop detected — %d launches in the last %ds", timestamps.count, Int(windowSeconds))

        // Reset so the alert doesn't fire again on the very next good launch.
        UserDefaults.standard.set([], forKey: timestampsKey)

        // Wait briefly for the app UI to settle before presenting the alert.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showCrashLoopAlert(launchCount: timestamps.count)
        }
    }

    // MARK: - Private

    private static func showCrashLoopAlert(launchCount: Int) {
        let alert = NSAlert()
        alert.messageText = "Lingerly seems to be crashing on startup"
        alert.informativeText = "It has restarted \(launchCount) times in the last minute, which may indicate a recurring crash. Please consider filing a GitHub issue so it can be investigated — your report helps fix the problem for everyone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open GitHub Issues")
        alert.addButton(withTitle: "Dismiss")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url = URL(string: issuesURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
