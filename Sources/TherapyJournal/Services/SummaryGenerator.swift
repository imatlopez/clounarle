import Foundation

final class SummaryGenerator {
    static let shared = SummaryGenerator()

    private init() {}

    /// Generate a structured therapy summary from journal conversations.
    func generateSummary(conversations: [ClaudeConversationDetail], sessionDate: Date, periodStart: Date, periodEnd: Date) async throws -> JournalSummary {
        let apiKey = try KeychainManager.shared.retrieve(key: .claudeAPIKey)

        let journalText = formatConversationsForPrompt(conversations)

        guard !journalText.isEmpty else {
            throw SummaryError.noJournalEntries
        }

        let systemPrompt = """
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

        let userMessage = """
        Here are journal entries from the past week. Please create a therapy prep summary.

        ---
        \(journalText)
        ---
        """

        let requestBody = ClaudeAPIRequest(
            model: "claude-sonnet-4-6",
            maxTokens: 2048,
            messages: [
                ClaudeAPIMessage(role: "user", content: "\(systemPrompt)\n\n\(userMessage)")
            ]
        )

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONEncoder().encode(requestBody)

        AppLogger.shared.info("Sending journal entries to Claude API for summary generation...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            AppLogger.shared.error("Claude API error: \(body)")
            throw SummaryError.apiError
        }

        let apiResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)

        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }),
              let summaryText = textContent.text else {
            throw SummaryError.noContentInResponse
        }

        AppLogger.shared.info("Summary generated successfully")

        return JournalSummary(
            content: summaryText,
            generatedAt: Date(),
            periodStart: periodStart,
            periodEnd: periodEnd,
            sessionDate: sessionDate
        )
    }

    // MARK: - Helpers

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

// MARK: - Errors

enum SummaryError: LocalizedError {
    case noJournalEntries
    case apiError
    case noContentInResponse

    var errorDescription: String? {
        switch self {
        case .noJournalEntries: return "No journal entries found for the period."
        case .apiError: return "Claude API request failed."
        case .noContentInResponse: return "Claude API returned an empty response."
        }
    }
}
