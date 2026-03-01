import AppKit
import CryptoKit
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
    var lastSessionDate: Date?
    var alwaysRegenerate: Bool

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
        lastSessionDate: nil,
        alwaysRegenerate: false,
        cachedOrgID: "",
        cachedProjectID: ""
    )

    init(
        userEmail: String, therapistEmail: String, calendarKeyword: String,
        summarySendTime: DateComponents, claudeProjectURL: String, summaryLanguage: String,
        launchAtLogin: Bool, lastSessionDate: Date?, alwaysRegenerate: Bool,
        cachedOrgID: String, cachedProjectID: String
    ) {
        self.userEmail = userEmail
        self.therapistEmail = therapistEmail
        self.calendarKeyword = calendarKeyword
        self.summarySendTime = summarySendTime
        self.claudeProjectURL = claudeProjectURL
        self.summaryLanguage = summaryLanguage
        self.launchAtLogin = launchAtLogin
        self.lastSessionDate = lastSessionDate
        self.alwaysRegenerate = alwaysRegenerate
        self.cachedOrgID = cachedOrgID
        self.cachedProjectID = cachedProjectID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userEmail = try container.decode(String.self, forKey: .userEmail)
        therapistEmail = try container.decode(String.self, forKey: .therapistEmail)
        calendarKeyword = try container.decode(String.self, forKey: .calendarKeyword)
        summarySendTime = try container.decode(DateComponents.self, forKey: .summarySendTime)
        claudeProjectURL = try container.decode(String.self, forKey: .claudeProjectURL)
        summaryLanguage = try container.decode(String.self, forKey: .summaryLanguage)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        lastSessionDate = try container.decodeIfPresent(Date.self, forKey: .lastSessionDate)
        alwaysRegenerate = try container.decodeIfPresent(Bool.self, forKey: .alwaysRegenerate) ?? false
        cachedOrgID = try container.decode(String.self, forKey: .cachedOrgID)
        cachedProjectID = try container.decode(String.self, forKey: .cachedProjectID)
    }

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

struct JournalSummary: Codable {
    let content: String
    let generatedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let sessionDate: Date

    enum CodingKeys: String, CodingKey {
        case content, generatedAt, periodStart, periodEnd, sessionDate
    }

    var emailSubject: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return "Therapy prep — \(formatter.string(from: sessionDate))"
    }

    /// RTF email body built from NSAttributedString. Bypasses Mail.app's HTML parser
    /// entirely — AppleScript reads the file as «class RTF » styled text and sets it
    /// as the message content in rich-text mode.
    var emailBodyRTF: Data {
        get throws {
            let stripped = content
                .components(separatedBy: "\n")
                .filter { $0.trimmingCharacters(in: .whitespaces).range(of: #"^-{2,}$"#, options: .regularExpression) == nil }
                .joined(separator: "\n")
            let attrStr = markdownToAttributedString(stripped)

            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            let startStr = formatter.string(from: periodStart)
            let endStr = formatter.string(from: periodEnd)
            let footer = "\n\nAuto-generated from Claude journal entries from \(startStr) to \(endStr)."
            let footerAttr = NSAttributedString(string: footer, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor(white: 0.55, alpha: 1)
            ])
            let full = NSMutableAttributedString(attributedString: attrStr)
            full.append(footerAttr)

            return try full.data(
                from: NSRange(location: 0, length: full.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }
    }

    private func markdownToAttributedString(_ markdown: String) -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: 14)
        let bold = NSFont.boldSystemFont(ofSize: 14)
        let dark = NSColor(white: 0.07, alpha: 1)

        let headerStyle: NSMutableParagraphStyle = {
            let s = NSMutableParagraphStyle()
            s.paragraphSpacingBefore = 20
            s.paragraphSpacing = 6
            return s
        }()
        let bulletStyle: NSMutableParagraphStyle = {
            let s = NSMutableParagraphStyle()
            s.headIndent = 16
            s.firstLineHeadIndent = 0
            s.paragraphSpacing = 5
            return s
        }()
        let paraStyle: NSMutableParagraphStyle = {
            let s = NSMutableParagraphStyle()
            s.paragraphSpacing = 8
            s.lineSpacing = 2
            return s
        }()

        let result = NSMutableAttributedString()
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let str: NSAttributedString
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4 {
                let text = String(trimmed.dropFirst(2).dropLast(2))
                str = NSAttributedString(string: text + "\n", attributes: [
                    .font: bold, .foregroundColor: dark, .paragraphStyle: headerStyle
                ])
            } else if trimmed.range(of: #"^-{2,}$"#, options: .regularExpression) != nil {
                str = NSAttributedString(string: "\n")
            } else if line.hasPrefix("- ") {
                let text = String(line.dropFirst(2))
                let inline = parseInline(text, font: body, bold: bold, color: dark, style: bulletStyle)
                let bullet = NSMutableAttributedString(string: "•  ")
                bullet.addAttributes([.font: body, .foregroundColor: dark, .paragraphStyle: bulletStyle],
                                     range: NSRange(location: 0, length: bullet.length))
                bullet.append(inline)
                bullet.append(NSAttributedString(string: "\n"))
                str = bullet
            } else if trimmed.isEmpty {
                str = NSAttributedString(string: "\n")
            } else {
                let inline = parseInline(line, font: body, bold: bold, color: dark, style: paraStyle)
                let para = NSMutableAttributedString(attributedString: inline)
                para.append(NSAttributedString(string: "\n"))
                str = para
            }
            result.append(str)
        }
        return result
    }

    private func parseInline(_ text: String, font: NSFont, bold: NSFont,
                              color: NSColor, style: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var isBold = false
        for part in text.components(separatedBy: "**") {
            guard !part.isEmpty else { isBold.toggle(); continue }
            result.append(NSAttributedString(string: part, attributes: [
                .font: isBold ? bold : font,
                .foregroundColor: color,
                .paragraphStyle: style
            ]))
            isBold.toggle()
        }
        return result
    }
}

// MARK: - Cached Summary

struct CachedSummary: Codable {
    let cacheKey: String
    let summary: JournalSummary
    let cachedAt: Date

    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TherapyJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cached_summary.json")
    }()

    static func cacheKey(for conversations: [ClaudeConversation]) -> String {
        let input = conversations
            .sorted { $0.uuid < $1.uuid }
            .map { "\($0.uuid):\($0.updatedAt)" }
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func load() -> CachedSummary? {
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(CachedSummary.self, from: data) else {
            return nil
        }
        return cached
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.fileURL, options: .atomic)
    }
}

// MARK: - Summary Status

enum SummaryStatus: Codable {
    case sent(date: Date)
    case failed(date: Date, error: String)
    case skipped(date: Date, reason: String)
    case none

    var displayString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        switch self {
        case .sent(let date):
            return "Sent \(formatter.string(from: date))"
        case .failed(let date, _):
            return "Failed \(formatter.string(from: date))"
        case .skipped(let date, _):
            return "Skipped \(formatter.string(from: date))"
        case .none:
            return "No summary yet"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, date, error, reason
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
        case "skipped":
            let date = try container.decode(Date.self, forKey: .date)
            let reason = try container.decode(String.self, forKey: .reason)
            self = .skipped(date: date, reason: reason)
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
        case .skipped(let date, let reason):
            try container.encode("skipped", forKey: .type)
            try container.encode(date, forKey: .date)
            try container.encode(reason, forKey: .reason)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
}

