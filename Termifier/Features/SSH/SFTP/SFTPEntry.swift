//
//  SFTPEntry.swift
//  Termifier
//
//  One row of a remote directory listing.
//

import Foundation

enum SFTPEntryKind: String, Equatable, Sendable {
    case file
    case directory
    case symlink
    case other

    /// The type character of a long listing's permission field.
    init(modeCharacter: Character) {
        switch modeCharacter {
        case "d": self = .directory
        case "l": self = .symlink
        case "-": self = .file
        default: self = .other
        }
    }

    var symbolName: String {
        switch self {
        case .directory: "folder"
        case .symlink: "arrow.triangle.turn.up.right.circle"
        case .file: "doc"
        case .other: "questionmark.square.dashed"
        }
    }
}

struct SFTPEntry: Identifiable, Equatable, Sendable {
    var name: String
    /// Absolute remote path; also the identity, since two entries in one
    /// listing can never share it.
    var path: String
    var kind: SFTPEntryKind
    var size: Int64
    /// The `rwxr-xr-x` part of the listing, without the type character.
    var permissions: String
    var owner: String
    var group: String
    /// The listing's date field, verbatim. Kept as text because a long
    /// listing gives either a time or a year depending on age, and
    /// without the server's timezone there is nothing to parse it into
    /// that would not be a guess.
    var modifiedDescription: String

    var id: String { path }

    var isDirectory: Bool { kind == .directory }

    /// Dotfiles, which the browser hides unless asked.
    var isHidden: Bool { name.hasPrefix(".") }

    /// The permission string as an octal mode (`rwxr-xr-x` -> `755`), for
    /// prefilling the permissions editor. `nil` when the listing's field
    /// is not a plain 9-character rwx triple (ACL `+`, `t`/`s` bits).
    var octalMode: String? {
        guard permissions.count == 9 else { return nil }
        var digits = ""
        for triple in stride(from: 0, to: 9, by: 3) {
            let start = permissions.index(permissions.startIndex, offsetBy: triple)
            let end = permissions.index(start, offsetBy: 3)
            var value = 0
            for (offset, character) in permissions[start..<end].enumerated() {
                switch (offset, character) {
                case (0, "r"): value += 4
                case (1, "w"): value += 2
                case (2, "x"): value += 1
                case (_, "-"): continue
                default: return nil
                }
            }
            digits += String(value)
        }
        return digits
    }

    var sizeDescription: String {
        kind == .directory
            ? "--"
            : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
