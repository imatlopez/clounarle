import Foundation

final class GmailService {
    static let shared = GmailService()

    private init() {}

    /// Send the therapy summary email to the user and therapist.
    func sendSummaryEmail(summary: JournalSummary) async throws {
        let config = AppConfig.load()
        guard !config.userEmail.isEmpty else {
            throw GmailError.userEmailNotConfigured
        }
        guard !config.therapistEmail.isEmpty else {
            throw GmailError.therapistEmailNotConfigured
        }

        let accessToken = try await GoogleOAuthManager.shared.getValidAccessToken()

        let rawMessage = buildRawMessage(
            from: config.userEmail,
            to: [config.userEmail, config.therapistEmail],
            subject: summary.emailSubject,
            body: summary.emailBody
        )

        let base64Message = rawMessage
            .data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messageBody = GmailMessage(raw: base64Message)
        request.httpBody = try JSONEncoder().encode(messageBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            AppLogger.shared.error("Gmail API error: \(body)")
            throw GmailError.sendFailed
        }

        AppLogger.shared.info("Summary email sent successfully to \(config.userEmail) and \(config.therapistEmail)")
    }

    // MARK: - Helpers

    private func buildRawMessage(from: String, to: [String], subject: String, body: String) -> String {
        let toHeader = to.joined(separator: ", ")
        return """
        From: \(from)\r
        To: \(toHeader)\r
        Subject: \(subject)\r
        Content-Type: text/plain; charset=UTF-8\r
        \r
        \(body)
        """
    }
}

// MARK: - Errors

enum GmailError: LocalizedError {
    case userEmailNotConfigured
    case therapistEmailNotConfigured
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .userEmailNotConfigured: return "Your email address is not configured."
        case .therapistEmailNotConfigured: return "Therapist email address is not configured."
        case .sendFailed: return "Failed to send email via Gmail API."
        }
    }
}
