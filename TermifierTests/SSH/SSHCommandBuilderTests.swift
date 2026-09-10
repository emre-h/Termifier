import Foundation
import Testing
@testable import Termifier

@Suite("SSH command builder")
struct SSHCommandBuilderTests {
    @Test("Password authentication uses Keychain-backed askpass without embedding a password")
    func passwordCommand() {
        let id = UUID(uuidString: "492B21EA-C695-4FB6-923F-527452D2F7FC")!
        let connection = SSHConnection(
            id: id,
            name: "Production",
            host: "example.com",
            username: "deploy",
            port: 2222,
            authentication: .password
        )

        let command = SSHCommandBuilder.command(
            for: connection,
            askPassPath: "/tmp/Termifier Support/askpass.sh"
        )

        #expect(command.contains("'SSH_ASKPASS=/tmp/Termifier Support/askpass.sh'"))
        #expect(command.contains("'TERMIFIER_SSH_CONNECTION_ID=\(id.uuidString)'"))
        #expect(command.contains("'PreferredAuthentications=password,keyboard-interactive'"))
        #expect(command.contains("'PubkeyAuthentication=no'"))
        #expect(command.hasSuffix("'--' 'deploy@example.com'"))
    }

    @Test("Identity authentication supports PEM paths containing spaces")
    func identityCommand() {
        let connection = SSHConnection(
            name: "Server",
            host: "10.0.0.5",
            username: "ubuntu",
            authentication: .identityFile,
            identityFile: "/tmp/SSH Keys/server.pem"
        )

        let command = SSHCommandBuilder.command(for: connection)

        #expect(command.contains("'TERM=xterm-256color'"))
        #expect(command.contains("'-i' '/tmp/SSH Keys/server.pem'"))
        #expect(command.contains("'IdentitiesOnly=yes'"))
        #expect(!command.contains("SSH_ASKPASS"))
    }

    @Test("Host text is shell-escaped and cannot append a command")
    func destinationIsShellEscaped() {
        let connection = SSHConnection(
            name: "Untrusted",
            host: "example.com; touch /tmp/should-not-run",
            username: "user",
            authentication: .identityFile,
            identityFile: "/tmp/key.pem"
        )

        let command = SSHCommandBuilder.command(for: connection)

        #expect(command.hasSuffix("'--' 'user@example.com; touch /tmp/should-not-run'"))
    }
}
