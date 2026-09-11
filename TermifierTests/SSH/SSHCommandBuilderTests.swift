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

    @Test("Agent authentication adds no credential options at all")
    func agentCommand() {
        let connection = SSHConnection(
            name: "Config host",
            host: "example.com",
            username: "deploy",
            authentication: .agent
        )

        let command = SSHCommandBuilder.command(for: connection)

        #expect(!command.contains("PubkeyAuthentication=no"))
        #expect(!command.contains("IdentitiesOnly"))
        #expect(!command.contains("'-i'"))
        #expect(command.hasSuffix("'--' 'deploy@example.com'"))
    }

    @Test("A jump chain becomes a single comma-joined -J argument")
    func jumpHosts() {
        let connection = SSHConnection(
            name: "Inner",
            host: "10.0.0.5",
            username: "ubuntu",
            authentication: .agent,
            jumpHosts: ["bastion.example.com", " user@middle "]
        )

        let command = SSHCommandBuilder.command(for: connection)

        #expect(command.contains("'-J' 'bastion.example.com,user@middle'"))
    }

    @Test("Blank jump entries never produce an empty hop")
    func blankJumpHostsAreDropped() {
        let connection = SSHConnection(
            name: "Server",
            host: "example.com",
            authentication: .agent,
            jumpHosts: ["", "   "]
        )

        #expect(!SSHCommandBuilder.command(for: connection).contains("'-J'"))
    }

    @Test("Every valid forwarding rule reaches the command line")
    func forwardArguments() {
        let connection = SSHConnection(
            name: "Tunnels",
            host: "example.com",
            authentication: .agent,
            forwards: [
                SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80),
                SSHPortForward(kind: .remote, listenPort: 9000, targetHost: "localhost", targetPort: 3000),
                SSHPortForward(kind: .dynamic, listenPort: 1080),
            ]
        )

        let command = SSHCommandBuilder.command(for: connection)

        #expect(command.contains("'-L' '8080:localhost:80'"))
        #expect(command.contains("'-R' '9000:localhost:3000'"))
        #expect(command.contains("'-D' '1080'"))
    }

    @Test("An invalid rule is skipped rather than costing the whole session")
    func invalidForwardIsSkipped() {
        let connection = SSHConnection(
            name: "Tunnels",
            host: "example.com",
            authentication: .agent,
            forwards: [
                SSHPortForward(kind: .local, listenPort: 0, targetHost: "localhost", targetPort: 80),
                SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80),
            ]
        )

        let command = SSHCommandBuilder.command(for: connection)

        #expect(command.contains("'-L' '8080:localhost:80'"))
        #expect(!command.contains("'0:localhost:80'"))
    }

    @Test("A startup command is one remote argument that hands over to the login shell")
    func startupCommand() {
        let connection = SSHConnection(
            name: "App",
            host: "example.com",
            username: "deploy",
            authentication: .agent,
            startupCommand: "cd /srv/app"
        )

        let command = SSHCommandBuilder.command(for: connection)

        #expect(command.hasSuffix("'--' 'deploy@example.com' 'cd /srv/app\nexec \"$SHELL\" -l'"))
    }

    @Test("No startup command leaves the destination as the last argument")
    func noStartupCommand() {
        let connection = SSHConnection(
            name: "App",
            host: "example.com",
            authentication: .agent,
            startupCommand: "   "
        )

        #expect(SSHCommandBuilder.command(for: connection).hasSuffix("'--' 'example.com'"))
        #expect(SSHCommandBuilder.remoteCommandToken(for: "") == nil)
    }

    @Test("A startup command containing quotes stays one shell token")
    func startupCommandQuoting() {
        let connection = SSHConnection(
            name: "App",
            host: "example.com",
            authentication: .agent,
            startupCommand: "echo 'hi'; touch /tmp/x"
        )

        let command = SSHCommandBuilder.command(for: connection)

        // The inner single quotes are escaped as '\'' rather than ending
        // the token, so the remote host -- not the local shell -- is the
        // only thing that interprets the command.
        #expect(command.contains("echo '\\''hi'\\''; touch /tmp/x"))
    }
}
