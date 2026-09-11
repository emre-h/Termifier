import Foundation
import Testing
@testable import Termifier

@MainActor
@Suite("SSH file browser model")
struct SSHFileBrowserModelTests {

    // MARK: - Fixtures

    private static func entry(
        _ name: String,
        in directory: String = "/home/deploy",
        kind: SFTPEntryKind = .file,
        size: Int64 = 10,
        permissions: String = "rw-r--r--"
    ) -> SFTPEntry {
        SFTPEntry(
            name: name,
            path: RemotePath.join(directory, name),
            kind: kind,
            size: size,
            permissions: permissions,
            owner: "501",
            group: "20",
            modifiedDescription: "Sep 11 00:47"
        )
    }

    private static func model(
        listings: [String: [SFTPEntry]] = [:],
        home: String = "/home/deploy"
    ) -> (SSHFileBrowserModel, FakeSFTP) {
        let fake = FakeSFTP(home: home, listings: listings)
        let model = SSHFileBrowserModel(
            connection: SSHConnection(name: "Production", host: "example.com"),
            operations: fake
        )
        return (model, fake)
    }

    // MARK: - Navigation

    @Test("Opening the browser lists the remote home directory")
    func startsInHome() async {
        let (model, fake) = Self.model(listings: [
            "/home/deploy": [Self.entry("notes.txt")]
        ])

        await model.start()

        #expect(model.path == "/home/deploy")
        #expect(model.pathDraft == "/home/deploy")
        #expect(model.entries.map(\.name) == ["notes.txt"])
        #expect(await fake.calls == ["pwd", "ls /home/deploy"])
    }

    @Test("Directories sort before files, whatever the sort field")
    func directoriesFirst() async {
        let (model, _) = Self.model(listings: [
            "/home/deploy": [
                Self.entry("zeta.txt", size: 1),
                Self.entry("alpha", kind: .directory, size: 4096),
                Self.entry("beta.txt", size: 900),
            ]
        ])

        await model.start()
        #expect(model.entries.map(\.name) == ["alpha", "beta.txt", "zeta.txt"])

        model.sortField = .size
        #expect(model.entries.map(\.name) == ["alpha", "zeta.txt", "beta.txt"])

        model.sortAscending = false
        #expect(model.entries.map(\.name) == ["alpha", "beta.txt", "zeta.txt"])
    }

    @Test("Dotfiles are hidden until asked for, without a second round trip")
    func hiddenFilter() async {
        let (model, fake) = Self.model(listings: [
            "/home/deploy": [Self.entry(".profile"), Self.entry("notes.txt")]
        ])

        await model.start()
        #expect(model.visibleEntries.map(\.name) == ["notes.txt"])

        model.showHidden = true
        #expect(model.visibleEntries.map(\.name) == [".profile", "notes.txt"])
        // The listing always asks for hidden entries, so toggling the view
        // needs no extra request beyond the refresh the toggle schedules.
        #expect(await fake.hiddenRequests.allSatisfy { $0 })
    }

    @Test("Up walks to the parent and stops at the root")
    func goUp() async {
        let (model, _) = Self.model(listings: [:], home: "/home/deploy")

        await model.start()
        #expect(model.canGoUp)

        await model.goUp()
        #expect(model.path == "/home")

        await model.goUp()
        #expect(model.path == "/")
        #expect(!model.canGoUp)

        await model.goUp()
        #expect(model.path == "/")
    }

    @Test("Opening a directory navigates; opening a file downloads it")
    func openEntries() async {
        let directory = Self.entry("logs", kind: .directory)
        let file = Self.entry("notes.txt")
        let (model, _) = Self.model(listings: [
            "/home/deploy": [directory, file],
            "/home/deploy/logs": [],
        ])
        var downloaded: [String] = []
        model.onDownload = { entry in downloaded.append(entry.path) }

        await model.start()
        await model.open(directory)
        #expect(model.path == "/home/deploy/logs")
        #expect(downloaded.isEmpty)

        await model.open(file)
        #expect(downloaded == ["/home/deploy/notes.txt"])
    }

