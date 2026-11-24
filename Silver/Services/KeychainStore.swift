import Foundation
import Security

enum KeychainStore {
    static let service = "com.silver.git.providers"
    static func read(_ provider: AIProvider) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ value: String, for provider: AIProvider) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue]
        let status: OSStatus
        if value.isEmpty {
            status = SecItemDelete(query as CFDictionary)
        } else {
            let data = Data(value.utf8)
            let existing = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if existing == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            } else { status = existing }
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitFailure(SecCopyErrorMessageString(status, nil) as String? ?? "Could not save the key in Keychain.")
        }
    }
}
