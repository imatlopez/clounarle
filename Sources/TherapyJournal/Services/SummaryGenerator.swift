import Foundation

@MainActor
final class SummaryGenerator {
    static let shared = SummaryGenerator()

    private let baseURL = "https://claude.ai/api"

    private init() {}

    /// Generate a structured therapy summary from journal conversations
    /// using the claude.ai session cookie (no API key required).
    func generateSummary(conversations: [ClaudeConversationDetail], sessionDate: Date, periodStart: Date, periodEnd: Date) async throws -> JournalSummary {
        let sessionKey = try getSessionKey()
        let config = AppConfig.load()

        guard !config.claudeProjectOrgID.isEmpty else {
            throw SummaryError.orgNotConfigured
        }

        let journalText = formatConversationsForPrompt(conversations)

        guard !journalText.isEmpty else {
            throw SummaryError.noJournalEntries
        }

        let prompt = """
        \(systemPrompt)

        \(userMessage(journalText: journalText))
        """

        let conversationUUID = UUID().uuidString.lowercased()
        let orgID = config.claudeProjectOrgID

        AppLogger.shared.info("Sending journal entries to Claude for summary generation...")

        // 1. Create a temporary conversation and stream the response
        let summaryText = try await sendChatMessage(
            orgID: orgID,
            conversationUUID: conversationUUID,
            prompt: prompt,
            sessionKey: sessionKey
        )

        // 2. Clean up — delete the temporary conversation
        await deleteConversation(orgID: orgID, conversationUUID: conversationUUID, sessionKey: sessionKey)

        AppLogger.shared.info("Summary generated successfully")

        return JournalSummary(
            content: summaryText,
            generatedAt: Date(),
            periodStart: periodStart,
            periodEnd: periodEnd,
            sessionDate: sessionDate
        )
    }

    // MARK: - Chat via claude.ai

    private func sendChatMessage(orgID: String, conversationUUID: String, prompt: String, sessionKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/organizations/\(orgID)/chat_conversations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "uuid": conversationUUID,
            "organization_uuid": orgID,
            "name": "",
            "prompt": prompt,
            "model": "claude-sonnet-4-6",
            "timezone": TimeZone.current.identifier,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummaryError.apiError
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            NotificationManager.shared.notifySessionCookieExpired()
            throw SummaryError.sessionExpired
        }

        guard httpResponse.statusCode == 200 else {
            AppLogger.shared.error("Claude.ai chat error: HTTP \(httpResponse.statusCode)")
            throw SummaryError.apiError
        }

        // Parse SSE stream — accumulate completion text deltas
        var accumulated = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let data = payload.data(using: .utf8) else { continue }

            if let event = try? JSONDecoder().decode(SSECompletionEvent.self, from: data) {
                if let text = event.completion {
                    accumulated += text
                }
                if event.stopReason == "end_turn" {
                    break
                }
            }
        }

        guard !accumulated.isEmpty else {
            throw SummaryError.noContentInResponse
        }

        return accumulated
    }

    private func deleteConversation(orgID: String, conversationUUID: String, sessionKey: String) async {
        let url = URL(string: "\(baseURL)/organizations/\(orgID)/chat_conversations/\(conversationUUID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
                AppLogger.shared.warn("Failed to delete summary conversation \(conversationUUID): HTTP \(httpResponse.statusCode)")
            } else {
                AppLogger.shared.debug("Deleted summary conversation \(conversationUUID)")
            }
        } catch {
            AppLogger.shared.warn("Failed to delete summary conversation: \(error.localizedDescription)")
        }
    }

    // MARK: - Session Key

    private func getSessionKey() throws -> String {
        do {
            return try KeychainManager.shared.retrieve(key: .claudeSessionKey)
        } catch {
            NotificationManager.shared.notifySessionCookieExpired()
            throw SummaryError.sessionKeyMissing
        }
    }

    // MARK: - Prompt

    private let systemPrompt = """
    You are a helpful assistant that creates structured therapy session prep summaries. \
    You will be given journal entries from a person's therapy journal (conversations with an AI journaling companion). \
    Your job is to synthesize these entries into a concise, useful summary their therapist can review before the session.

    Format your response EXACTLY as follows (use this exact structure):

    **This week's themes**
    - [theme 1]
    - [theme 2]
    - [add more as needed]

    **Emotional tone**
    - [Brief reading of overall mood/tone across entries, e.g. "Anxious early in the week, more settled by Thursday"]

    **Key highlights**
    - "[verbatim quote or close paraphrase worth surfacing]"
    - "[another highlight]"
    - [add more as needed]

    **Possible things to explore in session**
    - [suggestion 1]
    - [suggestion 2]
    - [add more as needed]

    Guidelines:
    - Be concise but thorough
    - Use the person's own words where possible
    - Do not diagnose or give clinical opinions
    - Focus on themes, patterns, and emotional content
    - Highlight anything that seems particularly significant or recurring
    """

    private func userMessage(journalText: String) -> String {
        """
        Here are journal entries from the past week. Please create a therapy prep summary.

        ---
        \(journalText)
        ---
        """
    }

    // MARK: - Formatting

    private func formatConversationsForPrompt(_ conversations: [ClaudeConversationDetail]) -> String {
        var sections: [String] = []

        for convo in conversations {
            var lines: [String] = []
            lines.append("### \(convo.name)")
            lines.append("")

            for message in convo.chatMessages {
                let role = message.sender == "human" ? "Journal entry" : "Companion"
                lines.append("**\(role):** \(message.text)")
                lines.append("")
            }

            sections.append(lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n---\n\n")
    }
}

// MARK: - SSE Event Model

private struct SSECompletionEvent: Decodable {
    let type: String?
    let completion: String?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type, completion
        case stopReason = "stop_reason"
    }
}

// MARK: - Errors

enum SummaryError: LocalizedError {
    case noJournalEntries
    case orgNotConfigured
    case sessionKeyMissing
    case sessionExpired
    case apiError
    case noContentInResponse

    var errorDescription: String? {
        switch self {
        case .noJournalEntries: return "No journal entries found for the period."
        case .orgNotConfigured: return "Organization ID not configured. Set it in Preferences."
        case .sessionKeyMissing: return "Claude session key not found. Please enter it in Preferences."
        case .sessionExpired: return "Claude session cookie has expired. Please update it in Preferences."
        case .apiError: return "Claude.ai chat request failed."
        case .noContentInResponse: return "Claude.ai returned an empty response."
        }
    }
}
