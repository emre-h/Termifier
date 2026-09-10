import AppKit
import SwiftUI

struct SSHSidebarView: View {
    @Bindable var store: SSHConnectionStore
    var onConnect: (SSHConnection) -> Void

    @State private var showingEditor = false
    @State private var editingConnection: SSHConnection?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if store.connections.isEmpty {
                ContentUnavailableView(
                    "No SSH Connections",
                    systemImage: "network",
                    description: Text("Add a server to open it in a terminal tab.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.connections) { connection in
                            HStack(spacing: 4) {
                                Button {
                                    onConnect(connection)
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: connection.authentication == .password ? "key.fill" : "doc.badge.key")
                                            .frame(width: 18)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(connection.name)
                                                .font(.system(size: 12, weight: .semibold))
                                                .lineLimit(1)
                                            Text("\(connection.destination):\(connection.port)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
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
                                    editingConnection = connection
                                    showingEditor = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 24, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 6)
                                .accessibilityLabel("Edit \(connection.name)")
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    do {
                                        try store.delete(connection)
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }

            Divider()

            Button {
                editingConnection = nil
                showingEditor = true
            } label: {
                Label("Add SSH Connection", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityIdentifier("sidebar.ssh.addConnection")
        }
        .sheet(isPresented: $showingEditor) {
            SSHConnectionEditorView(store: store, connection: editingConnection)
        }
        .alert("SSH Connection Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

private struct SSHConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SSHConnectionStore
    let connection: SSHConnection?

    @State private var name = ""
    @State private var host = ""
    @State private var username = ""
    @State private var port = "22"
    @State private var authentication: SSHAuthenticationMethod = .password
    @State private var password = ""
    @State private var identityFile = ""
    @State private var errorMessage: String?

    init(store: SSHConnectionStore, connection: SSHConnection? = nil) {
        self.store = store
        self.connection = connection
        _name = State(initialValue: connection?.name ?? "")
        _host = State(initialValue: connection?.host ?? "")
        _username = State(initialValue: connection?.username ?? "")
        _port = State(initialValue: String(connection?.port ?? 22))
        _authentication = State(initialValue: connection?.authentication ?? .password)
        _identityFile = State(initialValue: connection?.identityFile ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(connection == nil ? "Add SSH Connection" : "Edit SSH Connection")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $name, prompt: Text("Production"))
                TextField("Host", text: $host, prompt: Text("server.example.com"))
                TextField("Username", text: $username, prompt: Text("optional"))
                TextField("Port", text: $port)

                Picker("Authentication", selection: $authentication) {
                    ForEach(SSHAuthenticationMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if authentication == .password {
                    SecureField("Password", text: $password)
                    if connection?.authentication == .password {
                        Text("Leave blank to keep the saved password.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        TextField("Identity file", text: $identityFile, prompt: Text("~/.ssh/id_ed25519 or .pem"))
                        Button("Choose…", action: chooseIdentityFile)
                    }
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
                Button(connection == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

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

    private func save() {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanIdentity = identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else {
            errorMessage = "Host is required."
            return
        }
        guard let portNumber = Int(port), (1...65535).contains(portNumber) else {
            errorMessage = "Port must be between 1 and 65535."
            return
        }
        if authentication == .identityFile, cleanIdentity.isEmpty {
            errorMessage = "Choose an identity file."
            return
        }
        if authentication == .identityFile {
            let expandedIdentity = (cleanIdentity as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedIdentity) else {
                errorMessage = "The selected identity file does not exist."
                return
            }
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedConnection = SSHConnection(
            id: connection?.id ?? UUID(),
            name: cleanName.isEmpty ? cleanHost : cleanName,
            host: cleanHost,
            username: cleanUser,
            port: portNumber,
            authentication: authentication,
            identityFile: authentication == .identityFile ? cleanIdentity : nil
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
}
