import Foundation

/// Orchestrates the full summary flow: fetch conversations, generate summary, send email.
final class SummaryOrchestrator: ObservableObject {
    static let shared = SummaryOrchestrator()

    @Published var isGenerating = false
    @Published var lastStatus: SummaryStatus = .none

    private init() {
        loadLastStatus()
    }

    /// Run the full summary pipeline for a therapy session.
    func runSummaryPipeline(for event: TherapyEvent) async {
        await MainActor.run { self.isGenerating = true }

        do {
            AppLogger.shared.info("Starting summary pipeline for session: \(event.title)")

            // Determine the period to fetch (last 7 days)
            let periodEnd = Date()
            let periodStart = Calendar.current.date(byAdding: .day, value: -7, to: periodEnd)!

            // Step 1: Fetch journal conversations
            AppLogger.shared.info("Fetching journal conversations since \(periodStart)...")
            let conversations = try await ClaudeConversationFetcher.shared.fetchRecentJournalEntries(since: periodStart)

            guard !conversations.isEmpty else {
                AppLogger.shared.warn("No journal entries found for the past week")
                let status = SummaryStatus.failed(date: Date(), error: "No journal entries found")
                await updateStatus(status)
                return
            }

            // Step 2: Generate summary via Claude API
            AppLogger.shared.info("Generating summary from \(conversations.count) conversations...")
            let summary = try await SummaryGenerator.shared.generateSummary(
                conversations: conversations,
                sessionDate: event.startDate,
                periodStart: periodStart,
                periodEnd: periodEnd
            )

            // Step 3: Send email via Gmail
            AppLogger.shared.info("Sending summary email...")
            try await GmailService.shared.sendSummaryEmail(summary: summary)

            // Success
            let status = SummaryStatus.sent(date: Date())
            await updateStatus(status)
            NotificationManager.shared.notifySummarySent(sessionDate: event.startDate)
            AppLogger.shared.info("Summary pipeline completed successfully")

        } catch {
            AppLogger.shared.error("Summary pipeline failed: \(error.localizedDescription)")
            let status = SummaryStatus.failed(date: Date(), error: error.localizedDescription)
            await updateStatus(status)
            NotificationManager.shared.notifyEmailFailed(error: error.localizedDescription)
        }

        await MainActor.run { self.isGenerating = false }
    }

    /// Manual trigger: generate and send summary now (uses tomorrow's session or a placeholder date).
    func generateNow() async {
        await MainActor.run { self.isGenerating = true }

        do {
            // Check if there's a session tomorrow
            if let event = try await CalendarService.shared.checkForTomorrowSession() {
                await runSummaryPipeline(for: event)
            } else {
                // No session found — generate anyway with today's date
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
            let status = SummaryStatus.failed(date: Date(), error: error.localizedDescription)
            await updateStatus(status)
            await MainActor.run { self.isGenerating = false }
        }
    }

    // MARK: - Status Persistence

    private func updateStatus(_ status: SummaryStatus) async {
        await MainActor.run {
            self.lastStatus = status
        }
        saveLastStatus(status)
    }

    private let statusFileURL: URL = {
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
