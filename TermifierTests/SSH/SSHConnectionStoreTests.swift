import Foundation
import Testing
@testable import Termifier

@MainActor
@Suite("SSH connection store")
struct SSHConnectionStoreTests {
    @Test("Password is sent to the credential store and never persisted in profile metadata")
    func passwordStorage() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let connection = SSHConnection(
            name: "Production",
            host: "prod.example.com",
            username: "deploy",
            authentication: .password
        )

        try fixture.store.add(connection, password: "super-secret-password")

        #expect(fixture.credentials.saved[connection.id] == "super-secret-password")
        let persistedData = try #require(fixture.defaults.data(forKey: "sshConnections.v1"))
        let persistedText = try #require(String(data: persistedData, encoding: .utf8))
        #expect(!persistedText.contains("super-secret-password"))
        #expect(persistedText.contains("prod.example.com"))
    }

    @Test("Saved profile metadata reloads from UserDefaults")
    func reload() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let connection = SSHConnection(
            name: "PEM server",
            host: "192.0.2.10",
            username: "ubuntu",
            authentication: .identityFile,
            identityFile: "/tmp/server.pem"
        )
        try fixture.store.add(connection, password: nil)

        let reloaded = SSHConnectionStore(
            defaults: fixture.defaults,
            credentialStore: fixture.credentials
        )

        #expect(reloaded.connections == [connection])
        #expect(fixture.credentials.deleted == [connection.id])
    }

    @Test("Deleting a profile also deletes its Keychain password")
    func delete() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let connection = SSHConnection(
            name: "Server",
            host: "server.example.com",
            authentication: .password
        )
        try fixture.store.add(connection, password: "secret")

        try fixture.store.delete(connection)

        #expect(fixture.store.connections.isEmpty)
        #expect(fixture.credentials.deleted == [connection.id])
    }

    @Test("Editing a password profile preserves its password when the field is blank")
    func updatePreservesPassword() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        var connection = SSHConnection(
            name: "Old name",
            host: "server.example.com",
            authentication: .password
        )
        try fixture.store.add(connection, password: "existing-secret")
        connection.name = "New name"

        try fixture.store.update(connection, password: "")

        #expect(fixture.store.connections == [connection])
        #expect(fixture.credentials.saved[connection.id] == "existing-secret")
    }

    @Test("Changing from password to identity removes the Keychain password")
    func updateToIdentityDeletesPassword() throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        var connection = SSHConnection(
            name: "Server",
            host: "server.example.com",
            authentication: .password
        )
        try fixture.store.add(connection, password: "secret")
        connection.authentication = .identityFile
        connection.identityFile = "/tmp/key.pem"

        try fixture.store.update(connection, password: nil)

        #expect(fixture.credentials.saved[connection.id] == nil)
        #expect(fixture.credentials.deleted == [connection.id])
    }

    @Test("Password profiles reject an empty password")
    func emptyPassword() {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        let connection = SSHConnection(
            name: "Server",
            host: "server.example.com",
            authentication: .password
        )

        #expect(throws: SSHConnectionStoreError.self) {
            try fixture.store.add(connection, password: "")
        }
        #expect(fixture.store.connections.isEmpty)
    }

    private final class FakeCredentialStore: SSHCredentialStoring {
        var saved: [UUID: String] = [:]
        var deleted: [UUID] = []

        func save(password: String, for connectionID: UUID) throws {
            saved[connectionID] = password
        }

        func deletePassword(for connectionID: UUID) throws {
            deleted.append(connectionID)
            saved.removeValue(forKey: connectionID)
        }
    }

    @MainActor
    private final class Fixture {
        let suiteName = "SSHConnectionStoreTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let credentials = FakeCredentialStore()
        let store: SSHConnectionStore

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            store = SSHConnectionStore(defaults: defaults, credentialStore: credentials)
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
