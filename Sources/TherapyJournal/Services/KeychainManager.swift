import Foundation
import Security

final class KeychainManager: Sendable {
    static let shared = KeychainManager()

    private let service = "com.therapyjournal.app"

    private init() {}

    enum KeychainKey: String {
        case claudeSessionKey = "claude_session_key"
        case claudeAPIKey = "claude_api_key"
    }

    // MARK: - String Values

    func save(key: KeychainKey, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(key: key.rawValue, data: data)
    }

    func retrieve(key: KeychainKey) throws -> String {
        let data = try retrieve(key: key.rawValue)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    func delete(key: KeychainKey) throws {
        try delete(key: key.rawValue)
    }

    // MARK: - Codable Values

    func saveCodable<T: Codable>(key: KeychainKey, value: T) throws {
        let data = try JSONEncoder().encode(value)
        try save(key: key.rawValue, data: data)
    }

    func retrieveCodable<T: Codable>(key: KeychainKey, type: T.Type) throws -> T {
        let data = try retrieve(key: key.rawValue)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Low-Level Keychain Operations

    private func save(key: String, data: Data) throws {
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            AppLogger.shared.error("Keychain save failed for \(key): \(status)")
            throw KeychainError.saveFailed(status)
        }
        AppLogger.shared.debug("Keychain saved: \(key)")
    }

    private func retrieve(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.itemNotFound
        }
        return data
    }

    private func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Convenience

    func hasKey(_ key: KeychainKey) -> Bool {
        do {
            _ = try retrieve(key: key.rawValue)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case itemNotFound
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode value for Keychain"
        case .decodingFailed: return "Failed to decode value from Keychain"
        case .saveFailed(let status): return "Keychain save failed with status \(status)"
        case .itemNotFound: return "Item not found in Keychain"
        case .deleteFailed(let status): return "Keychain delete failed with status \(status)"
        }
    }
}
