import Foundation

@MainActor
final class ClaudeConversationFetcher {
    static let shared = ClaudeConversationFetcher()

    private let baseURL = "https://claude.ai/api"

    private init() {}

    /// Resolve the organization ID from the claude.ai API.
    /// Caches the result in AppConfig for future use.
    func resolveOrgID(sessionKey: String) async throws -> String {
        // Check cache first
        let config = AppConfig.load()
        if !config.cachedOrgID.isEmpty {
            return config.cachedOrgID
        }

        AppLogger.shared.info("Resolving organization ID from claude.ai...")

        let url = URL(string: "\(baseURL)/organizations")!
        var request = URLRequest(url: url)
        request.setValue(sessionKey, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            AppLogger.shared.debug("GET /api/organizations → HTTP \(statusCode)")
            if statusCode == 401 || statusCode == 403 {
                let body = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
                AppLogger.shared.error("Auth rejected (\(statusCode)): \(body)")
                NotificationManager.shared.notifySessionCookieExpired()
                throw ClaudeFetchError.sessionExpired
            }
            guard statusCode == 200 else {
                let body = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
                AppLogger.shared.error("Unexpected status \(statusCode): \(body)")
                throw ClaudeFetchError.apiFailed(statusCode: statusCode)
            }
        }

        let orgs = try JSONDecoder().decode([ClaudeOrganization].self, from: data)

        guard let orgID = orgs.first?.uuid else {
            throw ClaudeFetchError.orgNotFound
        }

        // Cache it
        var updatedConfig = config
        updatedConfig.cachedOrgID = orgID
        try? updatedConfig.save()

        AppLogger.shared.info("Resolved organization ID: \(orgID)")
        return orgID
    }

    /// Fetch recent conversations from the user's Claude.ai journal project.
    func fetchRecentJournalEntries(since: Date) async throws -> [ClaudeConversationDetail] {
        let config = AppConfig.load()
        let projectID = config.projectID
        guard !projectID.isEmpty else {
            throw ClaudeFetchError.projectNotConfigured
        }

        let sessionKey = try getSessionKey()
        let orgID = try await resolveOrgID(sessionKey: sessionKey)

        // Step 1: List conversations in the project
        let conversations = try await listProjectConversations(
            orgID: orgID,
            projectID: projectID,
            sessionKey: sessionKey
        )

        // Step 2: Filter to conversations updated since the start date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let recentConversations = conversations.filter { convo in
            if let updatedDate = formatter.date(from: convo.updatedAt) {
                return updatedDate >= since
            }
            return false
        }

        AppLogger.shared.info("Found \(recentConversations.count) conversations since \(since)")

        // Step 3: Fetch full details for each recent conversation
        var details: [ClaudeConversationDetail] = []
        for convo in recentConversations {
            do {
                let detail = try await fetchConversationDetail(
                    orgID: orgID,
                    conversationID: convo.uuid,
                    sessionKey: sessionKey
                )
                details.append(detail)
            } catch {
                AppLogger.shared.warn("Failed to fetch conversation \(convo.uuid): \(error)")
            }
        }

        return details
    }

    // MARK: - API Calls

    private func listProjectConversations(orgID: String, projectID: String, sessionKey: String) async throws -> [ClaudeConversation] {
        let url = URL(string: "\(baseURL)/organizations/\(orgID)/projects/\(projectID)/conversations")!
        var request = URLRequest(url: url)
        request.setValue(sessionKey, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                NotificationManager.shared.notifySessionCookieExpired()
                throw ClaudeFetchError.sessionExpired
            }
            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                AppLogger.shared.error("Claude.ai API error (\(httpResponse.statusCode)): \(body)")
                throw ClaudeFetchError.apiFailed(statusCode: httpResponse.statusCode)
            }
        }

        return try JSONDecoder().decode([ClaudeConversation].self, from: data)
    }

    private func fetchConversationDetail(orgID: String, conversationID: String, sessionKey: String) async throws -> ClaudeConversationDetail {
        let url = URL(string: "\(baseURL)/organizations/\(orgID)/chat_conversations/\(conversationID)")!
        var request = URLRequest(url: url)
        request.setValue(sessionKey, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                throw ClaudeFetchError.sessionExpired
            }
            guard httpResponse.statusCode == 200 else {
                throw ClaudeFetchError.apiFailed(statusCode: httpResponse.statusCode)
            }
        }

        return try JSONDecoder().decode(ClaudeConversationDetail.self, from: data)
    }

    // MARK: - Helpers

    private func getSessionKey() throws -> String {
        do {
            return try KeychainManager.shared.retrieve(key: .claudeSessionKey)
        } catch {
            NotificationManager.shared.notifySessionCookieExpired()
            throw ClaudeFetchError.sessionKeyMissing
        }
    }
}

// MARK: - Errors

// MARK: - Organization Model

struct ClaudeOrganization: Codable {
    let uuid: String
    let name: String?
}

// MARK: - Errors

enum ClaudeFetchError: LocalizedError {
    case projectNotConfigured
    case sessionKeyMissing
    case sessionExpired
    case orgNotFound
    case apiFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .projectNotConfigured:
            return "Claude journal project not configured. Paste your Project URL in Preferences."
        case .sessionKeyMissing:
            return "Claude session key not found. Please enter it in Preferences."
        case .sessionExpired:
            return "Claude session cookie has expired. Please update it in Preferences."
        case .orgNotFound:
            return "Could not resolve your Claude organization. Check your session key."
        case .apiFailed(let code):
            return "Claude.ai API request failed with status \(code)."
        }
    }
}
