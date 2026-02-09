import Foundation

/// Pure helper for deciding when interval thresholds are met.
enum TimingEvaluator {
    /// Returns true when either interval or active-time thresholds are reached.
    static func shouldTriggerInterval(wallElapsed: TimeInterval, activeElapsed: TimeInterval, threshold: TimeInterval, modes: TimingModes) -> Bool {
        let intervalHit = modes.contains(.interval) && wallElapsed >= threshold
        let activeHit = modes.contains(.activeTime) && activeElapsed >= threshold
        return intervalHit || activeHit
    }
}
