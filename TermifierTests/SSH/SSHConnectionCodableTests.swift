import Foundation
import Testing
@testable import Termifier

@Suite("SSH connection persistence compatibility")
struct SSHConnectionCodableTests {
    /// Exactly the shape `SSHConnectionStore` wrote before folders, jump
    /// hosts, forwarding and startup commands existed. The store decodes
    /// its whole array with `try?` and falls back to an EMPTY list, so a
    /// decoder that required any new key would not degrade -- it would
    /// erase every saved profile on upgrade.
    @Test("Profiles saved by an older build still decode, with defaults for new fields")
    func decodesLegacyProfile() throws {
        let json = """
        [{
          "id": "492B21EA-C695-4FB6-923F-527452D2F7FC",
          "name": "Production",
          "host": "prod.example.com",
          "username": "deploy",
          "port": 2222,
          "authentication": "password"
        }]
        """

        let connections = try JSONDecoder().decode([SSHConnection].self, from: Data(json.utf8))

        #expect(connections.count == 1)
        let connection = try #require(connections.first)
        #expect(connection.name == "Production")
        #expect(connection.port == 2222)
        #expect(connection.authentication == .password)
        #expect(connection.folder.isEmpty)
        #expect(connection.jumpHosts.isEmpty)
        #expect(connection.forwards.isEmpty)
        #expect(connection.startupCommand.isEmpty)
        #expect(connection.remoteDirectory.isEmpty)
    }

    @Test("Every new field survives a full encode/decode round trip")
    func roundTrip() throws {
        let connection = SSHConnection(
            name: "Tunnelled",
            host: "example.com",
            username: "deploy",
            port: 2222,
            authentication: .agent,
            folder: "Prod",
            jumpHosts: ["bastion"],
            forwards: [SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80)],
            startupCommand: "cd /srv",
            remoteDirectory: "/srv/uploads"
        )

        let data = try JSONEncoder().encode([connection])
        let decoded = try JSONDecoder().decode([SSHConnection].self, from: data)

        #expect(decoded == [connection])
    }

    @Test("Local listen ports exclude remote forwardings")
    func localListenPorts() {
        let connection = SSHConnection(
            name: "Mixed",
            host: "example.com",
            forwards: [
                SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80),
                SSHPortForward(kind: .remote, listenPort: 9000, targetHost: "localhost", targetPort: 3000),
                SSHPortForward(kind: .dynamic, listenPort: 1080),
            ]
        )

        #expect(connection.localListenPorts == [8080, 1080])
    }
}
