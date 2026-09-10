import Foundation

enum SSHCommandBuilder {
    static func command(for connection: SSHConnection, askPassPath: String? = nil) -> String {
        var arguments: [String] = []

        // Ghostty advertises xterm-ghostty locally, but many Linux hosts do not
        // ship that terminfo entry. xterm-256color preserves the usual colors,
        // cursor and clear-screen behavior across standard SSH servers.
        arguments += ["/usr/bin/env", "TERM=xterm-256color"]

        if connection.authentication == .password, let askPassPath {
            arguments += [
                "SSH_ASKPASS=\(askPassPath)",
                "SSH_ASKPASS_REQUIRE=force",
                "DISPLAY=:0",
                "TERMIFIER_SSH_CONNECTION_ID=\(connection.id.uuidString)",
            ]
        }

        arguments += [
            "/usr/bin/ssh",
            "-tt",
            "-o", "StrictHostKeyChecking=accept-new",
            "-p", String(connection.port),
        ]

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
        }

        arguments += ["--", connection.destination]
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
