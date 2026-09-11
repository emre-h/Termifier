//
//  SFTPService.swift
//  Termifier
//
//  Runs `sftp -b -` for the remote file browser: one process per
//  operation, commands on stdin, output parsed by `SFTPListingParser`.
//  The process runner is injectable, and the argument vector is supplied
//  as a closure, so tests can drive the real OpenSSH client against a
//  local `sftp-server` (`sftp -D`) with no network or server setup.
//

import Foundation

struct SFTPService: SFTPOperations {
    struct ProcessResult: Sendable {
        let status: Int32
        let standardOutput: String
        let standardError: String
    }

    /// Runs an argument vector with `script` on stdin. `nil` means the
    /// process could not be launched.
    typealias ProcessRunner = @Sendable (_ arguments: [String], _ script: String) async -> ProcessResult?

    /// Safety ceilings for a recursive delete's walk. A runaway tree (a
    /// huge cache, a mount point) is refused with an explanation instead
    /// of issuing thousands of remote deletions from one GUI click.
    static let deletionEntryLimit = 2000
    static let deletionDirectoryLimit = 200

    private let argumentsProvider: @Sendable () -> [String]
    private let runner: ProcessRunner
    /// Directory to create before the first run, for the multiplexing
    /// socket. `nil` in direct/test mode, where there is no socket.
    private let controlDirectory: String?

    init(
        connection: SSHConnection,
        askPassPath: String?,
        runner: ProcessRunner? = nil
    ) {
        let controlPath = SFTPCommandBuilder.controlPath(for: connection)
        self.argumentsProvider = {
            SFTPCommandBuilder.arguments(
                for: connection,
                askPassPath: askPassPath,
                controlPath: controlPath
            )
        }
        self.runner = runner ?? Self.systemRunner
        self.controlDirectory = (controlPath as NSString).deletingLastPathComponent
    }

    /// Direct-argument initializer, for tests and for `sftp -D` (a local
    /// sftp-server, no ssh involved).
    init(
        arguments: @escaping @Sendable () -> [String],
        runner: ProcessRunner? = nil
    ) {
        self.argumentsProvider = arguments
        self.runner = runner ?? Self.systemRunner
        self.controlDirectory = nil
    }

    // MARK: - Operations

    func workingDirectory() async throws -> String {
        let output = try await run([SFTPBatchScript.workingDirectory])
        guard let path = SFTPListingParser.workingDirectory(from: output) else {
            throw SFTPError.noWorkingDirectory
        }
        return path
    }

    func list(path: String, includeHidden: Bool) async throws -> [SFTPEntry] {
        let output = try await run([
            SFTPBatchScript.list(path: path, includeHidden: includeHidden)
        ])
        return SFTPListingParser.entries(from: output, directory: path)
    }

    func makeDirectory(path: String) async throws {
        _ = try await run([SFTPBatchScript.makeDirectory(path: path)])
    }

    func rename(from: String, to destination: String) async throws {
        _ = try await run([SFTPBatchScript.rename(from: from, to: destination)])
    }

    func changeMode(octal: String, path: String) async throws {
        _ = try await run([SFTPBatchScript.changeMode(octal: octal, path: path)])
    }

    func delete(_ entry: SFTPEntry) async throws {
        guard entry.isDirectory else {
            // A symlink is removed as a link, never followed -- deleting
            // what it points at is not what "delete this row" means.
            _ = try await run([SFTPBatchScript.removeFile(path: entry.path)])
            return
        }
        let targets = try await deletionTargets(root: entry.path)
        _ = try await run(SFTPBatchScript.recursiveDeletion(of: targets))
    }

    /// Breadth-first walk of `root`, parents before children, including
    /// `root` itself. Symlinked directories are collected as links, not
    /// descended into.
    private func deletionTargets(root: String) async throws -> [SFTPDeletionTarget] {
        var targets = [SFTPDeletionTarget(path: root, isDirectory: true)]
        var queue = [root]
        var visitedDirectories = 0

        while let directory = queue.first {
            queue.removeFirst()
            visitedDirectories += 1
            guard visitedDirectories <= Self.deletionDirectoryLimit,
                  targets.count <= Self.deletionEntryLimit else {
                throw SFTPError.treeTooLarge(path: root)
            }

            for entry in try await list(path: directory, includeHidden: true) {
                targets.append(
                    SFTPDeletionTarget(path: entry.path, isDirectory: entry.isDirectory)
                )
                if entry.isDirectory {
                    queue.append(entry.path)
                }
            }
        }
        return targets
    }

    // MARK: - Running

    private func run(_ commands: [String]) async throws -> String {
        guard !commands.isEmpty else { return "" }
        if let controlDirectory {
            // 0700: the socket is a live, already-authenticated channel to
            // the server; anything that can connect to it can use it.
            try? FileManager.default.createDirectory(
                atPath: controlDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let script = SFTPBatchScript.script(commands)
        guard let result = await runner(argumentsProvider(), script) else {
            throw SFTPError.unavailable
        }
        guard result.status == 0 else {
            throw SFTPError.failed(
                SFTPListingParser.failureMessage(
                    stderr: result.standardError,
                    stdout: result.standardOutput
                )
            )
        }
        return result.standardOutput
    }

    /// Spawns the real process. stdout and stderr are drained on separate
    /// queues before waiting, so a large listing cannot fill a pipe and
    /// deadlock the wait.
    static let systemRunner: ProcessRunner = { arguments, script in
        guard let executable = arguments.first,
              FileManager.default.fileExists(atPath: executable) else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = Array(arguments.dropFirst())
                process.environment = [
                    "HOME": NSHomeDirectory(),
                    "PATH": "/usr/bin:/bin",
                    "LC_ALL": "C",
                ]

                let stdinPipe = Pipe()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardInput = stdinPipe
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                stdinPipe.fileHandleForWriting.write(Data(script.utf8))
                stdinPipe.fileHandleForWriting.closeFile()

                var outputData = Data()
                var errorData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.wait()
                process.waitUntilExit()
                stdoutPipe.fileHandleForReading.closeFile()
                stderrPipe.fileHandleForReading.closeFile()

                continuation.resume(
                    returning: ProcessResult(
                        status: process.terminationStatus,
                        standardOutput: String(data: outputData, encoding: .utf8) ?? "",
                        standardError: String(data: errorData, encoding: .utf8) ?? ""
                    )
                )
            }
        }
    }
}
