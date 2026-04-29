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

    /// Find the earliest therapy session matching the configured keyword that starts within
    /// `daysAhead` calendar days of today (inclusive of today and the day `daysAhead` from now).
    func findUpcomingSession(daysAhead: Int) async throws -> TherapyEvent? {
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
        let searchStart = calendar.startOfDay(for: now)
        guard let searchEnd = calendar.date(byAdding: .day, value: daysAhead + 1, to: searchStart) else {
            return nil
        }

        let predicate = eventStore.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: nil)
        let events = eventStore.events(matching: predicate)

        let keyword = config.calendarKeyword.lowercased()
        let match = events
            .filter { ($0.title ?? "").lowercased().contains(keyword) }
            .min(by: { $0.startDate < $1.startDate })

        guard let event = match, let title = event.title else {
            AppLogger.shared.info("No therapy session found within \(daysAhead) day(s)")
            return nil
        }

        AppLogger.shared.info("Found therapy session \(title) at \(event.startDate!)")
        return TherapyEvent(
            title: title,
            startDate: event.startDate,
            endDate: event.endDate,
            calendarName: event.calendar.title
        )
    }
}
