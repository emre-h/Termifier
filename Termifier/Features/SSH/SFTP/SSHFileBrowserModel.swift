//
//  SSHFileBrowserModel.swift
//  Termifier
//
//  State and behavior of the remote file browser window. All of the logic
//  worth testing lives here; `SSHFileBrowserView` /
//  `SSHFileBrowserWindowController` are the SwiftUI/AppKit shell around
//  it, and `SFTPOperations` is the seam tests replace.
//

import Foundation
import Observation

@MainActor
@Observable
final class SSHFileBrowserModel {
    enum SortField: String, CaseIterable, Sendable {
        case name
        case size
        case modified

        var title: String {
            switch self {
            case .name: "Name"
            case .size: "Size"
            case .modified: "Modified"
            }
        }
    }

    let connection: SSHConnection

    private(set) var path = ""
    private(set) var entries: [SFTPEntry] = []
    private(set) var isLoading = false
    var errorMessage: String?
    /// Row ids (absolute paths) the user has selected.
    var selection: Set<String> = []
    var showHidden = false {
        didSet { guard showHidden != oldValue else { return }; reload() }
    }
    var sortField: SortField = .name {
        didSet { guard sortField != oldValue else { return }; sortEntries() }
    }
    var sortAscending = true {
        didSet { guard sortAscending != oldValue else { return }; sortEntries() }
    }
    /// The path shown in the editable location field, which may differ
    /// from `path` while the user is typing.
    var pathDraft = ""

    /// Download one entry. Wired to the same scp-in-a-tab transfer the
    /// sidebar uses, so a big file shows a progress meter instead of
    /// freezing a window.
    var onDownload: ((SFTPEntry) -> Void)?
    /// Upload local paths into the directory given as the second argument.
    var onUpload: (([String], String) -> Void)?

    private let operations: any SFTPOperations

    init(connection: SSHConnection, operations: any SFTPOperations) {
        self.connection = connection
        self.operations = operations
    }

    /// Entries as shown: hidden ones filtered unless asked for.
    ///
    /// The filter is applied here rather than by asking the server for a
    /// shorter listing, so toggling "show hidden" is instant and does not
    /// depend on a round trip.
    var visibleEntries: [SFTPEntry] {
        showHidden ? entries : entries.filter { !$0.isHidden }
    }

    var selectedEntries: [SFTPEntry] {
        visibleEntries.filter { selection.contains($0.id) }
    }

    var canGoUp: Bool { !path.isEmpty && !RemotePath.isRoot(path) }

    var windowTitle: String { "\(connection.name) — Files" }

    // MARK: - Navigation

    /// Resolves the remote home directory and lists it. Called once when
    /// the window opens.
    func start() async {
        guard path.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let home = try await operations.workingDirectory()
            await load(path: RemotePath.normalize(home))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func navigate(to target: String) async {
        await load(path: RemotePath.normalize(target))
    }

    func goUp() async {
        guard canGoUp else { return }
        await load(path: RemotePath.parent(of: path))
    }

    func goHome() async {
        do {
            let home = try await operations.workingDirectory()
            await load(path: RemotePath.normalize(home))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Double-click/Return on a row: directories are entered, everything
    /// else is downloaded. A symlink is tried as a directory first,
    /// because that is what most symlinks in a listing are; if the server
    /// says otherwise it is downloaded instead.
    func open(_ entry: SFTPEntry) async {
        switch entry.kind {
        case .directory:
            await load(path: entry.path)
        case .symlink:
            let previousPath = path
            await load(path: entry.path)
            if path == previousPath {
                errorMessage = nil
                onDownload?(entry)
            }
        case .file, .other:
            onDownload?(entry)
        }
    }

    func refresh() async {
        guard !path.isEmpty else { return }
        await load(path: path)
    }

    private func load(path target: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Ask for hidden entries always and filter locally, so the
            // toggle needs no round trip.
            let listed = try await operations.list(path: target, includeHidden: true)
            path = target
            pathDraft = target
            entries = listed
            selection = []
            errorMessage = nil
            sortEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fire-and-forget reload, for the `didSet` hooks that cannot await.
    private func reload() {
        Task { await refresh() }
    }

    // MARK: - Mutations

    func createFolder(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValidName(trimmed) else {
            errorMessage = "A folder name cannot be empty or contain \"/\"."
            return
        }
        await perform {
            try await operations.makeDirectory(path: RemotePath.join(path, trimmed))
        }
    }

    func rename(_ entry: SFTPEntry, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValidName(trimmed) else {
            errorMessage = "A name cannot be empty or contain \"/\"."
            return
        }
        guard trimmed != entry.name else { return }
        await perform {
            try await operations.rename(
                from: entry.path,
                to: RemotePath.join(RemotePath.parent(of: entry.path), trimmed)
            )
        }
    }

    func changeMode(_ entry: SFTPEntry, to octal: String) async {
        let trimmed = octal.trimmingCharacters(in: .whitespaces)
        guard Self.isValidOctalMode(trimmed) else {
            errorMessage = "Permissions must be three or four octal digits, such as 755."
            return
        }
        await perform {
            try await operations.changeMode(octal: trimmed, path: entry.path)
        }
    }

    /// Deletes the given entries, stopping at the first failure so the
    /// user sees which one broke rather than a half-finished sweep with no
    /// explanation.
    func delete(_ targets: [SFTPEntry]) async {
        guard !targets.isEmpty else { return }
        await perform {
            for entry in targets {
                try await operations.delete(entry)
            }
        }
    }

    func upload(localPaths: [String]) {
        guard !localPaths.isEmpty, !path.isEmpty else { return }
        onUpload?(localPaths, path)
    }

    func download(_ targets: [SFTPEntry]) {
        for entry in targets {
            onDownload?(entry)
        }
    }

    /// Runs a mutation and refreshes the listing on success.
    private func perform(_ work: () async throws -> Void) async {
        isLoading = true
        do {
            try await work()
            errorMessage = nil
            isLoading = false
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Sorting and validation

    private func sortEntries() {
        // Directories first in every order: a listing where folders and
        // files interleave is far harder to scan.
        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let ordered: Bool
            switch sortField {
            case .name:
                ordered = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .size:
                ordered = lhs.size < rhs.size
            case .modified:
                ordered = lhs.modifiedDescription < rhs.modifiedDescription
            }
            return sortAscending ? ordered : !ordered
        }
    }

    /// A single path component: no separators, and not a relative marker.
    private func isValidName(_ name: String) -> Bool {
        !name.contains("/") && name != "." && name != ".."
    }

    static func isValidOctalMode(_ mode: String) -> Bool {
        guard (3...4).contains(mode.count) else { return false }
        return mode.allSatisfy { ("0"..."7").contains(String($0)) }
    }
}
