import Foundation
import Testing
@testable import Termifier

@Suite("SFTP listing parser")
struct SFTPListingParserTests {
    /// Captured verbatim from `sftp -b -` against the OpenSSH server
    /// shipped with macOS: batch mode echoes the command, names come back
    /// as full paths when `ls` is given one, and the link-count field is
    /// `?` on a server that does not report it.
    private let realOutput = """
    sftp> ls -lan "/tmp/sftptest"
    drwxr-xr-x    ? 501      20             160 Sep 11 00:47 /tmp/sftptest/.
    drwxrwxrwt    ? 0        0             3648 Sep 11 00:47 /tmp/sftptest/..
    drwxr-xr-x    ? 501      20              64 Sep 11 00:47 /tmp/sftptest/a dir
    -rw-r--r--    2 501      20               6 Sep 11 00:47 /tmp/sftptest/file with space.txt
    lrwxr-xr-x    ? 501      20              19 Sep 11 00:47 /tmp/sftptest/link.txt
    -rw-r--r--    ? 501      20               0 Sep 11 00:48 /tmp/sftptest/.hidden
    """

    @Test("Parses a real listing, skipping the command echo and the . / .. rows")
    func parsesRealListing() throws {
        let entries = SFTPListingParser.entries(from: realOutput, directory: "/tmp/sftptest")

        #expect(entries.map(\.name) == ["a dir", "file with space.txt", "link.txt", ".hidden"])
        let directory = try #require(entries.first)
        #expect(directory.kind == .directory)
        #expect(directory.path == "/tmp/sftptest/a dir")
        #expect(directory.permissions == "rwxr-xr-x")
        #expect(directory.owner == "501")
        #expect(directory.group == "20")
        #expect(directory.modifiedDescription == "Sep 11 00:47")
    }

    @Test("A name containing spaces survives, and a symlink keeps its kind")
    func namesAndKinds() throws {
        let entries = SFTPListingParser.entries(from: realOutput, directory: "/tmp/sftptest")

        let file = try #require(entries.first { $0.name == "file with space.txt" })
        #expect(file.kind == .file)
        #expect(file.size == 6)

        let link = try #require(entries.first { $0.name == "link.txt" })
        #expect(link.kind == .symlink)

        let hidden = try #require(entries.first { $0.name == ".hidden" })
        #expect(hidden.isHidden)
    }

    @Test("A bare-name listing is resolved against the directory it came from")
    func bareNames() throws {
        // `ls` with no path argument answers with bare names.
        let output = "sftp> ls -ln\n-rw-r--r--    1 501      20            12 Sep 11 00:47 notes.txt\n"

        let entries = SFTPListingParser.entries(from: output, directory: "/srv/app")

        #expect(entries.count == 1)
        #expect(entries[0].path == "/srv/app/notes.txt")
    }

    @Test("Lines that are not listing rows are skipped, not guessed at")
    func skipsNoise() {
        let output = """
        sftp> ls -ln "/srv"
        Connected to example.com.
        Can't ls: "/nope" not found
        -rw-r--r--    1 501      20            12 Sep 11 00:47 /srv/notes.txt
        """

        let entries = SFTPListingParser.entries(from: output, directory: "/srv")

        #expect(entries.map(\.name) == ["notes.txt"])
    }

    @Test("pwd's answer is the browser's starting directory")
    func workingDirectory() {
        let output = "sftp> pwd\nRemote working directory: /home/deploy\n"

        #expect(SFTPListingParser.workingDirectory(from: output) == "/home/deploy")
        #expect(SFTPListingParser.workingDirectory(from: "sftp> pwd\n") == nil)
    }

    @Test("A failure reports sftp's own message, never an empty alert")
    func failureMessage() {
        #expect(
            SFTPListingParser.failureMessage(
                stderr: "remote mkdir \"/nope/x\": No such file or directory\n",
                stdout: "sftp> mkdir \"/nope/x\"\n"
            ) == "remote mkdir \"/nope/x\": No such file or directory"
        )
        // Only the command echo available: fall through to a generic line
        // rather than reporting the echo as the error.
        #expect(
            SFTPListingParser.failureMessage(stderr: "", stdout: "sftp> rm \"/x\"\n")
                == "The SFTP command failed."
        )
    }
}

@Suite("SFTP entry")
struct SFTPEntryTests {
    private func entry(permissions: String, kind: SFTPEntryKind = .file) -> SFTPEntry {
        SFTPEntry(
            name: "a",
            path: "/srv/a",
            kind: kind,
            size: 10,
            permissions: permissions,
            owner: "501",
            group: "20",
            modifiedDescription: "Sep 11 00:47"
        )
    }

    @Test("Permission strings convert to the octal mode chmod takes")
    func octalMode() {
        #expect(entry(permissions: "rwxr-xr-x").octalMode == "755")
        #expect(entry(permissions: "rw-r--r--").octalMode == "644")
        #expect(entry(permissions: "rwx------").octalMode == "700")
        #expect(entry(permissions: "---------").octalMode == "000")
    }

    @Test("A permission field with sticky/setuid or ACL bits has no plain octal form")
    func unconvertiblePermissions() {
        #expect(entry(permissions: "rwxrwxrwt").octalMode == nil)
        #expect(entry(permissions: "rwxr-xr-x+").octalMode == nil)
        #expect(entry(permissions: "rwx").octalMode == nil)
    }

    @Test("Directories show no size")
    func sizeDescription() {
        #expect(entry(permissions: "rwxr-xr-x", kind: .directory).sizeDescription == "--")
        #expect(entry(permissions: "rw-r--r--").sizeDescription.contains("10"))
    }
}
