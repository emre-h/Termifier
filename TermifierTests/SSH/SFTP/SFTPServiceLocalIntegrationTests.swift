import Foundation
import Testing
@testable import Termifier

/// End-to-end exercise of the SFTP layer against the REAL OpenSSH client
/// and server, with no network and no server setup: `sftp -D
/// /usr/libexec/sftp-server` runs the server as a local subprocess.
///
/// This is what pins the parts that cannot be verified by reasoning about
/// the format alone -- sftp's quoting rules, the exact listing shape, and
/// which failures produce a non-zero exit status -- so the browser's
/// behavior against a real server is not taken on trust. Skipped when
/// either binary is missing.
@Suite("SFTP service against a local sftp-server")
struct SFTPServiceLocalIntegrationTests {
    static let clientPath = "/usr/bin/sftp"
    static let serverPath = "/usr/libexec/sftp-server"

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: clientPath)
            && FileManager.default.fileExists(atPath: serverPath)
    }

    private func service() -> SFTPService {
        SFTPService(arguments: { [Self.clientPath, "-b", "-", "-D", Self.serverPath] })
    }

    /// A throwaway directory holding one of everything the browser has to
    /// render, including the names most likely to break quoting.
    private final class Fixture {
        let root: String

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("sftp-" + UUID().uuidString)
                .path
            try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                atPath: root + "/a dir", withIntermediateDirectories: true
            )
            try "hello\n".write(toFile: root + "/file with space.txt", atomically: true, encoding: .utf8)
            try "x".write(toFile: root + "/.hidden", atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(
                atPath: root + "/link.txt", withDestinationPath: "file with space.txt"
            )
        }

        func cleanup() {
            try? FileManager.default.removeItem(atPath: root)
        }
    }

    @Test("A real listing parses into entries, with hidden files only when asked", .enabled(if: SFTPServiceLocalIntegrationTests.isAvailable))
    func listsRealDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let visible = try await service().list(path: fixture.root, includeHidden: false)
        #expect(visible.map(\.name).sorted() == ["a dir", "file with space.txt", "link.txt"])

        let all = try await service().list(path: fixture.root, includeHidden: true)
        #expect(all.contains { $0.name == ".hidden" })
        // `.` and `..` are never rows.
        #expect(!all.contains { $0.name == "." || $0.name == ".." })

        let directory = try #require(visible.first { $0.name == "a dir" })
        #expect(directory.kind == .directory)
        #expect(directory.path == fixture.root + "/a dir")

        let file = try #require(visible.first { $0.name == "file with space.txt" })
        #expect(file.kind == .file)
        #expect(file.size == 6)
        #expect(file.octalMode != nil)

        #expect(visible.first { $0.name == "link.txt" }?.kind == .symlink)
    }

    @Test("pwd answers with an absolute path", .enabled(if: SFTPServiceLocalIntegrationTests.isAvailable))
    func workingDirectory() async throws {
        let path = try await service().workingDirectory()

        #expect(path.hasPrefix("/"))
    }

    @Test("mkdir, rename and chmod reach the real server", .enabled(if: SFTPServiceLocalIntegrationTests.isAvailable))
    func mutations() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = service()

        try await service.makeDirectory(path: fixture.root + "/new dir")
        try await service.rename(
            from: fixture.root + "/new dir",
            to: fixture.root + "/renamed dir"
        )
        try await service.changeMode(octal: "700", path: fixture.root + "/renamed dir")

        let entries = try await service.list(path: fixture.root, includeHidden: false)
        let renamed = try #require(entries.first { $0.name == "renamed dir" })
        #expect(renamed.kind == .directory)
        #expect(renamed.permissions == "rwx------")
        #expect(!entries.contains { $0.name == "new dir" })
    }

    @Test("Names with quotes, backslashes and glob characters survive quoting", .enabled(if: SFTPServiceLocalIntegrationTests.isAvailable))
    func awkwardNames() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = service()
        // Each of these breaks a different naive quoting scheme.
        let names = ["glob[1]*", "quo\"te", "back\\slash", "trailing space "]

        for name in names {
            try await service.makeDirectory(path: fixture.root + "/" + name)
        }

        let entries = try await service.list(path: fixture.root, includeHidden: false)
        for name in names {
            #expect(entries.contains { $0.name == name }, "missing \(name)")
        }

        // And they can be operated on afterwards, not merely created.
        try await service.changeMode(octal: "700", path: fixture.root + "/glob[1]*")
        let updated = try await service.list(path: fixture.root, includeHidden: false)
        #expect(updated.first { $0.name == "glob[1]*" }?.permissions == "rwx------")
    }

    @Test("Deleting a file removes it; deleting a directory takes its contents with it", .enabled(if: SFTPServiceLocalIntegrationTests.isAvailable))
    func deletion() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = service()
        // A non-empty tree: `rmdir` alone fails on this with nothing more
        // useful than "Failure", which is why the service walks it.
        try FileManager.default.createDirectory(
            atPath: fixture.root + "/tree/inner", withIntermediateDirectories: true
        )
        try "x".write(toFile: fixture.root + "/tree/a.txt", atomically: true, encoding: .utf8)
        try "y".write(toFile: fixture.root + "/tree/inner/b.txt", atomically: true, encoding: .utf8)
        try "z".write(toFile: fixture.root + "/tree/inner/.dotfile", atomically: true, encoding: .utf8)

        let entries = try await service.list(path: fixture.root, includeHidden: false)
        let file = try #require(entries.first { $0.name == "file with space.txt" })
        let tree = try #require(entries.first { $0.name == "tree" })

        try await service.delete(file)
        try await service.delete(tree)

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root + "/tree"))
        // The rest of the fixture is untouched.
        #expect(FileManager.default.fileExists(atPath: fixture.root + "/a dir"))
    }

    @Test("Deleting a symlink removes the link, never its target", .enabled(if: SFTPServiceLocalIntegrationTests.isAvailable))
    func deletingSymlinkKeepsTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = service()
        let entries = try await service.list(path: fixture.root, includeHidden: false)
        let link = try #require(entries.first { $0.name == "link.txt" })

        try await service.delete(link)

        #expect(!FileManager.default.fileExists(atPath: fixture.root + "/link.txt"))
        #expect(FileManager.default.fileExists(atPath: fixture.root + "/file with space.txt"))
    }

    @Test("A refused command throws with the server's own message", .enabled(if: SFTPServiceLocalIntegrationTests.isAvailable))
    func failureMessage() async throws {
        let service = service()

        await #expect(throws: SFTPError.self) {
            try await service.makeDirectory(path: "/nonexistent-parent-xyz/child")
        }

        do {
            try await service.makeDirectory(path: "/nonexistent-parent-xyz/child")
            Issue.record("expected a failure")
        } catch let error as SFTPError {
            guard case .failed(let message) = error else {
                Issue.record("expected .failed, got \(error)")
                return
            }
            #expect(message.contains("mkdir"))
            #expect(!message.hasPrefix("sftp>"))
        }
    }

    @Test("Listing a path that does not exist is a failure, not an empty directory", .enabled(if: SFTPServiceLocalIntegrationTests.isAvailable))
    func listingMissingPath() async throws {
        // An empty listing would read as "this folder is empty" in the UI,
        // which is a different claim from "this folder is not there".
        await #expect(throws: SFTPError.self) {
            _ = try await service().list(path: "/nonexistent-parent-xyz", includeHidden: false)
        }
    }
}
