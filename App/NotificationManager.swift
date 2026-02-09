import Foundation
import UserNotifications

/// Handles local notifications and routes their actions to app callbacks.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    @MainActor static let shared = NotificationManager()

    enum ActionIdentifier {
        static let snooze = "lingerly.action.snooze"
        static let skip = "lingerly.action.skip"
        static let confirmSkip = "lingerly.action.confirmSkip"
        static let cancelSkip = "lingerly.action.cancelSkip"
    }

    enum CategoryIdentifier {
        static let breakDue = "lingerly.category.breakDue"
        static let confirmSkip = "lingerly.category.confirmSkip"
    }

    var onSnooze: (() -> Void)?
    var onSkipRequest: (() -> Void)?
    var onConfirmSkip: (() -> Void)?
    var onCancelSkip: (() -> Void)?

    private let center: UNUserNotificationCenter?

    /// Initializes the notification center and registers action categories.
    override init() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            center = UNUserNotificationCenter.current()
        } else {
            center = nil
        }
        super.init()
        center?.delegate = self
        configureCategories(snoozeMinutes: currentSnoozeMinutes())
    }

    /// Requests notification authorization if the app is running as a bundle.
    func requestAuthorizationIfNeeded() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Shows a notification indicating a break is due.
    func showBreakDueNotification() {
        requestAuthorizationIfNeeded()
        configureCategories(snoozeMinutes: currentSnoozeMinutes())
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Notification Break Due Title")
        content.body = WellnessReminderText.sentenceFromDefaults()
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = CategoryIdentifier.breakDue

        let request = UNNotificationRequest(identifier: "lingerly.break.due", content: content, trigger: nil)
        center?.add(request)
    }

    /// Shows a confirmation prompt before skipping a break.
    func showConfirmSkipNotification() {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Notification Skip Confirm Title")
        content.body = String(localized: "Notification Skip Confirm Body")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = CategoryIdentifier.confirmSkip

        let request = UNNotificationRequest(identifier: "lingerly.break.confirmSkip", content: content, trigger: nil)
        center?.add(request)
    }

    /// Registers notification categories and actions.
    private func configureCategories(snoozeMinutes: Int = 1) {
        guard let center else { return }
        let snoozeTitle = String.localizedStringWithFormat(String(localized: "Snooze 1 min"), max(snoozeMinutes, 1))
        let snooze = UNNotificationAction(identifier: ActionIdentifier.snooze, title: snoozeTitle, options: [])
        let skip = UNNotificationAction(identifier: ActionIdentifier.skip, title: String(localized: "Notification Skip"), options: [.destructive])

        let confirmSkip = UNNotificationAction(identifier: ActionIdentifier.confirmSkip, title: String(localized: "Notification Skip Confirm"), options: [.destructive])
        let cancelSkip = UNNotificationAction(identifier: ActionIdentifier.cancelSkip, title: String(localized: "Notification Skip Cancel"), options: [])

        let breakDueCategory = UNNotificationCategory(
            identifier: CategoryIdentifier.breakDue,
            actions: [snooze, skip],
            intentIdentifiers: [],
            options: []
        )

        let confirmCategory = UNNotificationCategory(
            identifier: CategoryIdentifier.confirmSkip,
            actions: [confirmSkip, cancelSkip],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([breakDueCategory, confirmCategory])
    }

    /// Reads the configured snooze minutes from user defaults.
    private func currentSnoozeMinutes() -> Int {
        let value = UserDefaults.standard.integer(forKey: TimingSettingsKeys.snoozeMinutes)
        return max(value, 1)
    }

    /// Dispatches notification actions to the caller-provided handlers.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        switch response.actionIdentifier {
        case ActionIdentifier.snooze:
            onSnooze?()
        case ActionIdentifier.skip:
            onSkipRequest?()
        case ActionIdentifier.confirmSkip:
            onConfirmSkip?()
        case ActionIdentifier.cancelSkip:
            onCancelSkip?()
        default:
            break
        }
    }
}
