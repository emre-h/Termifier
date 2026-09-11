//
//  SSHKnownHosts.swift
//  Termifier
//
//  Host-key inspection and removal for a saved profile, via
//  `ssh-keygen -F` / `ssh-keygen -R`.
//
//  WHY THIS EXISTS: sessions connect with
//  `StrictHostKeyChecking=accept-new`, which records an unknown host's
//  key silently but REFUSES a host whose recorded key changed -- the
//  common case after a server rebuild or an IP reuse. ssh then prints its
//  "REMOTE HOST IDENTIFICATION HAS CHANGED" block and exits, and the user
//  is stuck: the offending entry lives in `~/.ssh/known_hosts`, which the
//  app never showed them. The profile editor now shows whether a key is
//  recorded and can forget it, so the next connection re-learns the key.
//
//  The argument builders are pure and unit-tested; only the service
//  spawns `ssh-keygen`, through an injectable runner.
//

import Foundation

enum SSHKnownHostStatus: Equatable, Sendable {
    /// The host has one or more keys in `known_hosts`.
    case recorded(keyTypes: [String])
    case notRecorded
    /// `ssh-keygen` could not be run, or failed for a reason other than
    /// "not found" -- reported as its own state rather than as "no key",
    /// which would invite the user to "forget" something that may exist.
    case unavailable
}

enum SSHKnownHostsCommandBuilder {
    static let sshKeygenPath = "/usr/bin/ssh-keygen"

    /// The `known_hosts` lookup key. A non-default port is stored in the
    /// bracketed `[host]:port` form, so looking it up as a bare hostname
    /// finds nothing.
    static func hostSpec(host: String, port: Int) -> String {
        let bare = host.trimmingCharacters(in: .whitespaces)
        guard port != 22 else { return bare }
        let bracketed = bare.hasPrefix("[") ? bare : "[\(bare)]"
        return "\(bracketed):\(port)"
    }

    static func findArguments(host: String, port: Int) -> [String] {
        ["-F", hostSpec(host: host, port: port)]
    }

    static func removeArguments(host: String, port: Int) -> [String] {
        ["-R", hostSpec(host: host, port: port)]
    }

    /// Key types from `ssh-keygen -F` output. Its first line is a
    /// `# Host … found: line N` comment; every following non-comment line
    /// is a known_hosts entry whose SECOND field is the key type.
    static func parseKeyTypes(from output: String) -> [String] {
        var types: [String] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 2 else { continue }
            types.append(String(fields[1]))
        }
        return types
    }
}

struct SSHKnownHostsService: Sendable {
    /// Exit status plus stdout of one `ssh-keygen` invocation.
    typealias Runner = @Sendable ([String]) async -> (status: Int32, output: String)?

    private let run: Runner

    init(run: Runner? = nil) {
        self.run = run ?? Self.systemRunner
    }

    func status(host: String, port: Int) async -> SSHKnownHostStatus {
        let arguments = SSHKnownHostsCommandBuilder.findArguments(host: host, port: port)
        guard let result = await run(arguments) else { return .unavailable }
        switch result.status {
        case 0:
            let types = SSHKnownHostsCommandBuilder.parseKeyTypes(from: result.output)
            // Exit 0 with no parsable entry means ssh-keygen answered
            // something this parser does not understand; claiming "no
            // key" there would be a guess.
            return types.isEmpty ? .unavailable : .recorded(keyTypes: types)
        case 1:
            return .notRecorded
        default:
            return .unavailable
        }
    }

    func status(for connection: SSHConnection) async -> SSHKnownHostStatus {
        await status(host: connection.host, port: connection.port)
    }

    /// Removes every recorded key for the host. `ssh-keygen -R` keeps a
    /// `known_hosts.old` backup of its own, so this is recoverable.
    func forget(host: String, port: Int) async -> Bool {
        let arguments = SSHKnownHostsCommandBuilder.removeArguments(host: host, port: port)
        guard let result = await run(arguments) else { return false }
        return result.status == 0
    }

    func forget(for connection: SSHConnection) async -> Bool {
        await forget(host: connection.host, port: connection.port)
    }

    /// Spawns the real `ssh-keygen`. Returns `nil` when the binary is
    /// missing or cannot be launched, which the callers above map to
    /// `.unavailable` rather than to a negative answer.
    static let systemRunner: Runner = { arguments in
        guard FileManager.default.fileExists(atPath: SSHKnownHostsCommandBuilder.sshKeygenPath) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(
                    fileURLWithPath: SSHKnownHostsCommandBuilder.sshKeygenPath
                )
                process.arguments = arguments
                // HOME is what ssh-keygen resolves ~/.ssh/known_hosts
                // from; an app launched from the Dock still has it, but
                // passing a minimal environment explicitly keeps the
                // result independent of whatever else is inherited.
                process.environment = [
                    "HOME": NSHomeDirectory(),
                    "PATH": "/usr/bin:/bin",
                    "LC_ALL": "C",
                ]
                let stdoutPipe = Pipe()
                process.standardOutput = stdoutPipe
                // Discarded rather than piped: an undrained stderr pipe
                // would deadlock this single-threaded read if ssh-keygen
                // ever filled it.
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                stdoutPipe.fileHandleForReading.closeFile()
                continuation.resume(
                    returning: (
                        status: process.terminationStatus,
                        output: String(data: data, encoding: .utf8) ?? ""
                    )
                )
            }
        }
    }
}
