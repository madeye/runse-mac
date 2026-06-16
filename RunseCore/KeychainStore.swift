import Foundation
import Security

public protocol SecretStore: Sendable {
    func save(_ value: String, service: String, account: String) async throws
    func load(service: String, account: String) async throws -> String?
    func delete(service: String, account: String) async throws
}

public enum KeychainError: Error, LocalizedError, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            String(localized: "Keychain error \(Int(status)).", bundle: .runseCore)
        case .invalidData:
            String(localized: "The saved secret could not be decoded.", bundle: .runseCore)
        }
    }
}

public final class KeychainStore: SecretStore {
    private let accessGroup: String?

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    public func save(_ value: String, service: String, account: String) async throws {
        let data = Data(value.utf8)
        var query = baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func load(service: String, account: String) async throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    public func delete(service: String, account: String) async throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

public enum KeychainAccessGroup {
    public static func make(appIdentifierPrefix: String) -> String? {
        let prefix = appIdentifierPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, !prefix.contains("$(") else { return nil }
        return prefix + RunseConstants.keychainAccessGroup
    }

    public static func current(bundle: Bundle = .main) -> String? {
        guard let prefix = bundle.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty else {
            return nil
        }
        return make(appIdentifierPrefix: prefix)
    }
}

public actor InMemorySecretStore: SecretStore {
    private var storage: [String: String] = [:]

    public init() {}

    public func save(_ value: String, service: String, account: String) {
        storage[key(service: service, account: account)] = value
    }

    public func load(service: String, account: String) -> String? {
        storage[key(service: service, account: account)]
    }

    public func delete(service: String, account: String) {
        storage.removeValue(forKey: key(service: service, account: account))
    }

    private func key(service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}

public enum SecretSeeder {
    public static let service = "Runse.ProviderAPIKey"

    public static func seedDefaultNVIDIAIfNeeded(secretStore: SecretStore, buildSettingValue: String?) async throws {
        let existing = try await secretStore.load(service: service, account: RunseConstants.defaultProfileID)
        if let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let trimmed = (buildSettingValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await secretStore.save(trimmed, service: service, account: RunseConstants.defaultProfileID)
    }
}
