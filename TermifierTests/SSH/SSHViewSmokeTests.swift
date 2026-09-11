import AppKit
import SwiftUI
import Testing
@testable import Termifier

/// Renders the SSH views through a real `NSHostingView` and forces a
/// layout pass.
///
/// WHY: every other SSH test exercises logic that was deliberately kept
/// out of the views, so nothing else evaluates a SwiftUI `body` at all --
/// a malformed `Table`, a binding into a collection that no longer holds
/// the row, or a sheet built from a stale identity are runtime failures a
/// type-checked build does not catch. These tests are deliberately shallow:
/// they assert that the view hierarchy builds and lays out, which is the
/// failure mode worth catching here.
@MainActor
@Suite("SSH view rendering")
struct SSHViewSmokeTests {

    /// Lays out `view` at a realistic size and returns its fitting size,
    /// which is non-zero only if the body actually produced content.
    private func render(_ view: some View, width: CGFloat = 820, height: CGFloat = 560) -> NSSize {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    private func store(_ connections: [SSHConnection]) -> SSHConnectionStore {
        let suiteName = "SSHViewSmokeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SSHConnectionStore(
            defaults: defaults,
            credentialStore: NoopCredentialStore()
        )
        for connection in connections {
            try? store.add(connection, password: nil)
        }
        return store
    }

    private func connection(
        name: String = "Production",
        folder: String = "",
        forwards: [SSHPortForward] = []
    ) -> SSHConnection {
        SSHConnection(
            name: name,
            host: "\(name.lowercased()).example.com",
            username: "deploy",
            authentication: .agent,
            folder: folder,
            jumpHosts: forwards.isEmpty ? [] : ["bastion.example.com"],
            forwards: forwards,
            startupCommand: "cd /srv/app",
            remoteDirectory: "/srv/uploads"
        )
    }

    @Test("The sidebar renders with no saved profiles")
    func emptySidebar() {
        let size = render(SSHSidebarView(store: store([]), onConnect: { _ in }))

        #expect(size.width > 0)
    }

    @Test("The sidebar renders folders, jump hosts and tunnel indicators")
    func populatedSidebar() {
        let connections = [
            connection(),
            connection(name: "Staging", folder: "Dev"),
            connection(
                name: "Tunnelled",
                folder: "Prod",
                forwards: [
                    SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80),
                    SSHPortForward(kind: .remote, listenPort: 9000, targetHost: "localhost", targetPort: 3000),
                    SSHPortForward(kind: .dynamic, listenPort: 1080),
                ]
            ),
        ]

        let size = render(
            SSHSidebarView(store: store(connections), onConnect: { _ in })
        )

        #expect(size.width > 0)
    }

    @Test("The profile editor renders in add and edit modes")
    func editor() {
        let store = store([])
        // A known-hosts service that answers without spawning ssh-keygen.
        let knownHosts = SSHKnownHostsService(run: { _ in (status: 1, output: "") })

        let addSize = render(
            SSHConnectionEditorView(store: store, connection: nil, knownHosts: knownHosts)
        )
        let editSize = render(
            SSHConnectionEditorView(
                store: store,
                connection: connection(
                    forwards: [
                        SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80),
                        SSHPortForward(kind: .dynamic, listenPort: 1080),
                    ]
                ),
                knownHosts: knownHosts
            )
        )

        #expect(addSize.width > 0)
        #expect(editSize.width > 0)
    }

    @Test("The ssh config import sheet renders the hosts it found")
    func importSheet() {
        let configText = """
        Host prod
            HostName prod.example.com
            User deploy
            LocalForward 8080 localhost:80
        Host staging
            HostName staging.example.com
        """
        let reader = SSHConfigFileReader(
            rootResolver: StubRootResolver(),
            loadConfig: { _ in configText }
        )

        let size = render(SSHConfigImportView(store: store([]), reader: reader))

        #expect(size.width > 0)
    }

    @Test("The file browser renders a listing")
    func fileBrowser() async {
        let directory = "/home/deploy"
        let entries = [
            SFTPEntry(
                name: "logs",
                path: "\(directory)/logs",
                kind: .directory,
                size: 4096,
                permissions: "rwxr-xr-x",
                owner: "501",
                group: "20",
                modifiedDescription: "Sep 11 00:47"
            ),
            SFTPEntry(
                name: "notes with space.txt",
                path: "\(directory)/notes with space.txt",
                kind: .file,
                size: 12,
                permissions: "rw-r--r--",
                owner: "501",
                group: "20",
                modifiedDescription: "Sep 11 00:47"
            ),
        ]
        let model = SSHFileBrowserModel(
            connection: connection(),
            operations: StubOperations(home: directory, entries: entries)
        )
        await model.start()

        let size = render(SSHFileBrowserView(model: model))

        #expect(model.entries.count == 2)
        #expect(size.width > 0)
    }

    @Test("The file browser renders an empty directory and an error state")
    func fileBrowserStates() async {
        let model = SSHFileBrowserModel(
            connection: connection(),
            operations: StubOperations(home: "/home/deploy", entries: [])
        )
        await model.start()
        #expect(render(SSHFileBrowserView(model: model)).width > 0)

        model.errorMessage = "remote mkdir \"/nope\": Permission denied"
        #expect(render(SSHFileBrowserView(model: model)).width > 0)
    }

    // MARK: - Stubs

    private struct StubRootResolver: SessionRootResolverProtocol {
        func resolve() -> String { "/tmp/termifier-tests-home" }
    }

    private struct NoopCredentialStore: SSHCredentialStoring {
        func save(password: String, for connectionID: UUID) throws {}
        func deletePassword(for connectionID: UUID) throws {}
    }

    private struct StubOperations: SFTPOperations {
        let home: String
        let entries: [SFTPEntry]

        func workingDirectory() async throws -> String { home }
        func list(path: String, includeHidden: Bool) async throws -> [SFTPEntry] {
            path == home ? entries : []
        }
        func makeDirectory(path: String) async throws {}
        func rename(from: String, to destination: String) async throws {}
        func delete(_ entry: SFTPEntry) async throws {}
        func changeMode(octal: String, path: String) async throws {}
    }
}
