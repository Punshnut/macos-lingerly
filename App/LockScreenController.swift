import Foundation
import Darwin

/// Provides a thin wrapper around the system lock-screen command.
enum LockScreenController {
    /// Attempts to lock the screen using available system mechanisms.
    static func lockScreen() {
        DispatchQueue.global(qos: .userInitiated).async {
            if runSACLockScreenImmediate() {
                return
            }
            if runCGSession() {
                return
            }
            if runAppleScriptLock() {
                return
            }
            NSLog("LockScreenController: Unable to lock screen via SACLockScreenImmediate, CGSession, or AppleScript.")
        }
    }

    /// Tries the private login.framework lock API.
    private static func runSACLockScreenImmediate() -> Bool {
        let dylibPath = "/System/Library/PrivateFrameworks/login.framework/Versions/A/login"
        guard let handle = dlopen(dylibPath, RTLD_NOW) else {
            NSLog("LockScreenController: Failed to load login framework at %@", dylibPath)
            return false
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            return false
        }

        typealias LockFunction = @convention(c) () -> Void
        let lock = unsafeBitCast(symbol, to: LockFunction.self)
        lock()
        return true
    }

    /// Falls back to invoking `CGSession -suspend` from known paths.
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

    /// Final fallback that sends the lock-screen shortcut via AppleScript.
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

    /// Runs a process and returns whether it exited successfully.
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
