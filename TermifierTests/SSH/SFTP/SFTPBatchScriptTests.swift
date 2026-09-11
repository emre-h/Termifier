import Foundation
import Testing
@testable import Termifier

@Suite("SFTP batch scripts")
struct SFTPBatchScriptTests {
    @Test("Paths are double-quoted, with backslash and quote escaped")
    func quoting() {
        #expect(SFTPBatchScript.quote("/srv/app") == "\"/srv/app\"")
        #expect(SFTPBatchScript.quote("/srv/my app.txt") == "\"/srv/my app.txt\"")
        #expect(SFTPBatchScript.quote("/srv/quo\"te") == "\"/srv/quo\\\"te\"")
        #expect(SFTPBatchScript.quote("/srv/back\\slash") == "\"/srv/back\\\\slash\"")
    }

    @Test("Glob characters are NOT escaped inside quotes")
    func globCharactersAreLeftAlone() {
        // Verified against the OpenSSH client: a quoted path is not
        // globbed, and an escaped `\*` inside quotes reaches the server
        // with the backslash attached, so the path is simply not found.
        #expect(SFTPBatchScript.quote("/srv/glob[1]*") == "\"/srv/glob[1]*\"")
    }

    @Test("Hidden entries are requested with ls -lan, the default view with ls -ln")
    func listFlags() {
        #expect(
            SFTPBatchScript.list(path: "/srv", includeHidden: false) == "ls -ln \"/srv\""
        )
        #expect(
            SFTPBatchScript.list(path: "/srv", includeHidden: true) == "ls -lan \"/srv\""
        )
    }

    @Test("Mutations quote their paths and leave the mode bare")
    func mutations() {
        #expect(SFTPBatchScript.makeDirectory(path: "/srv/new dir") == "mkdir \"/srv/new dir\"")
        #expect(
            SFTPBatchScript.rename(from: "/srv/a", to: "/srv/b") == "rename \"/srv/a\" \"/srv/b\""
        )
        #expect(SFTPBatchScript.removeFile(path: "/srv/a") == "rm \"/srv/a\"")
        #expect(SFTPBatchScript.removeDirectory(path: "/srv/a") == "rmdir \"/srv/a\"")
        #expect(
            SFTPBatchScript.changeMode(octal: "755", path: "/srv/a") == "chmod 755 \"/srv/a\""
        )
    }

    @Test("A recursive delete removes children before their parents")
    func recursiveDeletionOrder() {
        // Discovery order: parents first, as a breadth-first walk yields.
        let targets = [
            SFTPDeletionTarget(path: "/srv/app", isDirectory: true),
            SFTPDeletionTarget(path: "/srv/app/a.txt", isDirectory: false),
            SFTPDeletionTarget(path: "/srv/app/sub", isDirectory: true),
            SFTPDeletionTarget(path: "/srv/app/sub/b.txt", isDirectory: false),
        ]

        let script = SFTPBatchScript.recursiveDeletion(of: targets)

        #expect(script == [
            "rm \"/srv/app/a.txt\"",
            "rm \"/srv/app/sub/b.txt\"",
            "rmdir \"/srv/app/sub\"",
            "rmdir \"/srv/app\"",
        ])
    }

    @Test("Commands become newline-separated stdin text")
    func script() {
        #expect(SFTPBatchScript.script(["pwd", "ls -ln \"/\""]) == "pwd\nls -ln \"/\"\n")
    }
}