    @Test("A symlink is tried as a directory and downloaded when it is not one")
    func openSymlink() async {
        let link = Self.entry("current", kind: .symlink)
        let (model, fake) = Self.model(listings: ["/home/deploy": [link]])
        var downloaded: [String] = []
        model.onDownload = { entry in downloaded.append(entry.path) }

        await model.start()
        await fake.setFailure(.failed("Can't ls: \"/home/deploy/current\" not found"))
        await model.open(link)

        #expect(model.path == "/home/deploy")
        #expect(downloaded == ["/home/deploy/current"])
        // The failed probe is not left on screen: it was not the user's
        // error, and the download is what happened instead.
        #expect(model.errorMessage == nil)
    }

    @Test("A failed listing surfaces the server's message and keeps the old view")
    func listingFailure() async {
        let (model, fake) = Self.model(listings: ["/home/deploy": [Self.entry("notes.txt")]])

        await model.start()
        await fake.setFailure(.failed("Can't ls: \"/root\" not found"))
        await model.navigate(to: "/root")

        #expect(model.path == "/home/deploy")
        #expect(model.errorMessage == "Can't ls: \"/root\" not found")
        #expect(model.entries.map(\.name) == ["notes.txt"])
    }

    // MARK: - Mutations

    @Test("New folders are created inside the directory on screen")
    func createFolder() async {
        let (model, fake) = Self.model(listings: ["/home/deploy": []])

        await model.start()
        await model.createFolder(named: "  releases  ")

        #expect(await fake.calls.contains("mkdir /home/deploy/releases"))
        // The listing is refreshed so the new folder appears.
        #expect(await fake.calls.last == "ls /home/deploy")
    }

    @Test("A name with a separator is refused before anything is sent")
    func invalidNames() async {
        let (model, fake) = Self.model(listings: ["/home/deploy": []])

        await model.start()
        await model.createFolder(named: "a/b")
        #expect(model.errorMessage != nil)

        await model.rename(Self.entry("notes.txt"), to: "..")
        #expect(model.errorMessage != nil)
        #expect(await !fake.calls.contains(where: { $0.hasPrefix("mkdir") }))
        #expect(await !fake.calls.contains(where: { $0.hasPrefix("rename") }))
    }

