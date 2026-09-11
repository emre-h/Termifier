import AppKit
import SwiftUI

/// Remote file browser content: a location bar, a listing table, and the
/// operations a file manager is expected to have. Every decision worth
/// testing lives in `SSHFileBrowserModel`; this file is presentation and
/// the small prompts (new folder, rename, permissions, delete
/// confirmation) that feed it.
struct SSHFileBrowserView: View {
    @Bindable var model: SSHFileBrowserModel

    @State private var prompt: BrowserPrompt?
    @State private var promptText = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            locationBar
            Divider()
            listing
            Divider()
            statusBar
        }
        // Lives in a tab beside the terminal, so it has to survive a
        // narrow window rather than dictate one.
        .frame(minWidth: 420, minHeight: 240)
        .task { await model.start() }
        .sheet(item: $prompt) { target in
            promptSheet(for: target)
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let targets = model.selectedEntries
                Task { await model.delete(targets) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Folders are deleted with everything inside them. "
                    + "This cannot be undone from Termifier."
            )
        }
    }

    // MARK: - Location bar

    private var locationBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.goUp() }
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!model.canGoUp)
            .help("Enclosing folder")

            Button {
                Task { await model.goHome() }
            } label: {
                Image(systemName: "house")
            }
            .help("Home directory")

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            TextField("Path", text: $model.pathDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit {
                    let target = model.pathDraft
                    Task { await model.navigate(to: target) }
                }
                .accessibilityIdentifier("ssh.browser.path")

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Listing

    private var listing: some View {
        Table(model.visibleEntries, selection: $model.selection) {
            TableColumn("Name") { entry in
                HStack(spacing: 6) {
                    Image(systemName: entry.kind.symbolName)
                        .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                    Text(entry.name)
                        .lineLimit(1)
                }
            }
            .width(min: 180, ideal: 280)

            TableColumn("Size") { entry in
                Text(entry.sizeDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Modified") { entry in
                Text(entry.modifiedDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Permissions") { entry in
                Text(entry.permissions)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 100)

            TableColumn("Owner") { entry in
                Text(entry.owner)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
        }
        // `primaryAction` is the double-click/Return action; the menu is
        // the right-click menu for whatever the click landed on.
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(for: ids)
        } primaryAction: { ids in
            guard let entry = entry(for: ids) else { return }
            Task { await model.open(entry) }
        }
        // Dropping into the window uploads into the directory on screen.
        .dropDestination(for: URL.self) { urls, _ in
            let paths = urls.filter(\.isFileURL).map(\.path)
            guard !paths.isEmpty else { return false }
            model.upload(localPaths: paths)
            return true
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<String>) -> some View {
        let targets = model.visibleEntries.filter { ids.contains($0.id) }
        if let single = targets.first, targets.count == 1 {
            Button(single.isDirectory ? "Open" : "Download") {
                Task { await model.open(single) }
            }
            Button("Rename…") {
                promptText = single.name
                prompt = .rename(single)
            }
            Button("Permissions…") {
                promptText = single.octalMode ?? ""
                prompt = .permissions(single)
            }
            Divider()
        } else if targets.count > 1 {
            Button("Download \(targets.count) Items") {
                model.download(targets)
            }
            Divider()
        }
        Button("New Folder…") {
            promptText = ""
            prompt = .newFolder
        }
        Button("Upload Files…", action: chooseUpload)
        if !targets.isEmpty {
            Divider()
            Button("Delete", role: .destructive) {
                model.selection = Set(targets.map(\.id))
                isConfirmingDelete = true
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let errorMessage = model.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .font(.caption)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Button("Dismiss") { model.errorMessage = nil }
                    .controlSize(.small)
            } else {
                Text(countSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("Hidden", isOn: $model.showHidden)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Picker("", selection: $model.sortField) {
                ForEach(SSHFileBrowserModel.SortField.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 96)

            Button {
                model.sortAscending.toggle()
            } label: {
                Image(systemName: model.sortAscending ? "arrow.up" : "arrow.down")
            }
            .controlSize(.small)
            .help(model.sortAscending ? "Ascending" : "Descending")

            Button {
                promptText = ""
                prompt = .newFolder
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New folder")
            .accessibilityIdentifier("ssh.browser.newFolder")

            Button(action: chooseUpload) {
                Image(systemName: "arrow.up.doc")
            }
            .help("Upload files")

            Button {
                model.download(model.selectedEntries)
            } label: {
                Image(systemName: "arrow.down.doc")
            }
            .disabled(model.selection.isEmpty)
            .help("Download selection")

            Button {
                isConfirmingDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(model.selection.isEmpty)
            .help("Delete selection")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var countSummary: String {
        let total = model.visibleEntries.count
        let selected = model.selection.count
        let items = total == 1 ? "1 item" : "\(total) items"
        return selected > 0 ? "\(items), \(selected) selected" : items
    }

    private var deleteConfirmationTitle: String {
        let count = model.selectedEntries.count
        return count == 1
            ? "Delete \"\(model.selectedEntries[0].name)\"?"
            : "Delete \(count) items?"
    }

    // MARK: - Prompts

    private func promptSheet(for target: BrowserPrompt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target.title)
                .font(.headline)
            TextField(target.placeholder, text: $promptText)
                .frame(width: 300)
                .onSubmit { submit(target) }
            if let help = target.help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { prompt = nil }
                    .keyboardShortcut(.cancelAction)
                Button(target.confirmTitle) { submit(target) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func submit(_ target: BrowserPrompt) {
        let text = promptText
        prompt = nil
        Task {
            switch target {
            case .newFolder:
                await model.createFolder(named: text)
            case .rename(let entry):
                await model.rename(entry, to: text)
            case .permissions(let entry):
                await model.changeMode(entry, to: text)
            }
        }
    }

    private func chooseUpload() {
        let panel = NSOpenPanel()
        panel.title = "Upload to \(model.path)"
        panel.prompt = "Upload"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        model.upload(localPaths: panel.urls.map(\.path))
    }

    private func entry(for ids: Set<String>) -> SFTPEntry? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return model.visibleEntries.first { $0.id == id }
    }
}

/// The single-field prompts the browser needs. `Identifiable` so
/// `sheet(item:)` gives each one its own view identity.
private enum BrowserPrompt: Identifiable {
    case newFolder
    case rename(SFTPEntry)
    case permissions(SFTPEntry)

    var id: String {
        switch self {
        case .newFolder: "new-folder"
        case .rename(let entry): "rename-\(entry.path)"
        case .permissions(let entry): "chmod-\(entry.path)"
        }
    }

    var title: String {
        switch self {
        case .newFolder: "New Folder"
        case .rename(let entry): "Rename \"\(entry.name)\""
        case .permissions(let entry): "Permissions for \"\(entry.name)\""
        }
    }

    var placeholder: String {
        switch self {
        case .newFolder: "Folder name"
        case .rename: "New name"
        case .permissions: "755"
        }
    }

    var confirmTitle: String {
        switch self {
        case .newFolder: "Create"
        case .rename: "Rename"
        case .permissions: "Apply"
        }
    }

    var help: String? {
        switch self {
        case .permissions: "Three or four octal digits, as passed to chmod."
        case .newFolder, .rename: nil
        }
    }
}
