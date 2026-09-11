//
//  SSHConnectionGrouping.swift
//  Termifier
//
//  Groups saved profiles into the sidebar's collapsible folder sections.
//  Pure function so the ordering rules are pinned by tests rather than by
//  reading SwiftUI code.
//

import Foundation

struct SSHConnectionGroup: Identifiable, Equatable, Sendable {
    /// The folder name; empty for the ungrouped bucket.
    let folder: String
    let connections: [SSHConnection]

    var id: String { folder }
    var isUngrouped: Bool { folder.isEmpty }
    var title: String { folder.isEmpty ? "Ungrouped" : folder }
}

enum SSHConnectionGrouping {
    /// Ungrouped profiles first (they are what an upgrading user has, so
    /// the sidebar must not suddenly hide them under a header), then
    /// named folders sorted case-insensitively. Within a group the saved
    /// order is preserved.
    ///
    /// The ungrouped section is omitted entirely when every profile has a
    /// folder, and a single ungrouped-only list produces one group -- the
    /// view renders that without a header.
    static func groups(for connections: [SSHConnection]) -> [SSHConnectionGroup] {
        var ungrouped: [SSHConnection] = []
        var byFolder: [String: [SSHConnection]] = [:]

        for connection in connections {
            let folder = connection.folder.trimmingCharacters(in: .whitespacesAndNewlines)
            if folder.isEmpty {
                ungrouped.append(connection)
            } else {
                byFolder[folder, default: []].append(connection)
            }
        }

        var groups: [SSHConnectionGroup] = []
        if !ungrouped.isEmpty {
            groups.append(SSHConnectionGroup(folder: "", connections: ungrouped))
        }
        for folder in byFolder.keys.sorted(by: {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }) {
            groups.append(SSHConnectionGroup(folder: folder, connections: byFolder[folder] ?? []))
        }
        return groups
    }
}
