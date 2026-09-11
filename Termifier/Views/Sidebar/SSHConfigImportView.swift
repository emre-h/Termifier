import SwiftUI

/// Sheet that lists the hosts found in `~/.ssh/config` and turns the
/// selected ones into saved profiles. Hosts already in the sidebar are
/// shown but not selectable, so re-importing after editing the config
/// adds only what is new.
struct SSHConfigImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SSHConnectionStore
    let reader: SSHConfigFileReader

    @State private var folder = "ssh config"
    @State private var candidates: [SSHConfigImportCandidate] = []
    @State private var selection: Set<String> = []
    @State private var didLoad = false

    init(store: SSHConnectionStore, reader: SSHConfigFileReader = SSHConfigFileReader()) {
        self.store = store
        self.reader = reader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from ssh config")
                .font(.title2.weight(.semibold))
            Text(reader.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            if didLoad, candidates.isEmpty {
                ContentUnavailableView(
                    "No Hosts Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No Host blocks with a concrete name were found in your ssh config.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(candidates) { candidate in
                        row(for: candidate)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 240)

                HStack {
                    Button("Select All") { selection = Set(importableIDs) }
                        .controlSize(.small)
                    Button("Select None") { selection = [] }
                        .controlSize(.small)
                    Spacer()
                    TextField("Folder", text: $folder, prompt: Text("optional"))
                        .frame(width: 160)
                }
            }

            HStack {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import", action: performImport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .task { load() }
    }

    private func row(for candidate: SSHConfigImportCandidate) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: binding(for: candidate)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.connection.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(detail(for: candidate))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(candidate.isAlreadySaved)
            Spacer(minLength: 0)
            if candidate.isAlreadySaved {
                Text("Already saved")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func detail(for candidate: SSHConfigImportCandidate) -> String {
        let connection = candidate.connection
        var parts = ["\(connection.destination):\(connection.port)"]
        if !connection.jumpHosts.isEmpty {
            parts.append("via \(connection.jumpHosts.joined(separator: ","))")
        }
        if !connection.forwards.isEmpty {
            parts.append("\(connection.forwards.count) forward(s)")
        }
        if connection.authentication == .identityFile, let file = connection.identityFile {
            parts.append((file as NSString).lastPathComponent)
        }
        return parts.joined(separator: " · ")
    }

    private var importableIDs: [String] {
        candidates.filter { !$0.isAlreadySaved }.map(\.id)
    }

    private var footerText: String {
        if !didLoad { return "Reading ssh config…" }
        let importable = importableIDs.count
        return "\(selection.count) of \(importable) selected"
    }

    private func binding(for candidate: SSHConfigImportCandidate) -> Binding<Bool> {
        Binding(
            get: { selection.contains(candidate.id) },
            set: { isOn in
                if isOn {
                    selection.insert(candidate.id)
                } else {
                    selection.remove(candidate.id)
                }
            }
        )
    }

    private func load() {
        let configText = reader.read() ?? ""
        candidates = SSHConfigImporter.candidates(
            from: configText,
            existing: store.connections,
            folder: folder
        )
        // Pre-select everything importable: the common case is "take all
        // of them", and deselecting a few is less work than ticking ten.
        selection = Set(importableIDs)
        didLoad = true
    }

    private func performImport() {
        // The folder is applied here rather than baked into the
        // candidates, so editing the folder field never has to rebuild
        // (and re-select) the whole list.
        let chosen = candidates
            .filter { selection.contains($0.id) }
            .map { candidate -> SSHConnection in
                var connection = candidate.connection
                connection.folder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
                return connection
            }
        store.importConnections(chosen)
        dismiss()
    }
}
