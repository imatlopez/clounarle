import Foundation

/// Schedules nightly checks for upcoming therapy sessions and triggers the summary pipeline.
@MainActor
final class NightlyScheduler {
    static let shared = NightlyScheduler()

    private var timer: Timer?
    private var isRunning = false

    private init() {}

    /// Start the nightly scheduler. Checks every minute if it's time to run.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        AppLogger.shared.info("Nightly scheduler started")

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIfTimeToRun()
            }
        }
        // Also check immediately on start
        checkIfTimeToRun()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        AppLogger.shared.info("Nightly scheduler stopped")
    }

    // MARK: - Check Logic

    private var lastRunDate: String?

    private func checkIfTimeToRun() {
        let config = AppConfig.load()
        let calendar = Calendar.current
        let now = Date()

        let targetHour = config.summarySendTime.hour ?? 20
        let targetMinute = config.summarySendTime.minute ?? 0

        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        // Check if we're at the target time (within the same minute)
        guard currentHour == targetHour && currentMinute == targetMinute else {
            return
        }

        // Prevent running more than once per day
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: now)

        guard lastRunDate != todayString else { return }
        lastRunDate = todayString

        AppLogger.shared.info("Nightly check triggered at \(targetHour):\(String(format: "%02d", targetMinute))")

        Task {
            await runNightlyCheck()
        }
    }

    private func runNightlyCheck() async {
        do {
            guard let event = try await CalendarService.shared.checkForTomorrowSession() else {
                AppLogger.shared.info("No therapy session tomorrow — skipping summary")
                return
            }

            AppLogger.shared.info("Therapy session found tomorrow: \(event.title). Triggering summary pipeline.")
            await SummaryOrchestrator.shared.runSummaryPipeline(for: event)

        } catch {
            AppLogger.shared.error("Nightly check failed: \(error.localizedDescription)")
            // Silently log and retry next night as specified
        }
    }
}
