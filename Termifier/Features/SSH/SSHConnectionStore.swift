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

    /// Moves a profile into `folder` (empty string = ungrouped),
    /// preserving its saved password: `update` treats a `nil` password on
    /// an already-password profile as "keep what is in the Keychain".
    func move(_ connection: SSHConnection, toFolder folder: String) throws {
        var moved = connection
        moved.folder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        try update(moved, password: nil)
    }

    /// Named folders in use, case-insensitively sorted. The ungrouped
    /// bucket is not a folder and is deliberately absent.
    var folders: [String] {
        let named = Set(connections.map(\.folder).filter { !$0.isEmpty })
        return named.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Appends imported profiles, skipping any that duplicate a saved
    /// one, and returns how many were added.
    ///
    /// A candidate that fails to save does not abort the import: one bad
    /// host in a long `~/.ssh/config` should cost the user that host, not
    /// the whole batch. Imported profiles never carry a password (see
    /// `SSHConfigImporter`), so `add`'s password path is never taken.
    @discardableResult
    func importConnections(_ candidates: [SSHConnection]) -> Int {
        var imported = 0
        for candidate in candidates {
            guard !SSHConfigImporter.isAlreadySaved(candidate, in: connections) else { continue }
            do {
                try add(candidate, password: nil)
                imported += 1
            } catch {
                continue
            }
        }
        return imported
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
