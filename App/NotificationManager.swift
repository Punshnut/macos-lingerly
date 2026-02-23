import Foundation
@preconcurrency import UserNotifications

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

    /// Shows a notification indicating a break is due.
    func showBreakDueNotification() {
        ensureAuthorization { authorized in
            guard authorized else { return }
            Task { @MainActor in
                NotificationManager.shared.postBreakDueNotification()
            }
        }
    }

    /// Shows a confirmation prompt before skipping a break.
    func showConfirmSkipNotification() {
        ensureAuthorization { authorized in
            guard authorized else { return }
            Task { @MainActor in
                NotificationManager.shared.postConfirmSkipNotification()
            }
        }
    }

    /// Requests permission when needed and reports whether posting is allowed.
    private func ensureAuthorization(_ completion: @escaping @Sendable (Bool) -> Void) {
        guard let center else {
            NSLog("Lingerly: notifications unavailable because app is not running from a .app bundle")
            completion(false)
            return
        }
        center.getNotificationSettings { settings in
            Self.logNotificationSettings(settings)
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if !granted {
                        NSLog("Lingerly: notification authorization request was not granted")
                    }
                    completion(granted)
                }
            case .denied:
                NSLog("Lingerly: notification authorization is denied in system settings")
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    /// Emits a compact diagnostics line to help identify OS-level suppression.
    private static func logNotificationSettings(_ settings: UNNotificationSettings) {
        let auth = settings.authorizationStatus.rawValue
        let alert = settings.alertSetting.rawValue
        let sound = settings.soundSetting.rawValue
        let center = settings.notificationCenterSetting.rawValue
        let lock = settings.lockScreenSetting.rawValue
        var extras = ""
        if #available(macOS 12.0, *) {
            extras += " scheduled=\(settings.scheduledDeliverySetting.rawValue)"
            extras += " timeSensitive=\(settings.timeSensitiveSetting.rawValue)"
        }
        NSLog("Lingerly notifications: auth=\(auth) alert=\(alert) sound=\(sound) center=\(center) lock=\(lock)\(extras)")
    }

    @MainActor
    private func postBreakDueNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Notification Break Due Title")
        content.body = WellnessReminderText.sentenceFromDefaults()
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lingerly.break.due",
            content: content,
            trigger: nil
        )
        center?.removePendingNotificationRequests(withIdentifiers: ["lingerly.break.due"])
        center?.removeDeliveredNotifications(withIdentifiers: ["lingerly.break.due"])
        center?.add(request) { error in
            if let error {
                NSLog("Lingerly: failed to add break due notification: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func postConfirmSkipNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Notification Skip Confirm Title")
        content.body = String(localized: "Notification Skip Confirm Body")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lingerly.break.confirmSkip",
            content: content,
            trigger: nil
        )
        center?.removePendingNotificationRequests(withIdentifiers: ["lingerly.break.confirmSkip"])
        center?.removeDeliveredNotifications(withIdentifiers: ["lingerly.break.confirmSkip"])
        center?.add(request) { error in
            if let error {
                NSLog("Lingerly: failed to add confirm skip notification: \(error.localizedDescription)")
            }
        }
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
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
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
        completionHandler()
    }

    /// Ensures banners are still presented when the app is currently active.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
