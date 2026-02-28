import Foundation
import EventKit

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let eventStore = EKEventStore()

    private init() {}

    /// Request calendar access from the user.
    func requestAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            AppLogger.shared.error("Calendar access request failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Check if tomorrow has a therapy session matching the configured keyword.
    func checkForTomorrowSession() async throws -> TherapyEvent? {
        let config = AppConfig.load()
        guard !config.calendarKeyword.isEmpty else {
            AppLogger.shared.warn("Calendar keyword not configured")
            return nil
        }

        // Ensure we have calendar access
        let status = EKEventStore.authorizationStatus(for: .event)
        if status != .fullAccess {
            let granted = await requestAccess()
            guard granted else {
                AppLogger.shared.warn("Calendar access not granted")
                return nil
            }
        }

        let calendar = Calendar.current
        let now = Date()
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let tomorrowEnd = calendar.date(byAdding: .day, value: 1, to: tomorrowStart) else {
            return nil
        }

        let predicate = eventStore.predicateForEvents(withStart: tomorrowStart, end: tomorrowEnd, calendars: nil)
        let events = eventStore.events(matching: predicate)

        let keyword = config.calendarKeyword.lowercased()
        for event in events {
            guard let title = event.title,
                  title.lowercased().contains(keyword) else { continue }

            AppLogger.shared.info("Found therapy session tomorrow: \(title) at \(event.startDate!)")
            return TherapyEvent(
                title: title,
                startDate: event.startDate,
                endDate: event.endDate,
                calendarName: event.calendar.title
            )
        }

        AppLogger.shared.info("No therapy session found for tomorrow")
        return nil
    }
}
