import Foundation

// MARK: - App Configuration

struct AppConfig: Codable {
    var userEmail: String
    var therapistEmail: String
    var calendarKeyword: String
    var summarySendTime: DateComponents
    var claudeProjectURL: String
    var summaryLanguage: String
    var launchAtLogin: Bool

    // Cached values resolved at runtime — not user-editable
    var cachedOrgID: String
    var cachedProjectID: String

    static let defaultConfig = AppConfig(
        userEmail: "",
        therapistEmail: "",
        calendarKeyword: "Therapy",
        summarySendTime: DateComponents(hour: 20, minute: 0),
        claudeProjectURL: "",
        summaryLanguage: "English",
        launchAtLogin: false,
        cachedOrgID: "",
        cachedProjectID: ""
    )

    /// Extract the project UUID from the project URL.
    /// Handles: claude.ai/project/{uuid} or claude.ai/project/{org}/{uuid}
    var projectID: String {
        guard let url = URL(string: claudeProjectURL) else { return cachedProjectID }
        let components = url.pathComponents  // e.g. ["/", "project", "{uuid}"]
        guard components.count >= 3, components[1] == "project" else { return cachedProjectID }
        return components.last ?? cachedProjectID
    }

    static let configFileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TherapyJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.configFileURL, options: .atomic)
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configFileURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .defaultConfig
        }
        return config
    }
}

// MARK: - Calendar Event

struct TherapyEvent {
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarName: String
}

// MARK: - Claude.ai Conversation Models

struct ClaudeConversation: Codable {
    let uuid: String
    let name: String
    let createdAt: String
    let updatedAt: String
    let project: ClaudeConversationProject?

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case project
    }
}

struct ClaudeConversationProject: Codable {
    let uuid: String
    let name: String
}

struct ClaudeChatMessage: Codable {
    let uuid: String
    let text: String
    let sender: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case uuid
        case text
        case sender
        case createdAt = "created_at"
    }
}

struct ClaudeConversationDetail: Codable {
    let uuid: String
    let name: String
    let chatMessages: [ClaudeChatMessage]

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case chatMessages = "chat_messages"
    }
}

// MARK: - Summary

struct JournalSummary {
    let content: String
    let generatedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let sessionDate: Date

    var emailSubject: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return "Therapy prep — \(formatter.string(from: sessionDate))"
    }

    var emailBody: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let startStr = formatter.string(from: periodStart)
        let endStr = formatter.string(from: periodEnd)
        return """
        \(content)

        ---
        This summary was auto-generated from your Claude journal entries from \(startStr) to \(endStr).
        """
    }
}

// MARK: - Summary Status

enum SummaryStatus: Codable {
    case sent(date: Date)
    case failed(date: Date, error: String)
    case none

    var displayString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        switch self {
        case .sent(let date):
            return "\(formatter.string(from: date)) — sent"
        case .failed(let date, _):
            return "\(formatter.string(from: date)) — failed"
        case .none:
            return "No summary generated yet"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, date, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "sent":
            let date = try container.decode(Date.self, forKey: .date)
            self = .sent(date: date)
        case "failed":
            let date = try container.decode(Date.self, forKey: .date)
            let error = try container.decode(String.self, forKey: .error)
            self = .failed(date: date, error: error)
        default:
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sent(let date):
            try container.encode("sent", forKey: .type)
            try container.encode(date, forKey: .date)
        case .failed(let date, let error):
            try container.encode("failed", forKey: .type)
            try container.encode(date, forKey: .date)
            try container.encode(error, forKey: .error)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
}

