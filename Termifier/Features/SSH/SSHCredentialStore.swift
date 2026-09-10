import Foundation
import Security

protocol SSHCredentialStoring {
    func save(password: String, for connectionID: UUID) throws
    func deletePassword(for connectionID: UUID) throws
}

enum SSHCredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Could not update the SSH password in Keychain: \(message)"
        }
    }
}

struct KeychainSSHCredentialStore: SSHCredentialStoring {
    static let service = "com.termifier.ssh.password"

    func save(password: String, for connectionID: UUID) throws {
        let query = baseQuery(connectionID: connectionID)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: "Termifier SSH password",
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SSHCredentialStoreError.keychain(updateStatus)
        }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SSHCredentialStoreError.keychain(addStatus)
        }
    }

    func deletePassword(for connectionID: UUID) throws {
        let status = SecItemDelete(baseQuery(connectionID: connectionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SSHCredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(connectionID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: connectionID.uuidString,
        ]
    }
}
