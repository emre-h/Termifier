import Foundation
import Testing
@testable import Termifier

@Suite("SFTP command builder")
struct SFTPCommandBuilderTests {
    private func connection(
        authentication: SSHAuthenticationMethod = .agent,
        port: Int = 22
    ) -> SSHConnection {
        SSHConnection(
            id: UUID(uuidString: "492B21EA-C695-4FB6-923F-527452D2F7FC")!,
            name: "Production",
            host: "example.com",
            username: "deploy",
            port: port,
            authentication: authentication
        )
    }

    @Test("BatchMode=no is passed BEFORE -b, or password profiles could never authenticate")
    func batchModeOrdering() throws {
        // sftp adds its own `-obatchmode=yes` to the ssh it spawns when it
        // parses `-b`, and ssh keeps the FIRST value given for an option.
        // BatchMode=yes disables every prompt, askpass included.
        let arguments = SFTPCommandBuilder.arguments(
            for: connection(authentication: .password),
            askPassPath: "/tmp/askpass.sh",
            controlPath: "/tmp/.termifier-sftp/abc"
        )

        let batchModeIndex = try #require(arguments.firstIndex(of: "BatchMode=no"))
        let batchFlagIndex = try #require(arguments.firstIndex(of: "-b"))
        #expect(batchModeIndex < batchFlagIndex)
        #expect(arguments.contains("SSH_ASKPASS=/tmp/askpass.sh"))
        #expect(arguments.contains("SSH_ASKPASS_REQUIRE=force"))
    }

    @Test("Commands arrive on stdin and the destination is last")
    func stdinAndDestination() throws {
        let arguments = SFTPCommandBuilder.arguments(
            for: connection(),
            askPassPath: nil,
            controlPath: "/tmp/.termifier-sftp/abc"
        )

        let batchFlagIndex = try #require(arguments.firstIndex(of: "-b"))
        #expect(arguments[batchFlagIndex + 1] == "-")
        #expect(arguments.suffix(2) == ["--", "deploy@example.com"])
        #expect(arguments.first == "/usr/bin/env")
        #expect(arguments.contains("/usr/bin/sftp"))
    }

    @Test("The port is passed as -P, like scp")
    func portFlag() throws {
        let arguments = SFTPCommandBuilder.arguments(
            for: connection(port: 2222),
            askPassPath: nil,
            controlPath: "/tmp/.termifier-sftp/abc"
        )

        let portIndex = try #require(arguments.firstIndex(of: "-P"))
        #expect(arguments[portIndex + 1] == "2222")
        #expect(!arguments.contains("-p"))
    }

    @Test("Connection multiplexing is configured so repeated operations reuse one authentication")
    func multiplexing() {
        let arguments = SFTPCommandBuilder.arguments(
            for: connection(),
            askPassPath: nil,
            controlPath: "/tmp/.termifier-sftp/abc"
        )

        #expect(arguments.contains("ControlMaster=auto"))
        #expect(arguments.contains("ControlPath=/tmp/.termifier-sftp/abc"))
        #expect(
            arguments.contains("ControlPersist=\(SFTPCommandBuilder.controlPersistSeconds)")
        )
    }

    @Test("Identity file and jump hosts are inherited from the profile")
    func inheritsSharedOptions() {
        var profile = connection(authentication: .identityFile)
        profile.identityFile = "/tmp/SSH Keys/server.pem"
        profile.jumpHosts = ["bastion.example.com"]

        let arguments = SFTPCommandBuilder.arguments(
            for: profile,
            askPassPath: nil,
            controlPath: "/tmp/.termifier-sftp/abc"
        )

        #expect(arguments.contains("/tmp/SSH Keys/server.pem"))
        #expect(arguments.contains("-J"))
        #expect(arguments.contains("bastion.example.com"))
        #expect(arguments.contains("StrictHostKeyChecking=accept-new"))
    }

    @Test("The control socket path is short, stable per profile, and distinct between profiles")
    func controlPath() {
        let first = SFTPCommandBuilder.controlPath(for: connection())
        let second = SFTPCommandBuilder.controlPath(for: connection())
        let other = SFTPCommandBuilder.controlPath(
            for: SSHConnection(name: "Other", host: "other.example.com")
        )

        #expect(first == second)
        #expect(first != other)
        // A unix socket path is capped near 104 bytes; this one must stay
        // far below it.
        #expect(first.utf8.count < 60)
        #expect(first.hasPrefix(SFTPCommandBuilder.controlDirectory + "/"))
    }
}
