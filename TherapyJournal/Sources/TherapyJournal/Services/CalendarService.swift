import Foundation

final class CalendarService {
    static let shared = CalendarService()

    private init() {}

    /// Check if tomorrow has a therapy session matching the configured keyword.
    func checkForTomorrowSession() async throws -> TherapyEvent? {
        let config = AppConfig.load()
        guard !config.calendarKeyword.isEmpty else {
            AppLogger.shared.warn("Calendar keyword not configured")
            return nil
        }

        let accessToken = try await GoogleOAuthManager.shared.getValidAccessToken()

        let calendar = Calendar.current
        let now = Date()
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let tomorrowEnd = calendar.date(byAdding: .day, value: 1, to: tomorrowStart) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let timeMin = formatter.string(from: tomorrowStart)
        let timeMax = formatter.string(from: tomorrowEnd)

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "q", value: config.calendarKeyword),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            AppLogger.shared.error("Calendar API error: \(body)")
            throw CalendarError.apiFailed
        }

        let eventsResponse = try JSONDecoder().decode(GoogleCalendarEventsResponse.self, from: data)

        guard let items = eventsResponse.items else { return nil }

        // Find the first event matching the keyword
        let keyword = config.calendarKeyword.lowercased()
        for event in items {
            guard let summary = event.summary,
                  summary.lowercased().contains(keyword) else { continue }

            let startDate = parseEventDate(event.start)
            let endDate = parseEventDate(event.end)

            if let start = startDate {
                AppLogger.shared.info("Found therapy session tomorrow: \(summary) at \(start)")
                return TherapyEvent(
                    title: summary,
                    startDate: start,
                    endDate: endDate ?? start,
                    calendarName: "Primary"
                )
            }
        }

        AppLogger.shared.info("No therapy session found for tomorrow")
        return nil
    }

    private func parseEventDate(_ dt: GoogleCalendarDateTime?) -> Date? {
        guard let dt else { return nil }

        if let dateTime = dt.dateTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateTime)
        }

        if let dateStr = dt.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateStr)
        }

        return nil
    }
}

enum CalendarError: LocalizedError {
    case apiFailed

    var errorDescription: String? {
        switch self {
        case .apiFailed: return "Google Calendar API request failed"
        }
    }
}
