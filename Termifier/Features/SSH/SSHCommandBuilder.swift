import Foundation

enum SSHCommandBuilder {
    static let envPath = "/usr/bin/env"
    static let sshPath = "/usr/bin/ssh"

    /// `/usr/bin/env` prefix tokens: the terminfo override every session
    /// needs, plus the Keychain-backed askpass wiring for password
    /// profiles. Shared with `SSHTransferCommandBuilder` so an scp of a
    /// password profile authenticates exactly like its terminal session.
    ///
    /// Ghostty advertises xterm-ghostty locally, but many Linux hosts do
    /// not ship that terminfo entry. xterm-256color preserves the usual
    /// colors, cursor and clear-screen behavior across standard SSH
    /// servers.
    static func environmentTokens(for connection: SSHConnection, askPassPath: String?) -> [String] {
        var tokens = [envPath, "TERM=xterm-256color"]
        if connection.authentication == .password, let askPassPath {
            tokens += [
                "SSH_ASKPASS=\(askPassPath)",
                "SSH_ASKPASS_REQUIRE=force",
                "DISPLAY=:0",
                "TERMIFIER_SSH_CONNECTION_ID=\(connection.id.uuidString)",
            ]
        }
        return tokens
    }

    /// Host-key policy, authentication options and the `ProxyJump`
    /// chain -- everything that is identical between an interactive
    /// session and a file transfer. The port is deliberately NOT here:
    /// ssh spells it `-p`, scp/sftp spell it `-P`.
    static func sharedOptions(for connection: SSHConnection) -> [String] {
        var arguments = ["-o", "StrictHostKeyChecking=accept-new"]

        switch connection.authentication {
        case .password:
            arguments += [
                "-o", "PreferredAuthentications=password,keyboard-interactive",
                "-o", "PubkeyAuthentication=no",
            ]
        case .identityFile:
            if let path = connection.identityFile, !path.isEmpty {
                arguments += ["-i", (path as NSString).expandingTildeInPath]
                arguments += ["-o", "IdentitiesOnly=yes"]
            }
        case .agent:
            // Nothing to add: ssh's own defaults (agent keys, ssh_config
            // IdentityFile entries, ~/.ssh/id_*) are the whole point of
            // this method.
            break
        }

        arguments += jumpArguments(for: connection)
        return arguments
    }

    /// `-J bastion,inner` for a saved jump chain. Blank entries are
    /// dropped and each remaining entry is trimmed, so a stray space in
    /// the editor cannot turn into a second, empty hop -- ssh rejects the
    /// whole session for one malformed hop.
    static func jumpArguments(for connection: SSHConnection) -> [String] {
        let hops = connection.jumpHosts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !hops.isEmpty else { return [] }
        return ["-J", hops.joined(separator: ",")]
    }

    /// Forwarding arguments for every VALID rule. An invalid rule is
    /// skipped rather than emitted: ssh treats a malformed `-L` spec as a
    /// fatal error, so emitting it would cost the user the whole session
    /// instead of one tunnel. The editor refuses to save invalid rules,
    /// so this is a second line of defense for profiles edited by hand.
    static func forwardArguments(for connection: SSHConnection) -> [String] {
        connection.forwards
            .filter { $0.validationError == nil }
            .flatMap(\.arguments)
    }

    /// The single remote-command argument for a startup command, or `nil`
    /// when there is none.
    ///
    /// The command is followed by `exec "$SHELL" -l` on its own line so
    /// the tab stays an interactive session instead of exiting the moment
    /// the command finishes -- which is what makes directory-changing
    /// startup commands (`cd /srv/app`) useful at all. A newline, not
    /// `;`, separates them: a trailing `#` comment or `&&` in the user's
    /// command would otherwise swallow the handover.
    static func remoteCommandToken(for startupCommand: String) -> String? {
        let trimmed = startupCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed + "\nexec \"$SHELL\" -l"
    }

    static func command(for connection: SSHConnection, askPassPath: String? = nil) -> String {
        var arguments = environmentTokens(for: connection, askPassPath: askPassPath)

        arguments += [
            sshPath,
            "-tt",
        ]
        arguments += sharedOptions(for: connection)
        arguments += ["-p", String(connection.port)]
        arguments += forwardArguments(for: connection)
        arguments += ["--", connection.destination]

        if let remoteCommand = remoteCommandToken(for: connection.startupCommand) {
            arguments.append(remoteCommand)
        }

        return arguments.map(SessionCommandSynthesizer.shSafeToken).joined(separator: " ")
    }
}

enum SSHAskPassInstaller {
    static func install() throws -> String {
        let directory = URL(fileURLWithPath: AppSupportDirectory.path, isDirectory: true)
            .appendingPathComponent("ssh", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("askpass.sh", isDirectory: false)
        let script = """
        #!/bin/sh
        exec /usr/bin/security find-generic-password -s '\(KeychainSSHCredentialStore.service)' -a "$TERMIFIER_SSH_CONNECTION_ID" -w
        """

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (script + "\n").write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL.path
    }
}
