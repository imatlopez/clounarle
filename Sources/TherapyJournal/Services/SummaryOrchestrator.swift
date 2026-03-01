import Foundation

/// Orchestrates the full summary flow: fetch conversations, generate summary, send email.
@MainActor
final class SummaryOrchestrator: ObservableObject {
    static let shared = SummaryOrchestrator()

    @Published var isGenerating = false
    @Published var lastStatus: SummaryStatus = .none

    private init() {
        loadLastStatus()
    }

    /// Run the full summary pipeline for a therapy session.
    func runSummaryPipeline(for event: TherapyEvent) async {
        isGenerating = true

        do {
            AppLogger.shared.info("Starting summary pipeline for session: \(event.title)")

            let (periodStart, periodEnd) = fetchPeriod()

            // Step 1: Fetch journal conversations
            AppLogger.shared.info("Fetching journal conversations since \(periodStart)...")
            let conversations = try await ClaudeConversationFetcher.shared.fetchRecentJournalEntries(since: periodStart)

            guard !conversations.isEmpty else {
                let reason = "No journal entries found since \(periodStart.formatted(date: .abbreviated, time: .omitted)). Report skipped."
                AppLogger.shared.warn(reason)
                updateStatus(.skipped(date: Date(), reason: reason))
                NotificationManager.shared.notifyReportSkipped(reason: reason)
                isGenerating = false
                return
            }

            // Step 2: Generate summary
            AppLogger.shared.info("Generating summary from \(conversations.count) conversations...")
            let summary = try await SummaryGenerator.shared.generateSummary(
                conversations: conversations,
                sessionDate: event.startDate,
                periodStart: periodStart,
                periodEnd: periodEnd
            )

            // Step 3: Send email via Mail.app
            AppLogger.shared.info("Sending summary email...")
            try await EmailService.shared.sendSummaryEmail(summary: summary)

            // Success — persist session date so next run covers from here
            saveLastSessionDate(event.startDate)
            updateStatus(.sent(date: Date()))
            NotificationManager.shared.notifySummarySent(sessionDate: event.startDate)
            AppLogger.shared.info("Summary pipeline completed successfully")

        } catch {
            AppLogger.shared.error("Summary pipeline failed: \(error.localizedDescription)")
            updateStatus(.failed(date: Date(), error: error.localizedDescription))
            NotificationManager.shared.notifyEmailFailed(error: error.localizedDescription)
        }

        isGenerating = false
    }

    /// Manual trigger: generate and send summary now (uses tomorrow's session or a placeholder date).
    func generateNow() async {
        isGenerating = true

        do {
            if let event = try await CalendarService.shared.checkForTomorrowSession() {
                await runSummaryPipeline(for: event)
            } else {
                let placeholder = TherapyEvent(
                    title: "Manual Summary",
                    startDate: Date(),
                    endDate: Date(),
                    calendarName: "Manual"
                )
                await runSummaryPipeline(for: placeholder)
            }
        } catch {
            AppLogger.shared.error("Manual generation failed: \(error.localizedDescription)")
            updateStatus(.failed(date: Date(), error: error.localizedDescription))
            isGenerating = false
        }
    }

    /// Preview mode: fetch and generate summary without sending email.
    /// Returns the summary on success, nil on failure.
    func generatePreview() async -> JournalSummary? {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let (periodStart, periodEnd) = fetchPeriod()

            AppLogger.shared.info("Generating preview — fetching conversations since \(periodStart)...")
            let conversations = try await ClaudeConversationFetcher.shared.fetchRecentJournalEntries(since: periodStart)

            guard !conversations.isEmpty else {
                let reason = "No journal entries found since \(periodStart.formatted(date: .abbreviated, time: .omitted))."
                AppLogger.shared.warn(reason)
                updateStatus(.skipped(date: Date(), reason: reason))
                NotificationManager.shared.notifyReportSkipped(reason: reason)
                return nil
            }

            AppLogger.shared.info("Generating preview summary from \(conversations.count) conversations...")
            let sessionDate = (try? await CalendarService.shared.checkForTomorrowSession())?.startDate ?? Date()
            let summary = try await SummaryGenerator.shared.generateSummary(
                conversations: conversations,
                sessionDate: sessionDate,
                periodStart: periodStart,
                periodEnd: periodEnd
            )

            AppLogger.shared.info("Preview summary generated successfully")
            return summary

        } catch {
            AppLogger.shared.error("Preview generation failed: \(error.localizedDescription)")
            updateStatus(.failed(date: Date(), error: error.localizedDescription))
            return nil
        }
    }

    // MARK: - Time Window

    /// Returns (periodStart, periodEnd) — start is lastSessionDate if saved, else 7-day fallback.
    private func fetchPeriod() -> (Date, Date) {
        let periodEnd = Date()
        let config = AppConfig.load()
        let periodStart = config.lastSessionDate
            ?? Calendar.current.date(byAdding: .day, value: -7, to: periodEnd)!
        return (periodStart, periodEnd)
    }

    private func saveLastSessionDate(_ date: Date) {
        var config = AppConfig.load()
        config.lastSessionDate = date
        try? config.save()
        AppLogger.shared.info("Saved lastSessionDate: \(date)")
    }

    // MARK: - Status Persistence

    private func updateStatus(_ status: SummaryStatus) {
        lastStatus = status
        saveLastStatus(status)
    }

    private nonisolated let statusFileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TherapyJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last_status.json")
    }()

    private func saveLastStatus(_ status: SummaryStatus) {
        do {
            let data = try JSONEncoder().encode(status)
            try data.write(to: statusFileURL, options: .atomic)
        } catch {
            AppLogger.shared.error("Failed to save status: \(error)")
        }
    }

    private func loadLastStatus() {
        guard let data = try? Data(contentsOf: statusFileURL),
              let status = try? JSONDecoder().decode(SummaryStatus.self, from: data) else {
            lastStatus = .none
            return
        }
        lastStatus = status
    }
}
