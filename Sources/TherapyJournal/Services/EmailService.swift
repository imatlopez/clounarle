import Foundation
import AppKit

@MainActor
final class EmailService {
    static let shared = EmailService()

    private init() {}

    /// Send the therapy summary email via the local Mail.app.
    func sendSummaryEmail(summary: JournalSummary) async throws {
        let config = AppConfig.load()
        guard !config.userEmail.isEmpty else {
            throw EmailError.userEmailNotConfigured
        }
        guard !config.therapistEmail.isEmpty else {
            throw EmailError.therapistEmailNotConfigured
        }

        let recipients = [config.userEmail, config.therapistEmail]
        let subject = summary.emailSubject
        let body = summary.emailBody

        try await sendViaMailApp(to: recipients, subject: subject, body: body)

        AppLogger.shared.info("Summary email sent via Mail.app to \(config.userEmail) and \(config.therapistEmail)")
    }

    /// Send an email using Mail.app via AppleScript.
    private func sendViaMailApp(to recipients: [String], subject: String, body: String) async throws {
        // Escape special characters for AppleScript string literals
        let escapedSubject = escapeForAppleScript(subject)
        let escapedBody = escapeForAppleScript(body)

        var recipientLines = ""
        for address in recipients {
            let escaped = escapeForAppleScript(address)
            recipientLines += "make new to recipient at end of to recipients with properties {address:\"\(escaped)\"}\n"
        }

        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(escapedSubject)", content:"\(escapedBody)", visible:false}
            tell newMessage
                \(recipientLines)
            end tell
            send newMessage
        end tell
        """

        let result = try await runAppleScript(script)

        if let errorMessage = result.error {
            AppLogger.shared.error("Mail.app AppleScript error: \(errorMessage)")
            throw EmailError.sendFailed(errorMessage)
        }
    }

    // MARK: - AppleScript Execution

    private struct AppleScriptResult {
        let output: String?
        let error: String?
    }

    private func runAppleScript(_ source: String) async throws -> AppleScriptResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorDict: NSDictionary?
                let appleScript = NSAppleScript(source: source)
                let output = appleScript?.executeAndReturnError(&errorDict)

                if let errorDict = errorDict {
                    let errorMessage = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(returning: AppleScriptResult(output: nil, error: errorMessage))
                } else {
                    continuation.resume(returning: AppleScriptResult(output: output?.stringValue, error: nil))
                }
            }
        }
    }

    // MARK: - Helpers

    private func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Errors

enum EmailError: LocalizedError {
    case userEmailNotConfigured
    case therapistEmailNotConfigured
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .userEmailNotConfigured: return "Your email address is not configured."
        case .therapistEmailNotConfigured: return "Therapist email address is not configured."
        case .sendFailed(let reason): return "Failed to send email via Mail.app: \(reason)"
        }
    }
}
