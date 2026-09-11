import AppKit
import SwiftUI

struct SSHSidebarView: View {
    @Bindable var store: SSHConnectionStore
    var onConnect: (SSHConnection) -> Void
    /// Runs one scp transfer in a terminal tab. Defaulted so callers that
    /// only open sessions stay source-compatible.
    var onTransfer: (SSHTransferRequest) -> Void = { _ in }
    /// Opens the remote file browser window for a profile.
    var onBrowse: (SSHConnection) -> Void = { _ in }

    @State private var tunnelMonitor = SSHTunnelMonitor.shared
    @State private var sheet: SSHSidebarSheet?
    @State private var alertItem: SSHSidebarAlert?
    /// Collapsed folder names, newline-joined. Stored in defaults rather
    /// than `@State` because switching the sidebar to Tabs and back
    /// rebuilds this view, which would otherwise re-expand everything.
    @AppStorage("sshCollapsedFolders") private var collapsedFoldersRaw = ""

    private let knownHosts = SSHKnownHostsService()

    /// How often the locally-listening forwarded ports are re-probed.
    private static let tunnelRefreshInterval: Duration = .seconds(3)

    var body: some View {
        VStack(spacing: 0) {
            if store.connections.isEmpty {
                ContentUnavailableView(
                    "No SSH Connections",
                    systemImage: "network",
                    description: Text("Add a server, or import the hosts from your ssh config.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                connectionList
            }

            Divider()
            footer
        }
        // `sheet(item:)`, not `sheet(isPresented:)`: the editor seeds its
        // `@State` fields from `connection` in its `init`, which SwiftUI
        // runs only once per view identity. Keyed by the presented
        // target's `id`, editing a second connection (or switching
        // between Add and Edit) is a new identity, so those initial
        // values are re-read instead of the first-presented connection's
        // -- previously every Edit after the first showed stale/empty
        // fields.
        .sheet(item: $sheet) { target in
            switch target {
            case .add:
                SSHConnectionEditorView(store: store, connection: nil)
            case .edit(let connection):
                SSHConnectionEditorView(store: store, connection: connection)
            case .importConfig:
                SSHConfigImportView(store: store)
            case .download(let connection):
                SSHDownloadSheet(connection: connection, onTransfer: onTransfer)
            }
        }
        .alert(alertItem?.title ?? "", isPresented: alertBinding) {
            Button("OK", role: .cancel) { alertItem = nil }
        } message: {
            Text(alertItem?.message ?? "")
        }
        // One long-lived probe loop for the whole sidebar: forwarded
        // ports belong to ssh processes the app does not own, so their
        // liveness can only be observed by polling (see SSHTunnelMonitor).
        .task {
            while !Task.isCancelled {
                await tunnelMonitor.refresh(connections: store.connections)
                try? await Task.sleep(for: Self.tunnelRefreshInterval)
            }
        }
    }

    // MARK: - List

    private var groups: [SSHConnectionGroup] {
        SSHConnectionGrouping.groups(for: store.connections)
    }

    private var connectionList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(groups) { group in
                    // A single ungrouped list needs no header -- that is
                    // every profile list that predates folders.
                    if !(groups.count == 1 && group.isUngrouped) {
                        folderHeader(for: group)
                    }
                    if !isCollapsed(group) {
                        ForEach(group.connections) { connection in
                            connectionRow(connection)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func folderHeader(for group: SSHConnectionGroup) -> some View {
        Button {
            toggleCollapsed(group)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed(group) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text(group.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(group.connections.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Folder \(group.title)")
    }

    private func connectionRow(_ connection: SSHConnection) -> some View {
        HStack(spacing: 4) {
            Button {
                onConnect(connection)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: authenticationSymbol(connection.authentication))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(subtitle(for: connection))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    tunnelIndicator(for: connection)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect to \(connection.name)")

            Button {
                onBrowse(connection)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Browse files on \(connection.name)")
            .accessibilityLabel("Browse files on \(connection.name)")

            Button {
                sheet = .edit(connection)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.trailing, 6)
            .accessibilityLabel("Edit \(connection.name)")
        }
        // Dropping files on a row uploads them to the profile's remote
        // folder -- the shortest path from "this file" to "on that box".
        .dropDestination(for: URL.self) { urls, _ in
            upload(urls: urls, to: connection)
        }
        .contextMenu { contextMenu(for: connection) }
    }

    @ViewBuilder
    private func contextMenu(for connection: SSHConnection) -> some View {
        Button("Connect") { onConnect(connection) }
        Button("Browse Files…") { onBrowse(connection) }
        Divider()
        Button("Upload Files…") { chooseUpload(for: connection) }
        Button("Download…") { sheet = .download(connection) }
        Divider()
        Button("Edit…") { sheet = .edit(connection) }
        Menu("Move to Folder") {
            Button("Ungrouped") { move(connection, to: "") }
            if !store.folders.isEmpty {
                Divider()
                ForEach(store.folders, id: \.self) { folder in
                    Button(folder) { move(connection, to: folder) }
                }
            }
        }
        Button("Forget Host Key") { forgetHostKey(for: connection) }
        Divider()
        Button("Delete", role: .destructive) {
            do {
                try store.delete(connection)
            } catch {
                alertItem = .error(error.localizedDescription)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button {
                sheet = .add
            } label: {
                Label("Add SSH Connection", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar.ssh.addConnection")

            Button {
                sheet = .importConfig
            } label: {
                Label("Import from ssh config", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar.ssh.importConfig")
        }
        .padding(8)
    }

    // MARK: - Row details

    private func authenticationSymbol(_ method: SSHAuthenticationMethod) -> String {
        switch method {
        case .password: "key.fill"
        case .identityFile: "doc.badge.key"
        case .agent: "person.badge.key"
        }
    }

    private func subtitle(for connection: SSHConnection) -> String {
        var text = "\(connection.destination):\(connection.port)"
        if !connection.jumpHosts.isEmpty {
            text += " ↪ \(connection.jumpHosts.count)"
        }
        return text
    }

    @ViewBuilder
    private func tunnelIndicator(for connection: SSHConnection) -> some View {
        let status = tunnelMonitor.status(for: connection)
        if status != .none {
            Image(systemName: tunnelSymbol(status))
                .font(.system(size: 8))
                .foregroundStyle(tunnelColor(status))
                .help(tunnelHelp(for: connection, status: status))
                .accessibilityLabel(status.summary)
        }
    }

    private func tunnelSymbol(_ status: SSHTunnelStatus) -> String {
        switch status {
        case .up, .partial: "circle.fill"
        // A profile you simply are not connected to is the resting state,
        // not a failure, so it gets an outline rather than a red dot.
        case .down: "circle"
        case .remoteOnly: "circle.dotted"
        case .none: "circle"
        }
    }

    private func tunnelColor(_ status: SSHTunnelStatus) -> Color {
        switch status {
        case .up: .green
        case .partial: .orange
        case .down, .remoteOnly, .none: .secondary
        }
    }

    private func tunnelHelp(for connection: SSHConnection, status: SSHTunnelStatus) -> String {
        let rules = connection.forwards.map(\.displayText).joined(separator: "\n")
        return rules.isEmpty ? status.summary : "\(status.summary)\n\(rules)"
    }

    // MARK: - Folders

    private var collapsedFolders: Set<String> {
        Set(collapsedFoldersRaw.split(separator: "\n").map(String.init))
    }

    private func isCollapsed(_ group: SSHConnectionGroup) -> Bool {
        !group.isUngrouped && collapsedFolders.contains(group.folder)
    }

    private func toggleCollapsed(_ group: SSHConnectionGroup) {
        guard !group.isUngrouped else { return }
        var folders = collapsedFolders
        if folders.contains(group.folder) {
            folders.remove(group.folder)
        } else {
            folders.insert(group.folder)
        }
        collapsedFoldersRaw = folders.sorted().joined(separator: "\n")
    }

    private func move(_ connection: SSHConnection, to folder: String) {
        do {
            try store.move(connection, toFolder: folder)
        } catch {
            alertItem = .error(error.localizedDescription)
        }
    }

    // MARK: - Transfers

    private func upload(urls: [URL], to connection: SSHConnection) -> Bool {
        let paths = urls.filter(\.isFileURL).map(\.path)
        guard !paths.isEmpty else { return false }
        onTransfer(.upload(connection: connection, localPaths: paths))
        return true
    }

    private func chooseUpload(for connection: SSHConnection) {
        let panel = NSOpenPanel()
        panel.title = "Upload to \(connection.name)"
        panel.prompt = "Upload"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        onTransfer(.upload(connection: connection, localPaths: panel.urls.map(\.path)))
    }

    // MARK: - Host keys

    private func forgetHostKey(for connection: SSHConnection) {
        Task {
            let removed = await knownHosts.forget(for: connection)
            alertItem = removed
                ? .info(
                    title: "Host Key Forgotten",
                    message: "\(connection.host) was removed from known_hosts. "
                        + "Its key will be recorded again on the next connection."
                )
                : .error("Could not remove \(connection.host) from known_hosts.")
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertItem != nil },
            set: { if !$0 { alertItem = nil } }
        )
    }
}

/// What the SSH sidebar is currently presenting. `Identifiable` so
/// `sheet(item:)` can key the sheet's view identity on it: each target is
/// a distinct identity, which is what makes the editor re-read its
/// initial field values.
private enum SSHSidebarSheet: Identifiable {
    case add
    case edit(SSHConnection)
    case importConfig
    case download(SSHConnection)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let connection): "edit-\(connection.id.uuidString)"
        case .importConfig: "import"
        case .download(let connection): "download-\(connection.id.uuidString)"
        }
    }
}

private struct SSHSidebarAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static func error(_ message: String) -> SSHSidebarAlert {
        SSHSidebarAlert(title: "SSH Connection Error", message: message)
    }

    static func info(title: String, message: String) -> SSHSidebarAlert {
        SSHSidebarAlert(title: title, message: message)
    }
}

/// Asks for a remote path and a local destination, then hands the
/// download to the window controller as a normal transfer.
private struct SSHDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let connection: SSHConnection
    let onTransfer: (SSHTransferRequest) -> Void

    @State private var remotePath: String
    @State private var localDirectory: String
    @State private var errorMessage: String?

    init(connection: SSHConnection, onTransfer: @escaping (SSHTransferRequest) -> Void) {
        self.connection = connection
        self.onTransfer = onTransfer
        _remotePath = State(initialValue: connection.remoteDirectory)
        _localDirectory = State(
            initialValue: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
                .first?.path ?? NSHomeDirectory()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download from \(connection.name)")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Remote path", text: $remotePath, prompt: Text("/var/log/app.log"))
                HStack {
                    TextField("Save to", text: $localDirectory)
                    Button("Choose…", action: chooseLocalDirectory)
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Download", action: start)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func chooseLocalDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            localDirectory = url.path
        }
    }

    private func start() {
        let path = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            errorMessage = "Enter the remote file or folder to download."
            return
        }
        guard !localDirectory.isEmpty else {
            errorMessage = SSHTransferError.missingLocalDirectory.localizedDescription
            return
        }
        onTransfer(
            .download(connection: connection, remotePath: path, localDirectory: localDirectory)
        )
        dismiss()
    }
}
