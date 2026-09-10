import Foundation
import Observation

@MainActor @Observable
final class SSHConnectionStore {
    static let shared = SSHConnectionStore()

    private static let defaultsKey = "sshConnections.v1"
    private let defaults: UserDefaults
    private let credentialStore: any SSHCredentialStoring
    private(set) var connections: [SSHConnection]

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any SSHCredentialStoring = KeychainSSHCredentialStore()
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([SSHConnection].self, from: data) {
            self.connections = decoded
        } else {
            self.connections = []
        }
    }

    func add(_ connection: SSHConnection, password: String?) throws {
        if connection.authentication == .password {
            guard let password, !password.isEmpty else {
                throw SSHConnectionStoreError.passwordRequired
            }
            try credentialStore.save(password: password, for: connection.id)
        } else {
            try credentialStore.deletePassword(for: connection.id)
        }

        connections.append(connection)
        persist()
    }

    func update(_ connection: SSHConnection, password: String?) throws {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else {
            return
        }

        let previous = connections[index]
        if connection.authentication == .password {
            if let password, !password.isEmpty {
                try credentialStore.save(password: password, for: connection.id)
            } else if previous.authentication != .password {
                throw SSHConnectionStoreError.passwordRequired
            }
        } else {
            try credentialStore.deletePassword(for: connection.id)
        }

        connections[index] = connection
        persist()
    }

    func delete(_ connection: SSHConnection) throws {
        try credentialStore.deletePassword(for: connection.id)
        connections.removeAll { $0.id == connection.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

enum SSHConnectionStoreError: LocalizedError {
    case passwordRequired

    var errorDescription: String? {
        switch self {
        case .passwordRequired: "Enter a password for this SSH connection."
        }
    }
}
