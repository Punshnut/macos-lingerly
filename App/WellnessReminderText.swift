import Foundation

struct WellnessReminderState {
    let hydrationEnabled: Bool
    let freshAirEnabled: Bool
    let standUpEnabled: Bool
    let workoutEnabled: Bool
}

/// Builds localized wellness reminder copy based on enabled suggestion types.
enum WellnessReminderText {
    private struct Clause {
        let key: String
        let isEnabled: Bool
    }

    /// Returns a complete reminder sentence for the provided wellness toggles.
    static func sentence(for state: WellnessReminderState) -> String {
        let base = localized("WellnessReminderBaseText")
        let clauses = [
            Clause(key: "WellnessReminderHydrationText", isEnabled: state.hydrationEnabled),
            Clause(key: "WellnessReminderFreshAirText", isEnabled: state.freshAirEnabled),
            Clause(key: "WellnessReminderStandUpText", isEnabled: state.standUpEnabled),
            Clause(key: "WellnessReminderWorkoutText", isEnabled: state.workoutEnabled)
        ]
        .compactMap { clause in
            clause.isEnabled ? localized(clause.key) : nil
        }

        return buildSentence(base: base, clauses: clauses)
    }

    /// Reads wellness toggles from defaults and returns the composed sentence.
    static func sentenceFromDefaults(_ defaults: UserDefaults = .standard) -> String {
        let state = WellnessReminderState(
            hydrationEnabled: defaults.bool(forKey: TimingSettingsKeys.waterReminderEnabled),
            freshAirEnabled: defaults.bool(forKey: TimingSettingsKeys.freshAirReminderEnabled),
            standUpEnabled: defaults.bool(forKey: TimingSettingsKeys.standUpReminderEnabled),
            workoutEnabled: defaults.bool(forKey: TimingSettingsKeys.workoutReminderEnabled)
        )
        return sentence(for: state)
    }

    /// Combines a base message with optional localized clause list punctuation.
    private static func buildSentence(base: String, clauses: [String]) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseText = trimmedBase.hasSuffix(".") ? String(trimmedBase.dropLast()) : trimmedBase
        guard !clauses.isEmpty else {
            return baseText + "."
        }

        let leadIn = selectLeadIn(for: clauses.count)
        let joiner = selectJoiner(for: clauses.count)
        let list = joinClauses(clauses, joiner: joiner)
        return "\(baseText), \(leadIn) \(list)."
    }

    /// Joins clauses using localized conjunction semantics for list length.
    private static func joinClauses(_ clauses: [String], joiner: String) -> String {
        guard clauses.count > 1 else {
            return clauses.first ?? ""
        }
        if clauses.count == 2 {
            return "\(clauses[0]) \(joiner) \(clauses[1])"
        }
        let head = clauses.dropLast().joined(separator: ", ")
        let tail = clauses.last ?? ""
        return "\(head), \(joiner) \(tail)"
    }

    /// Chooses a localized lead-in phrase based on clause count.
    private static func selectLeadIn(for count: Int) -> String {
        let leadIns = [
            "WellnessReminderLeadIn1Text",
            "WellnessReminderLeadIn2Text",
            "WellnessReminderLeadIn3Text"
        ]
        let index = max(count - 1, 0) % leadIns.count
        return localized(leadIns[index])
    }

    /// Chooses a localized list joiner for the current clause count.
    private static func selectJoiner(for count: Int) -> String {
        let joiners = [
            "WellnessReminderJoiner1Text",
            "WellnessReminderJoiner2Text",
            "WellnessReminderJoiner3Text"
        ]
        let index = max(count - 2, 0) % joiners.count
        return localized(joiners[index])
    }

    /// Resolves a localized string for the supplied key.
    private static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
