import Foundation

/// Schedules nightly checks for upcoming therapy sessions and triggers the summary pipeline.
@MainActor
final class NightlyScheduler {
    static let shared = NightlyScheduler()

    private var timer: Timer?
    private var isRunning = false

    /// In-memory guard so a transient pipeline failure doesn't get retried every minute.
    /// Keyed by `event.startDate`; cleared on relaunch so a fresh attempt is possible.
    private var attemptedEventDate: Date?

    private init() {}

    /// Start the scheduler. Checks immediately (catch-up) and once per minute thereafter.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        AppLogger.shared.info("Nightly scheduler started")

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tickIfDue()
            }
        }
        Task { @MainActor in
            await tickIfDue()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        AppLogger.shared.info("Nightly scheduler stopped")
    }

    // MARK: - Due Check

    /// Single check that handles both the regular schedule and on-launch catch-up:
    /// fires whenever there's an upcoming therapy event whose scheduled fire-time has
    /// passed and which hasn't already been sent for.
    private func tickIfDue() async {
        let config = AppConfig.load()
        let leadDays = max(1, config.summaryLeadDays)

        let event: TherapyEvent?
        do {
            event = try await CalendarService.shared.findUpcomingSession(daysAhead: leadDays)
        } catch {
            AppLogger.shared.error("Calendar lookup failed: \(error.localizedDescription)")
            return
        }
        guard let event else { return }

        let cal = Calendar.current

        if let lastSent = config.lastSessionDate,
           cal.isDate(lastSent, inSameDayAs: event.startDate) {
            return
        }

        if let attempted = attemptedEventDate,
           cal.isDate(attempted, inSameDayAs: event.startDate) {
            return
        }

        let fireTime = scheduledFireTime(for: event, config: config)
        guard Date() >= fireTime else { return }

        AppLogger.shared.info("Scheduled fire-time reached for \(event.title) — running pipeline")
        attemptedEventDate = event.startDate
        await SummaryOrchestrator.shared.runSummaryPipeline(for: event)
    }

    /// Scheduled fire instant: `summaryLeadDays` days before the event's day, at the
    /// configured `summarySendTime`.
    private func scheduledFireTime(for event: TherapyEvent, config: AppConfig) -> Date {
        let cal = Calendar.current
        let leadDays = max(1, config.summaryLeadDays)
        let eventDay = cal.startOfDay(for: event.startDate)
        guard let fireDay = cal.date(byAdding: .day, value: -leadDays, to: eventDay) else {
            return event.startDate
        }
        return cal.date(
            bySettingHour: config.summarySendTime.hour ?? 20,
            minute: config.summarySendTime.minute ?? 0,
            second: 0,
            of: fireDay
        ) ?? fireDay
    }
}
