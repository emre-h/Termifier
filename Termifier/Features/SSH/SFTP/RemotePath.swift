//
//  RemotePath.swift
//  Termifier
//
//  POSIX remote-path arithmetic for the SFTP browser. Separate from
//  Foundation's URL/NSString path APIs on purpose: those carry local
//  filesystem assumptions (percent-escaping, case behavior, volume
//  handling), while a remote path is just a slash-separated byte string
//  the server interprets.
//

import Foundation

enum RemotePath {
    static let separator = "/"
    static let root = "/"

    /// `base` + `name`, collapsing the duplicate separator that a base of
    /// `/` would otherwise produce.
    static func join(_ base: String, _ name: String) -> String {
        let cleanBase = base.isEmpty ? root : base
        if cleanBase.hasSuffix(separator) { return cleanBase + name }
        return cleanBase + separator + name
    }

    /// The containing directory, or `/` at the root (never "above" it --
    /// an Up button at the root must be a no-op, not an error).
    static func parent(of path: String) -> String {
        let trimmed = stripTrailingSeparator(path)
        guard let index = trimmed.lastIndex(of: "/") else { return root }
        if index == trimmed.startIndex { return root }
        return String(trimmed[trimmed.startIndex..<index])
    }

    /// The final component. Empty only for the root itself.
    static func lastComponent(of path: String) -> String {
        let trimmed = stripTrailingSeparator(path)
        guard let index = trimmed.lastIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: index)...])
    }

    /// Collapses repeated separators and drops a trailing one, so the
    /// path the UI shows and the path sent to sftp are the same string
    /// however the user typed it.
    static func normalize(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return root }
        let isAbsolute = trimmed.hasPrefix(separator)
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        let joined = components.joined(separator: separator)
        if joined.isEmpty { return root }
        return isAbsolute ? separator + joined : joined
    }

    static func isRoot(_ path: String) -> Bool {
        stripTrailingSeparator(path).isEmpty
    }

    private static func stripTrailingSeparator(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix(separator) {
            result.removeLast()
        }
        return result == separator ? "" : result
    }
}
