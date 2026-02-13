import Foundation

struct WellnessReminderState {
    let hydrationEnabled: Bool
    let freshAirEnabled: Bool
    let standUpEnabled: Bool
    let workoutEnabled: Bool
}

enum WellnessReminderText {
    private struct Clause {
        let key: String
        let isEnabled: Bool
    }

    static func sentence(for state: WellnessReminderState) -> String {
        let base = localized("Wellness Reminder Base")
        let clauses = [
            Clause(key: "Wellness Reminder Hydration", isEnabled: state.hydrationEnabled),
            Clause(key: "Wellness Reminder Fresh Air", isEnabled: state.freshAirEnabled),
            Clause(key: "Wellness Reminder Stand Up", isEnabled: state.standUpEnabled),
            Clause(key: "Wellness Reminder Workout", isEnabled: state.workoutEnabled)
        ]
        .compactMap { clause in
            clause.isEnabled ? localized(clause.key) : nil
        }

        return buildSentence(base: base, clauses: clauses)
    }

    static func sentenceFromDefaults(_ defaults: UserDefaults = .standard) -> String {
        let state = WellnessReminderState(
            hydrationEnabled: defaults.bool(forKey: TimingSettingsKeys.waterReminderEnabled),
            freshAirEnabled: defaults.bool(forKey: TimingSettingsKeys.freshAirReminderEnabled),
            standUpEnabled: defaults.bool(forKey: TimingSettingsKeys.standUpReminderEnabled),
            workoutEnabled: defaults.bool(forKey: TimingSettingsKeys.workoutReminderEnabled)
        )
        return sentence(for: state)
    }

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

    private static func selectLeadIn(for count: Int) -> String {
        let leadIns = [
            "Wellness Reminder Lead In 1",
            "Wellness Reminder Lead In 2",
            "Wellness Reminder Lead In 3"
        ]
        let index = max(count - 1, 0) % leadIns.count
        return localized(leadIns[index])
    }

    private static func selectJoiner(for count: Int) -> String {
        let joiners = [
            "Wellness Reminder Joiner 1",
            "Wellness Reminder Joiner 2",
            "Wellness Reminder Joiner 3"
        ]
        let index = max(count - 2, 0) % joiners.count
        return localized(joiners[index])
    }

    private static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
