//
//  SFTPCommandBuilder.swift
//  Termifier
//
//  The `sftp -b -` argument vector behind the remote file browser. Pure;
//  `SFTPService` is what spawns it.
//
//  WHY ONE PROCESS PER OPERATION, plus connection multiplexing: a
//  long-lived interactive `sftp` would have to be driven by matching
//  prompts in a byte stream, with no reliable delimiter between one
//  command's output and the next. A batch process per operation instead
//  gets delimitation for free (EOF) and a real exit status, and
//  `ControlMaster` makes the repeated connections nearly free -- the
//  first one authenticates, the rest reuse its socket. For a password
//  profile that also means the Keychain askpass runs once per
//  `ControlPersist` window rather than once per click.
//

import Foundation

enum SFTPCommandBuilder {
    static let sftpPath = "/usr/bin/sftp"

    /// Directory holding the multiplexing sockets. Kept short and under
    /// `/tmp` on purpose: a unix socket path is capped near 104 bytes, and
    /// the app-support directory ("~/Library/Application Support/…") is
    /// long enough to risk that cap once a profile name is appended.
    static let controlDirectory = "/tmp/.termifier-sftp"

    /// How long an idle master connection is kept for reuse.
    static let controlPersistSeconds = 30

    /// A per-profile socket path, short and stable: the same profile
    /// reuses its master connection across operations and browser
    /// windows, while two profiles never share one.
    static func controlPath(for connection: SSHConnection, directory: String = controlDirectory) -> String {
        let token = connection.id.uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(12)
            .lowercased()
        return "\(directory)/\(token)"
    }

    static func arguments(
        for connection: SSHConnection,
        askPassPath: String?,
        controlPath: String
    ) -> [String] {
        // Same env prefix as the interactive session and scp, so a
        // password profile authenticates through the same Keychain-backed
        // askpass helper.
        var arguments = SSHCommandBuilder.environmentTokens(
            for: connection,
            askPassPath: askPassPath
        )
        arguments.append(sftpPath)

        // MUST come before `-b`: sftp adds its own `-obatchmode=yes` to
        // the ssh it spawns when it parses `-b`, and ssh keeps the FIRST
        // value it is given for an option. Without this, BatchMode=yes
        // would win and disable every prompt -- including the askpass
        // helper -- so password profiles could not authenticate at all.
        arguments += ["-o", "BatchMode=no"]

        arguments += SSHCommandBuilder.sharedOptions(for: connection)
        arguments += [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=\(controlPersistSeconds)",
        ]
        // sftp spells the port `-P`, like scp.
        arguments += ["-P", String(connection.port)]
        // Commands arrive on stdin.
        arguments += ["-b", "-"]
        arguments += ["--", connection.destination]
        return arguments
    }
}
