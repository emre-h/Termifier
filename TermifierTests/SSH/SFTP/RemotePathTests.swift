import Foundation
import Testing
@testable import Termifier

@Suite("Remote path arithmetic")
struct RemotePathTests {
    @Test("Joining never doubles the separator at the root")
    func join() {
        #expect(RemotePath.join("/", "etc") == "/etc")
        #expect(RemotePath.join("/srv", "app") == "/srv/app")
        #expect(RemotePath.join("/srv/", "app") == "/srv/app")
        #expect(RemotePath.join("", "etc") == "/etc")
        // A name with a space is a name, not two components.
        #expect(RemotePath.join("/srv", "my app") == "/srv/my app")
    }

    @Test("The parent of a root-level path is the root, and the root's own parent is itself")
    func parent() {
        #expect(RemotePath.parent(of: "/srv/app/config") == "/srv/app")
        #expect(RemotePath.parent(of: "/srv") == "/")
        #expect(RemotePath.parent(of: "/") == "/")
        #expect(RemotePath.parent(of: "/srv/app/") == "/srv")
    }

    @Test("Last component ignores a trailing separator")
    func lastComponent() {
        #expect(RemotePath.lastComponent(of: "/srv/app") == "app")
        #expect(RemotePath.lastComponent(of: "/srv/app/") == "app")
        #expect(RemotePath.lastComponent(of: "/srv/my app.txt") == "my app.txt")
        #expect(RemotePath.lastComponent(of: "/") == "")
        #expect(RemotePath.lastComponent(of: "app") == "app")
    }

    @Test("Normalizing collapses repeats and drops a trailing separator")
    func normalize() {
        #expect(RemotePath.normalize("/srv//app/") == "/srv/app")
        #expect(RemotePath.normalize("  /srv/app  ") == "/srv/app")
        #expect(RemotePath.normalize("/") == "/")
        #expect(RemotePath.normalize("") == "/")
        // A relative path stays relative.
        #expect(RemotePath.normalize("srv//app") == "srv/app")
    }

    @Test("Only the root is the root")
    func isRoot() {
        #expect(RemotePath.isRoot("/"))
        #expect(!RemotePath.isRoot("/srv"))
        #expect(!RemotePath.isRoot("/srv/"))
    }
}
