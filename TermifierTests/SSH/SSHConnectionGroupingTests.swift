import Foundation
import Testing
@testable import Termifier

@Suite("SSH sidebar grouping")
struct SSHConnectionGroupingTests {
    private func connection(_ name: String, folder: String = "") -> SSHConnection {
        SSHConnection(name: name, host: "\(name).example.com", folder: folder)
    }

    @Test("Ungrouped profiles come first, then folders sorted case-insensitively")
    func ordering() {
        let groups = SSHConnectionGrouping.groups(for: [
            connection("beta", folder: "prod"),
            connection("alpha"),
            connection("gamma", folder: "Dev"),
            connection("delta", folder: "prod"),
        ])

        #expect(groups.map(\.folder) == ["", "Dev", "prod"])
        #expect(groups[0].connections.map(\.name) == ["alpha"])
        // Saved order is preserved inside a folder.
        #expect(groups[2].connections.map(\.name) == ["beta", "delta"])
    }

    @Test("The ungrouped section is omitted when every profile has a folder")
    func noUngroupedSection() {
        let groups = SSHConnectionGrouping.groups(for: [connection("alpha", folder: "prod")])

        #expect(groups.map(\.folder) == ["prod"])
        #expect(groups[0].title == "prod")
    }

    @Test("A whitespace-only folder is treated as ungrouped")
    func whitespaceFolder() {
        let groups = SSHConnectionGrouping.groups(for: [connection("alpha", folder: "   ")])

        #expect(groups.count == 1)
        #expect(groups[0].isUngrouped)
        #expect(groups[0].title == "Ungrouped")
    }

    @Test("An empty list produces no groups")
    func empty() {
        #expect(SSHConnectionGrouping.groups(for: []).isEmpty)
    }
}
