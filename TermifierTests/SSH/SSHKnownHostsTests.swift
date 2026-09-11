import Foundation
import Testing
@testable import Termifier

@Suite("SSH known hosts")
struct SSHKnownHostsTests {
    @Test("A non-default port uses the bracketed known_hosts spelling")
    func hostSpec() {
        #expect(SSHKnownHostsCommandBuilder.hostSpec(host: "example.com", port: 22) == "example.com")
        #expect(
            SSHKnownHostsCommandBuilder.hostSpec(host: "example.com", port: 2222)
                == "[example.com]:2222"
        )
        // An IPv6 literal is already bracketed; it must not be doubled.
        #expect(SSHKnownHostsCommandBuilder.hostSpec(host: "[fd00::5]", port: 2222) == "[fd00::5]:2222")
    }

    @Test("Lookup and removal use ssh-keygen's -F and -R")
    func arguments() {
        #expect(
            SSHKnownHostsCommandBuilder.findArguments(host: "example.com", port: 22)
                == ["-F", "example.com"]
        )
        #expect(
            SSHKnownHostsCommandBuilder.removeArguments(host: "example.com", port: 2222)
                == ["-R", "[example.com]:2222"]
        )
    }

    @Test("Key types are read from the entry lines, not the comment header")
    func parseKeyTypes() {
        let output = """
        # Host example.com found: line 3
        example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA
        example.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB
        """

        #expect(
            SSHKnownHostsCommandBuilder.parseKeyTypes(from: output) == ["ssh-ed25519", "ssh-rsa"]
        )
        #expect(SSHKnownHostsCommandBuilder.parseKeyTypes(from: "").isEmpty)
    }

    @Test("Exit 0 with entries means the key is recorded")
    func recorded() async {
        let service = SSHKnownHostsService(run: { _ in
            (status: 0, output: "# Host example.com found: line 3\nexample.com ssh-ed25519 AAAA\n")
        })

        #expect(await service.status(host: "example.com", port: 22) == .recorded(keyTypes: ["ssh-ed25519"]))
    }

    @Test("Exit 1 means no key is recorded yet")
    func notRecorded() async {
        let service = SSHKnownHostsService(run: { _ in (status: 1, output: "") })

        #expect(await service.status(host: "example.com", port: 22) == .notRecorded)
    }

    @Test("A failure to run ssh-keygen is reported as unknown, never as 'no key'")
    func unavailable() async {
        // Reporting "no key" here would invite the user to forget a key
        // that may well exist.
        let missing = SSHKnownHostsService(run: { _ in nil })
        #expect(await missing.status(host: "example.com", port: 22) == .unavailable)

        let crashed = SSHKnownHostsService(run: { _ in (status: 255, output: "") })
        #expect(await crashed.status(host: "example.com", port: 22) == .unavailable)

        // Exit 0 whose output this parser cannot read is also unknown.
        let unparsable = SSHKnownHostsService(run: { _ in (status: 0, output: "# Host found\n") })
        #expect(await unparsable.status(host: "example.com", port: 22) == .unavailable)
    }

    @Test("Forgetting a key passes -R for the connection's host and port")
    func forget() async {
        let recorded = Recorder()
        let service = SSHKnownHostsService(run: { arguments in
            await recorded.record(arguments)
            return (status: 0, output: "")
        })
        let connection = SSHConnection(name: "Prod", host: "example.com", port: 2222)

        let removed = await service.forget(for: connection)

        #expect(removed)
        #expect(await recorded.arguments == [["-R", "[example.com]:2222"]])
    }

    @Test("A non-zero ssh-keygen exit reports the removal as failed")
    func forgetFailure() async {
        let service = SSHKnownHostsService(run: { _ in (status: 1, output: "") })

        #expect(await service.forget(host: "example.com", port: 22) == false)
    }

    private actor Recorder {
        var arguments: [[String]] = []
        func record(_ value: [String]) { arguments.append(value) }
    }
}
