import Foundation
import Testing
@testable import Termifier

@Suite("SSH file transfers")
struct SSHTransferCommandBuilderTests {
    private func connection(
        authentication: SSHAuthenticationMethod = .agent,
        port: Int = 22,
        host: String = "example.com",
        remoteDirectory: String = ""
    ) -> SSHConnection {
        SSHConnection(
            id: UUID(uuidString: "492B21EA-C695-4FB6-923F-527452D2F7FC")!,
            name: "Production",
            host: host,
            username: "deploy",
            port: port,
            authentication: authentication,
            remoteDirectory: remoteDirectory
        )
    }

    @Test("An upload sends the local paths last, with the remote target after them")
    func uploadArguments() throws {
        let request = SSHTransferRequest.upload(
            connection: connection(remoteDirectory: "/srv/uploads"),
            localPaths: ["/tmp/a.txt", "/tmp/dir"]
        )

        let arguments = try SSHTransferCommandBuilder.arguments(for: request, askPassPath: nil)

        #expect(arguments.contains("/usr/bin/scp"))
        #expect(arguments.contains("-r"))
        // scp spells the port -P; -p would mean "preserve times".
        #expect(arguments.contains("-P"))
        #expect(arguments.suffix(3) == ["/tmp/a.txt", "/tmp/dir", "deploy@example.com:/srv/uploads"])
    }

    @Test("A download puts the remote source first and the local folder last")
    func downloadArguments() throws {
        let request = SSHTransferRequest.download(
            connection: connection(),
            remotePath: "/var/log/app.log",
            localDirectory: "/Users/me/Downloads"
        )

        let arguments = try SSHTransferCommandBuilder.arguments(for: request, askPassPath: nil)

        #expect(arguments.suffix(2) == ["deploy@example.com:/var/log/app.log", "/Users/me/Downloads"])
    }

    @Test("Transfers inherit the profile's port, identity file and jump chain")
    func inheritsConnectionOptions() throws {
        var profile = connection(authentication: .identityFile, port: 2222)
        profile.identityFile = "/tmp/SSH Keys/server.pem"
        profile.jumpHosts = ["bastion.example.com"]
        let request = SSHTransferRequest.upload(connection: profile, localPaths: ["/tmp/a.txt"])

        let arguments = try SSHTransferCommandBuilder.arguments(for: request, askPassPath: nil)

        #expect(arguments.contains("-J"))
        #expect(arguments.contains("bastion.example.com"))
        #expect(arguments.contains("/tmp/SSH Keys/server.pem"))
        let portIndex = try #require(arguments.firstIndex(of: "-P"))
        #expect(arguments[portIndex + 1] == "2222")
    }

    @Test("Password profiles reuse the Keychain-backed askpass helper")
    func passwordTransferUsesAskPass() throws {
        let request = SSHTransferRequest.upload(
            connection: connection(authentication: .password),
            localPaths: ["/tmp/a.txt"]
        )

        let arguments = try SSHTransferCommandBuilder.arguments(
            for: request,
            askPassPath: "/tmp/Termifier Support/askpass.sh"
        )

        #expect(arguments.contains("SSH_ASKPASS=/tmp/Termifier Support/askpass.sh"))
        #expect(arguments.contains("SSH_ASKPASS_REQUIRE=force"))
        #expect(
            arguments.contains("TERMIFIER_SSH_CONNECTION_ID=492B21EA-C695-4FB6-923F-527452D2F7FC")
        )
    }

    @Test("A home-relative remote path becomes relative, which resolves the same in both scp modes")
    func remotePathNormalization() {
        #expect(SSHTransferCommandBuilder.normalizedRemotePath("~/srv") == "srv")
        #expect(SSHTransferCommandBuilder.normalizedRemotePath("~") == "")
        #expect(SSHTransferCommandBuilder.normalizedRemotePath("./logs") == "logs")
        #expect(SSHTransferCommandBuilder.normalizedRemotePath("  /srv/app  ") == "/srv/app")
        #expect(SSHTransferCommandBuilder.normalizedRemotePath("") == "")
    }

    @Test("An empty remote path targets the remote home directory")
    func emptyRemotePathIsHome() throws {
        let request = SSHTransferRequest.upload(connection: connection(), localPaths: ["/tmp/a.txt"])

        let arguments = try SSHTransferCommandBuilder.arguments(for: request, askPassPath: nil)

        #expect(arguments.last == "deploy@example.com:")
    }

    @Test("An IPv6 host is bracketed so scp does not read its colons as a path separator")
    func ipv6Host() {
        let remote = SSHTransferCommandBuilder.remoteArgument(
            for: connection(host: "fd00::5"),
            path: "/srv"
        )

        #expect(remote == "deploy@[fd00::5]:/srv")
    }

    @Test("A remote path with shell metacharacters is refused")
    func unsafeRemotePath() {
        let request = SSHTransferRequest.upload(
            connection: connection(),
            localPaths: ["/tmp/a.txt"],
            remoteDirectory: "/srv; rm -rf /"
        )

        #expect(throws: SSHTransferError.unsafeRemotePath("/srv; rm -rf /")) {
            try SSHTransferCommandBuilder.arguments(for: request, askPassPath: nil)
        }
    }

    @Test("A transfer with no local path is refused with a direction-specific message")
    func missingLocalPaths() {
        let upload = SSHTransferRequest.upload(connection: connection(), localPaths: [])
        #expect(throws: SSHTransferError.noLocalPaths) {
            try SSHTransferCommandBuilder.arguments(for: upload, askPassPath: nil)
        }

        let download = SSHTransferRequest.download(
            connection: connection(),
            remotePath: "/var/log/app.log",
            localDirectory: ""
        )
        #expect(throws: SSHTransferError.missingLocalDirectory) {
            try SSHTransferCommandBuilder.arguments(for: download, askPassPath: nil)
        }
    }

    @Test("The tab command wraps scp in a shell that outlives it")
    func commandKeepsTheTabAlive() throws {
        // Ghostty execs a surface command directly, so an unwrapped scp
        // would take the tab -- and any error it printed -- with it when
        // it exits.
        let request = SSHTransferRequest.upload(connection: connection(), localPaths: ["/tmp/a.txt"])

        let command = try SSHTransferCommandBuilder.command(for: request, askPassPath: nil)

        #expect(command.hasPrefix("'/bin/sh' '-c' '"))
        #expect(command.contains("/usr/bin/scp"))
        #expect(command.contains("exec \"$SHELL\" -l"))
    }

    @Test("A local path containing a space stays one argument")
    func quotedLocalPath() throws {
        let request = SSHTransferRequest.upload(
            connection: connection(),
            localPaths: ["/tmp/My Files/a.txt"]
        )

        let command = try SSHTransferCommandBuilder.command(for: request, askPassPath: nil)

        // Escaped for the inner shell: the outer wrapper quotes the whole
        // script, so the inner quotes appear as '\''.
        #expect(command.contains("/tmp/My Files/a.txt"))
    }

    @Test("Tab titles name the direction and the profile")
    func tabTitles() {
        let upload = SSHTransferRequest.upload(connection: connection(), localPaths: ["/tmp/a"])
        let download = SSHTransferRequest.download(
            connection: connection(),
            remotePath: "/tmp/a",
            localDirectory: "/tmp"
        )

        #expect(upload.tabTitle == "Upload → Production")
        #expect(download.tabTitle == "Download ← Production")
    }
}