    @Test("Renaming keeps the entry in its own directory")
    func rename() async {
        let entry = Self.entry("notes.txt", in: "/home/deploy/logs")
        let (model, fake) = Self.model(listings: ["/home/deploy": []])

        await model.start()
        await model.rename(entry, to: "notes.old.txt")

        #expect(
            await fake.calls.contains(
                "rename /home/deploy/logs/notes.txt -> /home/deploy/logs/notes.old.txt"
            )
        )
    }

    @Test("Renaming to the same name does nothing")
    func renameNoop() async {
        let entry = Self.entry("notes.txt")
        let (model, fake) = Self.model(listings: ["/home/deploy": []])

        await model.start()
        await model.rename(entry, to: "notes.txt")

        #expect(await !fake.calls.contains(where: { $0.hasPrefix("rename") }))
    }

    @Test("Permissions must be octal digits")
    func changeMode() async {
        let entry = Self.entry("notes.txt")
        let (model, fake) = Self.model(listings: ["/home/deploy": []])

        await model.start()
        await model.changeMode(entry, to: "rwxr-xr-x")
        #expect(model.errorMessage != nil)
        #expect(await !fake.calls.contains(where: { $0.hasPrefix("chmod") }))

        await model.changeMode(entry, to: " 750 ")
        #expect(await fake.calls.contains("chmod 750 /home/deploy/notes.txt"))
        #expect(model.errorMessage == nil)

        #expect(!SSHFileBrowserModel.isValidOctalMode("8"))
        #expect(!SSHFileBrowserModel.isValidOctalMode("75555"))
        #expect(SSHFileBrowserModel.isValidOctalMode("0755"))
    }

    @Test("Deleting stops at the first failure so the user sees which item broke")
    func deleteStopsAtFailure() async {
        let first = Self.entry("a.txt")
        let second = Self.entry("b.txt")
        let (model, fake) = Self.model(listings: ["/home/deploy": [first, second]])

        await model.start()
        await fake.failDelete(path: first.path, message: "remote delete /home/deploy/a.txt: Permission denied")
        await model.delete([first, second])

        #expect(model.errorMessage == "remote delete /home/deploy/a.txt: Permission denied")
        #expect(await !fake.calls.contains("delete /home/deploy/b.txt"))
    }

    @Test("Deleting several entries deletes each of them, then refreshes")
    func deleteMany() async {
        let first = Self.entry("a.txt")
        let second = Self.entry("logs", kind: .directory)
        let (model, fake) = Self.model(listings: ["/home/deploy": [first, second]])

        await model.start()
        await model.delete([first, second])

        #expect(await fake.calls.contains("delete /home/deploy/a.txt"))
        #expect(await fake.calls.contains("delete /home/deploy/logs"))
        #expect(await fake.calls.last == "ls /home/deploy")
        #expect(model.errorMessage == nil)
    }

    // MARK: - Transfers

    @Test("Uploads target the directory on screen")
    func upload() async {
        let (model, _) = Self.model(listings: ["/home/deploy": []])
        var uploaded: ([String], String)?
        model.onUpload = { paths, directory in uploaded = (paths, directory) }

        await model.start()
        await model.navigate(to: "/srv/app")
        model.upload(localPaths: ["/tmp/a.txt"])

        #expect(uploaded?.0 == ["/tmp/a.txt"])
        #expect(uploaded?.1 == "/srv/app")
    }

    @Test("Downloading a selection hands every row to the transfer")
    func downloadSelection() async {
        let first = Self.entry("a.txt")
        let second = Self.entry("b.txt")
        let (model, _) = Self.model(listings: ["/home/deploy": [first, second]])
        var downloaded: [String] = []
        model.onDownload = { entry in downloaded.append(entry.name) }

        await model.start()
        model.selection = [first.id, second.id]
        model.download(model.selectedEntries)

        #expect(downloaded == ["a.txt", "b.txt"])
    }

    @Test("A files tab is never written to the session snapshot")
    func filesTabIsNotPersisted() {
        // Restoring one would re-authenticate to a remote host at launch,
        // before the user has asked for anything.
        let tab = Tab(
            title: "Files — Production",
            titleOverride: "Files — Production",
            content: .files(connectionID: UUID())
        )

        #expect(tab.snapshot() == nil)
        // A terminal tab in the same shape still persists, so the nil
        // above is about the content kind, not the missing surfaces.
        #expect(Tab(title: "Terminal").snapshot() != nil)
    }

    @Test("The window title names the profile")
    func windowTitle() {
        let (model, _) = Self.model()

        #expect(model.windowTitle == "Production — Files")
    }

    // MARK: - Fake

    /// Records every call as a readable string and can be told to fail.
    private actor FakeSFTP: SFTPOperations {
        private let home: String
        private var listings: [String: [SFTPEntry]]
        private var failure: SFTPError?
        private var failingDeletePath: String?
        private var failingDeleteMessage = ""
        var calls: [String] = []
        /// Whether each listing asked for hidden entries.
        var hiddenRequests: [Bool] = []

        init(home: String, listings: [String: [SFTPEntry]]) {
            self.home = home
            self.listings = listings
        }

        func setFailure(_ failure: SFTPError?) { self.failure = failure }

        func failDelete(path: String, message: String) {
            failingDeletePath = path
            failingDeleteMessage = message
        }

        func workingDirectory() async throws -> String {
            calls.append("pwd")
            if let failure { throw failure }
            return home
        }

        func list(path: String, includeHidden: Bool) async throws -> [SFTPEntry] {
            calls.append("ls \(path)")
            hiddenRequests.append(includeHidden)
            if let failure { throw failure }
            return listings[path] ?? []
        }

        func makeDirectory(path: String) async throws {
            calls.append("mkdir \(path)")
            if let failure { throw failure }
        }

        func rename(from: String, to destination: String) async throws {
            calls.append("rename \(from) -> \(destination)")
            if let failure { throw failure }
        }

        func delete(_ entry: SFTPEntry) async throws {
            calls.append("delete \(entry.path)")
            if entry.path == failingDeletePath {
                throw SFTPError.failed(failingDeleteMessage)
            }
            if let failure { throw failure }
        }

        func changeMode(octal: String, path: String) async throws {
            calls.append("chmod \(octal) \(path)")
            if let failure { throw failure }
        }
    }
}
