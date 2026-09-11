//
//  SFTPBatchScript.swift
//  Termifier
//
//  Builds the command text fed to `sftp -b -` on stdin, and quotes remote
//  paths for sftp's own parser.
//
//  QUOTING, verified against the OpenSSH client shipped with macOS: a
//  path is wrapped in double quotes, inside which only `\` and `"` need
//  escaping. Glob metacharacters (`*?[]`) must NOT be escaped inside
//  quotes -- sftp does not glob a quoted path, and an escaped `\*` inside
//  quotes reaches the server with the backslash still attached, so the
//  path is simply not found. (sftp(1)'s advice to backslash-escape glob
//  characters applies to UNQUOTED paths.)
//

import Foundation

enum SFTPBatchScript {

    /// One remote path as a single sftp argument.
    static func quote(_ path: String) -> String {
        var escaped = ""
        for character in path {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    /// `pwd`, whose answer (`Remote working directory: /home/deploy`) is
    /// how the browser learns where to start.
    static let workingDirectory = "pwd"

    /// A long, numeric-id listing of `path`. `-a` is added only when
    /// hidden entries are wanted: without it sftp omits dotfiles as well
    /// as `.` and `..`, which is exactly the browser's default view.
    static func list(path: String, includeHidden: Bool) -> String {
        "ls -\(includeHidden ? "lan" : "ln") \(quote(path))"
    }

    static func makeDirectory(path: String) -> String {
        "mkdir \(quote(path))"
    }

    static func rename(from: String, to destination: String) -> String {
        "rename \(quote(from)) \(quote(destination))"
    }

    static func removeFile(path: String) -> String {
        "rm \(quote(path))"
    }

    static func removeDirectory(path: String) -> String {
        "rmdir \(quote(path))"
    }

    /// `chmod` takes the mode unquoted -- it is a number, not a path.
    static func changeMode(octal: String, path: String) -> String {
        "chmod \(octal) \(quote(path))"
    }

    /// Orders a recursive delete so every child is removed before its
    /// parent: `rmdir` on a non-empty directory fails with nothing more
    /// helpful than "Failure", so the browser has to do the walk itself.
    ///
    /// `targets` is the tree in DISCOVERY order (parents before their
    /// children, as a breadth- or depth-first walk produces it); the
    /// returned script reverses that for directories, which is what makes
    /// the deletion bottom-up. Files may be removed in any order and keep
    /// their discovery order.
    static func recursiveDeletion(of targets: [SFTPDeletionTarget]) -> [String] {
        let files = targets.filter { !$0.isDirectory }
        let directories = targets.filter(\.isDirectory)
        return files.map { removeFile(path: $0.path) }
            + directories.reversed().map { removeDirectory(path: $0.path) }
    }

    /// Joins commands into the stdin text for one `sftp -b -` run. Batch
    /// mode aborts on the first failure, so the order above is also the
    /// failure order: a file that cannot be deleted stops the run before
    /// its directory is attempted.
    static func script(_ commands: [String]) -> String {
        commands.joined(separator: "\n") + "\n"
    }
}

/// One path in a recursive deletion walk.
struct SFTPDeletionTarget: Equatable, Sendable {
    let path: String
    let isDirectory: Bool
}
