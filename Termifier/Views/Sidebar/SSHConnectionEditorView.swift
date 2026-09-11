import AppKit
import SwiftUI

/// Add/edit sheet for one saved SSH profile: server, authentication,
/// jump chain, port forwarding, session behavior and the host key
/// recorded for it.
struct SSHConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SSHConnectionStore
    let connection: SSHConnection?
    let knownHosts: SSHKnownHostsService

    @State private var name = ""
    @State private var host = ""
    @State private var username = ""
    @State private var port = "22"
    @State private var folder = ""
    @State private var authentication: SSHAuthenticationMethod = .password
    @State private var password = ""
    @State private var identityFile = ""
    @State private var jumpHosts = ""
    @State private var startupCommand = ""
    @State private var remoteDirectory = ""
    @State private var forwardDrafts: [SSHPortForwardDraft] = []
    @State private var errorMessage: String?
    @State private var knownHostStatus: SSHKnownHostStatus?
    @State private var isCheckingHostKey = false

    init(
        store: SSHConnectionStore,
        connection: SSHConnection? = nil,
        knownHosts: SSHKnownHostsService = SSHKnownHostsService()
    ) {
        self.store = store
        self.connection = connection
        self.knownHosts = knownHosts
        _name = State(initialValue: connection?.name ?? "")
        _host = State(initialValue: connection?.host ?? "")
        _username = State(initialValue: connection?.username ?? "")
        _port = State(initialValue: String(connection?.port ?? 22))
        _folder = State(initialValue: connection?.folder ?? "")
        _authentication = State(initialValue: connection?.authentication ?? .password)
        _identityFile = State(initialValue: connection?.identityFile ?? "")
        _jumpHosts = State(initialValue: (connection?.jumpHosts ?? []).joined(separator: ", "))
        _startupCommand = State(initialValue: connection?.startupCommand ?? "")
        _remoteDirectory = State(initialValue: connection?.remoteDirectory ?? "")
        _forwardDrafts = State(
            initialValue: (connection?.forwards ?? []).map(SSHPortForwardDraft.init(forward:))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(connection == nil ? "Add SSH Connection" : "Edit SSH Connection")
                .font(.title2.weight(.semibold))

            Form {
                serverSection
                authenticationSection
                routingSection
                forwardingSection
                sessionSection
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
                Button(connection == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 620)
        // Re-probed whenever the target changes, debounced because the
        // host field changes on every keystroke.
        .task(id: hostKeyProbeID) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await refreshHostKeyStatus()
        }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section("Server") {
            TextField("Name", text: $name, prompt: Text("Production"))
            TextField("Host", text: $host, prompt: Text("server.example.com"))
            TextField("Username", text: $username, prompt: Text("optional"))
            TextField("Port", text: $port)
            HStack {
                TextField("Folder", text: $folder, prompt: Text("optional"))
                if !store.folders.isEmpty {
                    Menu {
                        Button("None") { folder = "" }
                        Divider()
                        ForEach(store.folders, id: \.self) { existing in
                            Button(existing) { folder = existing }
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }

    private var authenticationSection: some View {
        Section("Authentication") {
            Picker("Method", selection: $authentication) {
                ForEach(SSHAuthenticationMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.segmented)

            switch authentication {
            case .password:
                SecureField("Password", text: $password)
                if connection?.authentication == .password {
                    Text("Leave blank to keep the saved password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .identityFile:
                HStack {
                    TextField("Identity file", text: $identityFile, prompt: Text("~/.ssh/id_ed25519 or .pem"))
                    Button("Choose…", action: chooseIdentityFile)
                }
            case .agent:
                Text("Uses your ssh agent, ~/.ssh/config and the default keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            hostKeyRow
        }
    }

    /// Surfaces `known_hosts` state, and lets the user forget a stale key
    /// -- the fix for the "REMOTE HOST IDENTIFICATION HAS CHANGED" wall
    /// that otherwise leaves a rebuilt server unreachable from the app.
    @ViewBuilder
    private var hostKeyRow: some View {
        LabeledContent("Host key") {
            HStack(spacing: 8) {
                Text(hostKeyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .recorded = knownHostStatus {
                    Button("Forget", action: forgetHostKey)
                        .controlSize(.small)
                        .disabled(isCheckingHostKey)
                }
            }
        }
    }

    /// Identity of the host-key probe: changing either field restarts it.
    private var hostKeyProbeID: String {
        "\(host.trimmingCharacters(in: .whitespacesAndNewlines))|\(port)"
    }

    private var hostKeyDescription: String {
        switch knownHostStatus {
        case .recorded(let keyTypes):
            "Trusted (\(keyTypes.joined(separator: ", ")))"
        case .notRecorded:
            "Not recorded yet"
        case .unavailable, .none:
            isCheckingHostKey ? "Checking…" : "Unknown"
        }
    }

    private var routingSection: some View {
        Section("Jump hosts") {
            TextField("ProxyJump", text: $jumpHosts, prompt: Text("bastion.example.com, user@inner"))
            Text("Comma-separated chain, outermost bastion first. Passed to ssh as -J.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var forwardingSection: some View {
        Section("Port forwarding") {
            ForEach($forwardDrafts) { $draft in
                forwardRow(draft: $draft)
            }
            Button {
                forwardDrafts.append(SSHPortForwardDraft())
            } label: {
                Label("Add Port Forward", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ssh.editor.addForward")
        }
    }

    private func forwardRow(draft: Binding<SSHPortForwardDraft>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Picker("", selection: draft.kind) {
                    ForEach(SSHPortForwardKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 116)

                TextField("port", text: draft.listenPort)
                    .frame(width: 62)

                if draft.wrappedValue.kind.usesTarget {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    TextField("host", text: draft.targetHost)
                        .frame(width: 110)
                    TextField("port", text: draft.targetPort)
                        .frame(width: 62)
                }

                Spacer(minLength: 0)

                Button {
                    forwardDrafts.removeAll { $0.id == draft.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove port forward")
            }

            // Only nag once the row has been started: a freshly added,
            // still-empty row is not an error the user made yet.
            if !draft.wrappedValue.listenPort.isEmpty,
               let error = draft.wrappedValue.validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            TextField("Startup command", text: $startupCommand, prompt: Text("cd /srv/app"))
            Text("Runs on the remote host after login, then hands over to your shell.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Remote folder", text: $remoteDirectory, prompt: Text("~ (home)"))
            Text("Where dragged-in files are uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func chooseIdentityFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose SSH Identity File"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK {
            identityFile = panel.url?.path ?? identityFile
        }
    }

    private func refreshHostKeyStatus() async {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, let portNumber = Int(port) else {
            knownHostStatus = nil
            return
        }
        isCheckingHostKey = true
        knownHostStatus = await knownHosts.status(host: target, port: portNumber)
        isCheckingHostKey = false
    }

    private func forgetHostKey() {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, let portNumber = Int(port) else { return }
        isCheckingHostKey = true
        Task {
            let removed = await knownHosts.forget(host: target, port: portNumber)
            if !removed {
                errorMessage = "Could not remove the host key from known_hosts."
            }
            await refreshHostKeyStatus()
        }
    }

    private func save() {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanIdentity = identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRemoteDirectory = remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanHost.isEmpty else {
            errorMessage = "Host is required."
            return
        }
        guard let portNumber = Int(port), (1...65535).contains(portNumber) else {
            errorMessage = "Port must be between 1 and 65535."
            return
        }
        if authentication == .identityFile {
            guard !cleanIdentity.isEmpty else {
                errorMessage = "Choose an identity file."
                return
            }
            let expandedIdentity = (cleanIdentity as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedIdentity) else {
                errorMessage = "The selected identity file does not exist."
                return
            }
        }

        let hops = Self.parseJumpHosts(jumpHosts)
        if let badHop = hops.first(where: { $0.contains(where: \.isWhitespace) }) {
            errorMessage = "Jump host \"\(badHop)\" must not contain spaces."
            return
        }
        if let forwardError = forwardDrafts.firstValidationError {
            errorMessage = forwardError
            return
        }
        // Checked here rather than at transfer time so the profile cannot
        // store a remote folder that every future upload would reject.
        if cleanRemoteDirectory.rangeOfCharacter(
            from: SSHTransferCommandBuilder.forbiddenRemotePathCharacters
        ) != nil {
            errorMessage = SSHTransferError.unsafeRemotePath(cleanRemoteDirectory).localizedDescription
            return
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedConnection = SSHConnection(
            id: connection?.id ?? UUID(),
            name: cleanName.isEmpty ? cleanHost : cleanName,
            host: cleanHost,
            username: cleanUser,
            port: portNumber,
            authentication: authentication,
            identityFile: authentication == .identityFile ? cleanIdentity : nil,
            folder: cleanFolder,
            jumpHosts: hops,
            forwards: forwardDrafts.forwards,
            startupCommand: startupCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            remoteDirectory: cleanRemoteDirectory
        )

        do {
            if connection == nil {
                try store.add(updatedConnection, password: authentication == .password ? password : nil)
            } else {
                try store.update(updatedConnection, password: authentication == .password ? password : nil)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Comma-separated jump chain -> trimmed, non-empty hops.
    static func parseJumpHosts(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
