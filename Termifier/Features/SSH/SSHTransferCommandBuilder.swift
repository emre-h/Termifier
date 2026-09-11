//
//  SSHTransferCommandBuilder.swift
//  Termifier
//
//  Turns a drag-and-drop (or menu-driven) file transfer against a saved
//  SSH profile into an `scp` command line for a terminal tab. Running it
//  in a real tab -- rather than a hidden subprocess -- is deliberate: the
//  user sees scp's own progress meter, its host-key and password prompts
//  work through the same askpass wiring as the interactive session, and
//  a failure stays on screen instead of collapsing into an alert.
//

import Foundation

enum SSHTransferDirection: String, Equatable, Sendable {
    case upload
    case download
}

/// One transfer the sidebar asks the window controller to run.
struct SSHTransferRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    var connection: SSHConnection
    var direction: SSHTransferDirection
    /// Upload: the local files/directories being sent. Download: exactly
    /// one local directory to receive the remote path.
    var localPaths: [String]
    /// Upload: the destination directory. Download: the file or
    /// directory being fetched.
    var remotePath: String

    init(
        id: UUID = UUID(),
        connection: SSHConnection,
        direction: SSHTransferDirection,
        localPaths: [String],
        remotePath: String
    ) {
        self.id = id
        self.connection = connection
        self.direction = direction
        self.localPaths = localPaths
        self.remotePath = remotePath
    }

    static func upload(
        connection: SSHConnection,
        localPaths: [String],
        remoteDirectory: String? = nil
    ) -> SSHTransferRequest {
        SSHTransferRequest(
            connection: connection,
            direction: .upload,
            localPaths: localPaths,
            remotePath: remoteDirectory ?? connection.remoteDirectory
        )
    }

    static func download(
        connection: SSHConnection,
        remotePath: String,
        localDirectory: String
    ) -> SSHTransferRequest {
        SSHTransferRequest(
            connection: connection,
            direction: .download,
            localPaths: [localDirectory],
            remotePath: remotePath
        )
    }

    /// Tab title: short enough for the tab bar, specific enough to tell
    /// two concurrent transfers apart.
    var tabTitle: String {
        switch direction {
        case .upload: "Upload → \(connection.name)"
        case .download: "Download ← \(connection.name)"
        }
    }
}

enum SSHTransferError: LocalizedError, Equatable {
    case noLocalPaths
    case missingLocalDirectory
    case unsafeRemotePath(String)

    var errorDescription: String? {
        switch self {
        case .noLocalPaths:
            "Choose at least one file to transfer."
        case .missingLocalDirectory:
            "Choose a local folder to download into."
        case .unsafeRemotePath(let path):
            "The remote path \"\(path)\" contains characters that are not allowed in a transfer path."
        }
    }
}

enum SSHTransferCommandBuilder {
    static let scpPath = "/usr/bin/scp"
    static let shellPath = "/bin/sh"

    /// Characters refused in a remote path.
    ///
    /// OpenSSH 9 runs `scp` over the SFTP protocol, where the remote path
    /// is a literal string, but `-O` (and older servers) still hand it to
    /// the remote *shell*. Rejecting shell metacharacters keeps the two
    /// modes behaving identically and keeps a profile's remote directory
    /// from turning into remote command execution.
    static let forbiddenRemotePathCharacters = CharacterSet(charactersIn: "`$;&|<>\"'\\\n\r")

    /// Strips a leading `~/` or `./`, leaving a path relative to the
    /// remote home directory -- the one spelling that resolves the same
    /// way under both the SFTP protocol (relative to home) and legacy
    /// remote-shell mode. Absolute paths pass through untouched, and an
    /// empty path stays empty, which scp reads as "the home directory".
    static func normalizedRemotePath(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return "" }
        if trimmed.hasPrefix("~/") { trimmed.removeFirst(2) }
        while trimmed.hasPrefix("./") { trimmed.removeFirst(2) }
        return trimmed
    }

    /// `user@host:path`, with an IPv6 literal bracketed so scp does not
    /// read its colons as the host/path separator.
    static func remoteArgument(for connection: SSHConnection, path: String) -> String {
        let host = connection.host.contains(":") && !connection.host.hasPrefix("[")
            ? "[\(connection.host)]"
            : connection.host
        let destination = connection.username.isEmpty ? host : "\(connection.username)@\(host)"
        return "\(destination):\(normalizedRemotePath(path))"
    }

    /// The scp argument vector, without the shell wrapper. Split out from
    /// `command(for:askPassPath:)` so tests can assert on the arguments
    /// themselves rather than on quoted shell text.
    static func arguments(for request: SSHTransferRequest, askPassPath: String?) throws -> [String] {
        let connection = request.connection
        let locals = request.localPaths
            .map { ($0 as NSString).expandingTildeInPath }
            .filter { !$0.isEmpty }
        guard !locals.isEmpty else {
            throw request.direction == .upload
                ? SSHTransferError.noLocalPaths
                : SSHTransferError.missingLocalDirectory
        }

        let remotePath = normalizedRemotePath(request.remotePath)
        guard remotePath.rangeOfCharacter(from: forbiddenRemotePathCharacters) == nil else {
            throw SSHTransferError.unsafeRemotePath(request.remotePath)
        }

        var arguments = SSHCommandBuilder.environmentTokens(
            for: connection,
            askPassPath: askPassPath
        )
        arguments += [scpPath, "-r"]
        arguments += SSHCommandBuilder.sharedOptions(for: connection)
        // scp spells the port `-P`; `-p` means "preserve times" there.
        arguments += ["-P", String(connection.port)]
        arguments += ["--"]

        let remote = remoteArgument(for: connection, path: remotePath)
        switch request.direction {
        case .upload:
            arguments += locals
            arguments.append(remote)
        case .download:
            arguments.append(remote)
            // A download's single local path is the destination folder.
            arguments.append(locals[0])
        }
        return arguments
    }

    /// The full command for `createCommandTab`.
    ///
    /// Ghostty runs a surface command as `bash -c "exec -l <command>"`,
    /// so the scp process REPLACES the shell and the tab would vanish
    /// (taking any error message with it) the moment the transfer ends.
    /// Wrapping in `/bin/sh -c` gives the transfer a parent that outlives
    /// it: the exit status is printed and the tab becomes a normal login
    /// shell instead of disappearing.
    static func command(for request: SSHTransferRequest, askPassPath: String?) throws -> String {
        let scpTokens = try arguments(for: request, askPassPath: askPassPath)
        let inner = scpTokens.map(SessionCommandSynthesizer.shSafeToken).joined(separator: " ")
        let script = """
        \(inner)
        status=$?
        printf '\\n[termifier] scp exited with status %s\\n' "$status"
        exec "$SHELL" -l
        """
        return [shellPath, "-c", script]
            .map(SessionCommandSynthesizer.shSafeToken)
            .joined(separator: " ")
    }
}
