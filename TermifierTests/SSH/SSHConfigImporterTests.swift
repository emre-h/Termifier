import Foundation
import Testing
@testable import Termifier

@Suite("ssh_config import")
struct SSHConfigImporterTests {
    @Test("A host with an identity file becomes an identity-file profile")
    func identityFileHost() {
        let host = SSHConfigHost(
            alias: "prod",
            hostName: "prod.example.com",
            user: "deploy",
            port: 2222,
            identityFile: "~/.ssh/prod_ed25519"
        )

        let connection = SSHConfigImporter.connection(from: host, folder: "ssh config")

        #expect(connection.name == "prod")
        #expect(connection.host == "prod.example.com")
        #expect(connection.username == "deploy")
        #expect(connection.port == 2222)
        #expect(connection.authentication == .identityFile)
        #expect(connection.identityFile == "~/.ssh/prod_ed25519")
        #expect(connection.folder == "ssh config")
    }

    @Test("A host without a key becomes an agent profile, never a password one")
    func agentHost() {
        // A password profile would be unsavable: there is no password to
        // put in the Keychain and the store rejects one without it.
        let connection = SSHConfigImporter.connection(
            from: SSHConfigHost(alias: "box"),
            folder: ""
        )

        #expect(connection.authentication == .agent)
        #expect(connection.identityFile == nil)
        #expect(connection.host == "box")
        #expect(connection.port == 22)
    }

    @Test("Jump hosts and forwardings carry over, invalid rules excluded")
    func carriesRouting() {
        let host = SSHConfigHost(
            alias: "inner",
            proxyJump: ["bastion"],
            forwards: [
                SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80),
                SSHPortForward(kind: .local, listenPort: 0, targetHost: "localhost", targetPort: 80),
            ]
        )

        let connection = SSHConfigImporter.connection(from: host, folder: "")

        #expect(connection.jumpHosts == ["bastion"])
        #expect(connection.forwards.count == 1)
    }

    @Test("Candidates flag hosts that are already saved by name or by endpoint")
    func duplicateDetection() {
        let existing = [
            SSHConnection(name: "prod", host: "somewhere.else", authentication: .agent),
            SSHConnection(name: "Staging box", host: "STAGING.example.com", username: "deploy", authentication: .agent),
        ]
        let config = """
        Host prod
            HostName prod.example.com
        Host staging
            HostName staging.example.com
            User deploy
        Host fresh
            HostName fresh.example.com
        """

        let candidates = SSHConfigImporter.candidates(from: config, existing: existing, folder: "")

        #expect(candidates.map(\.id) == ["prod", "staging", "fresh"])
        // Same name, different host.
        #expect(candidates[0].isAlreadySaved)
        // Different name, same user/host/port -- host compared case-insensitively.
        #expect(candidates[1].isAlreadySaved)
        #expect(!candidates[2].isAlreadySaved)
    }

    @Test("A different port on the same host is not a duplicate")
    func portDistinguishes() {
        let existing = [SSHConnection(name: "a", host: "example.com", port: 22, authentication: .agent)]
        let candidate = SSHConnection(name: "b", host: "example.com", port: 2222, authentication: .agent)

        #expect(!SSHConfigImporter.isAlreadySaved(candidate, in: existing))
    }

    @Test("The config reader derives its path from the session root resolver")
    func readerPath() {
        let reader = SSHConfigFileReader(
            rootResolver: StubRootResolver(root: "/tmp/home"),
            loadConfig: { path in path == "/tmp/home/.ssh/config" ? "Host box\n" : nil }
        )

        #expect(reader.path == "/tmp/home/.ssh/config")
        #expect(reader.read() == "Host box\n")
    }

    @Test("A missing config reads as nil rather than failing")
    func missingConfig() {
        let reader = SSHConfigFileReader(
            rootResolver: StubRootResolver(root: "/tmp/home"),
            loadConfig: { _ in nil }
        )

        #expect(reader.read() == nil)
    }

    private struct StubRootResolver: SessionRootResolverProtocol {
        let root: String
        func resolve() -> String { root }
    }
}
