import Foundation
import Security

enum CredentialStoreError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case notFound
    case loadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s):  return "Keychain save failed (\(s))"
        case .notFound:           return "Credential not found in Keychain"
        case .loadFailed(let s):  return "Keychain load failed (\(s))"
        }
    }
}

struct CredentialStore {
    private static let service = "com.PaisleyTerm"

    func savePassword(_ password: String, id: String) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id,
            kSecValueData as String:   data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.saveFailed(status)
        }
    }

    func loadPassword(id: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ? CredentialStoreError.notFound : CredentialStoreError.loadFailed(status)
        }
        guard let data = result as? Data, let pwd = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.notFound
        }
        return pwd
    }

    func deletePassword(id: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id
        ]
        SecItemDelete(query as CFDictionary)
    }
}
