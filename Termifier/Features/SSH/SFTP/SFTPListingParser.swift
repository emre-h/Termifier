//
//  SFTPListingParser.swift
//  Termifier
//
//  Parses `sftp -b -` output into directory entries.
//
//  SHAPE, captured from the OpenSSH client/server pair shipped with
//  macOS:
//
//      sftp> ls -ln "/tmp/dir"
//      drwxr-xr-x    ? 501      20             64 Sep 11 00:47 /tmp/dir/sub
//      -rw-r--r--    2 501      20              6 Sep 11 00:47 /tmp/dir/a b.txt
//
//  Three things that shape the parser:
//  - Batch mode echoes every command as `sftp> …`; those lines are not
//    data.
//  - When `ls` is given a path, names come back as FULL PATHS, not
//    basenames.
//  - The link-count field is `?` on servers that do not report it, so it
//    cannot be relied on to be numeric.
//
//  LIMIT: the long-listing format is ambiguous for owner or group names
//  containing spaces -- there is no delimiter to recover from. Numeric
//  ids (`ls -n`) are therefore what the browser asks for, and a listing
//  line this parser cannot read is skipped rather than guessed at.
//

import Foundation

enum SFTPListingParser {
    /// Prefix batch mode echoes each command with.
    private static let echoPrefix = "sftp> "
    /// Prefix of `pwd`'s answer.
    private static let workingDirectoryPrefix = "Remote working directory: "

    /// Entries in the listing, excluding `.` and `..` (the browser
    /// navigates with its own Up control, so those rows are noise the
    /// user can only get wrong).
    static func entries(from output: String, directory: String) -> [SFTPEntry] {
        var entries: [SFTPEntry] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard !line.hasPrefix(echoPrefix) else { continue }
            guard let entry = entry(from: line, directory: directory) else { continue }
            guard entry.name != ".", entry.name != ".." else { continue }
            entries.append(entry)
        }
        return entries
    }

    /// The path reported by `pwd`, or `nil` when the output holds no
    /// answer (a failed connection, where the error is on stderr).
    static func workingDirectory(from output: String) -> String? {
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard line.hasPrefix(workingDirectoryPrefix) else { continue }
            let path = String(line.dropFirst(workingDirectoryPrefix.count))
                .trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : path
        }
        return nil
    }

    /// One long-listing line, or `nil` when the line is not one.
    ///
    /// `directory` is the listing's own path, used to rebuild an entry's
    /// absolute path when the server reports a bare name (which it does
    /// for a listing of the current directory, with no path argument).
    static func entry(from line: String, directory: String) -> SFTPEntry? {
        // perms, links, owner, group, size, month, day, time, then the
        // name -- which may itself contain spaces, so it is the whole
        // remainder rather than a ninth field.
        let fields = line.split(
            separator: " ",
            maxSplits: 8,
            omittingEmptySubsequences: true
        ).map(String.init)
        guard fields.count == 9 else { return nil }

        // A listing line starts with a mode string: at least ten
        // characters, all of them permission characters. Checking that
        // (plus a numeric size) is what keeps a stray informational line
        // from being read as an entry.
        let mode = fields[0]
        guard mode.count >= 10,
              mode.allSatisfy({ "dlbcps-rwxsStT+@".contains($0) }),
              let typeCharacter = mode.first,
              Int64(fields[4]) != nil else { return nil }

        return build(
            fields: fields,
            mode: mode,
            kind: SFTPEntryKind(modeCharacter: typeCharacter),
            directory: directory
        )
    }

    private static func build(
        fields: [String],
        mode: String,
        kind: SFTPEntryKind,
        directory: String
    ) -> SFTPEntry? {
        guard let size = Int64(fields[4]) else { return nil }
        let reportedName = fields[8]
        // `ls <path>` answers with full paths; `ls` without one answers
        // with bare names.
        let name = RemotePath.lastComponent(of: reportedName)
        guard !name.isEmpty else { return nil }
        let path = reportedName.hasPrefix(RemotePath.separator)
            ? RemotePath.normalize(reportedName)
            : RemotePath.join(directory, name)

        let permissions = String(mode.dropFirst().prefix(9))
        let modified = "\(fields[5]) \(fields[6]) \(fields[7])"

        return SFTPEntry(
            name: name,
            path: path,
            kind: kind,
            size: size,
            permissions: permissions,
            owner: fields[2],
            group: fields[3],
            modifiedDescription: modified
        )
    }

    /// The message to show for a failed run: sftp puts one line per
    /// failure on stderr (`remote mkdir "/x": Permission denied`). Falls
    /// back to stdout, then to a generic message, so a failure is never
    /// reported as an empty alert.
    static func failureMessage(stderr: String, stdout: String) -> String {
        let candidates = (stderr + "\n" + stdout)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(echoPrefix) }
        return candidates.first ?? "The SFTP command failed."
    }
}
