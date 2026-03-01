import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private init() {}

    func requestPermission() {
        guard isAvailable else {
            AppLogger.shared.warn("Notifications unavailable — no bundle identifier. Run as .app bundle.")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.shared.error("Notification permission error: \(error.localizedDescription)")
            } else if granted {
                AppLogger.shared.info("Notification permission granted")
            }
        }
    }

    func sendNotification(title: String, body: String, identifier: String = UUID().uuidString, categoryIdentifier: String? = nil) {
        guard isAvailable else {
            AppLogger.shared.warn("Notification skipped (no bundle): \(title) — \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let cat = categoryIdentifier {
            content.categoryIdentifier = cat
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.shared.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    func notifySessionCookieExpired() {
        sendNotification(
            title: "Therapy Journal",
            body: "Your Claude session cookie has expired. Please update it in Preferences.",
            identifier: "session-cookie-expired"
        )
    }

    func notifyEmailFailed(error: String) {
        sendNotification(
            title: "Therapy Journal — Email Failed",
            body: "Failed to send therapy summary email. \(error). Open the app to retry.",
            identifier: "email-failed",
            categoryIdentifier: "EMAIL_RETRY"
        )
    }

    func notifySummarySent(sessionDate: Date) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        sendNotification(
            title: "Therapy Journal",
            body: "Summary for your \(formatter.string(from: sessionDate)) session has been sent.",
            identifier: "summary-sent"
        )
    }

    func notifyReportSkipped(reason: String) {
        sendNotification(
            title: "Therapy Journal — Report Skipped",
            body: reason,
            identifier: "report-skipped"
        )
    }
}
