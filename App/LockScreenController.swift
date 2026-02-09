import Foundation

/// Provides a thin wrapper around the system lock-screen command.
enum LockScreenController {
    /// Invokes the system lock screen command via `CGSession`, with a fallback to AppleScript.
    static func lockScreen() {
        DispatchQueue.global(qos: .userInitiated).async {
            if runCGSession() {
                return
            }
            if runAppleScriptLock() {
                return
            }
            NSLog("LockScreenController: Unable to lock screen via CGSession or AppleScript.")
        }
    }

    private static func runCGSession() -> Bool {
        let candidates = [
            "/System/Library/CoreServices/CGSession",
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if runProcess(url, arguments: ["-suspend"], label: "CGSession") {
                return true
            }
        }
        return false
    }

    private static func runAppleScriptLock() -> Bool {
        let scriptSource = "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        guard let script = NSAppleScript(source: scriptSource) else {
            NSLog("LockScreenController: Failed to compile AppleScript.")
            return false
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("LockScreenController: AppleScript error: %@", errorInfo)
            return false
        }
        return true
    }

    private static func runProcess(_ url: URL, arguments: [String], label: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            NSLog("LockScreenController: %@ not executable at %@", label, url.path)
            return false
        }
        let task = Process()
        task.executableURL = url
        task.arguments = arguments
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return true
            }
            NSLog("LockScreenController: %@ exited with status %d", label, task.terminationStatus)
            return false
        } catch {
            NSLog("LockScreenController: %@ failed to run: %@", label, String(describing: error))
            return false
        }
    }
}
