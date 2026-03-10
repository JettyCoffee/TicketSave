import Foundation
import Security

enum AppSecretsStore {
    private static let service = "com.jettycoffee.TicketSave"
    private static let deepSeekAccount = "deepseek_api_key"

    static func saveDeepSeekAPIKey(_ key: String) -> Bool {
        save(key: key.trimmingCharacters(in: .whitespacesAndNewlines), account: deepSeekAccount)
    }

    static func loadDeepSeekAPIKey() -> String? {
        load(account: deepSeekAccount)
    }

    private static func save(key: String, account: String) -> Bool {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
