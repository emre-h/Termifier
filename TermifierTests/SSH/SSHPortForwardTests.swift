import Foundation
import Testing
@testable import Termifier

@Suite("SSH port forwarding rules")
struct SSHPortForwardTests {
    @Test("Local forwarding produces an -L spec")
    func localSpec() {
        let forward = SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80)

        #expect(forward.arguments == ["-L", "8080:localhost:80"])
        #expect(forward.localListenPort == 8080)
        #expect(forward.validationError == nil)
    }

    @Test("A bind address is prefixed to the listen side")
    func bindAddress() {
        let forward = SSHPortForward(
            kind: .local,
            bindAddress: "127.0.0.1",
            listenPort: 5432,
            targetHost: "db.internal",
            targetPort: 5432
        )

        #expect(forward.arguments == ["-L", "127.0.0.1:5432:db.internal:5432"])
    }

    @Test("Remote forwarding listens on the remote host, so it has no local port")
    func remoteForward() {
        let forward = SSHPortForward(kind: .remote, listenPort: 9000, targetHost: "localhost", targetPort: 3000)

        #expect(forward.arguments == ["-R", "9000:localhost:3000"])
        #expect(forward.localListenPort == nil)
    }

    @Test("Dynamic forwarding takes only a listen port")
    func dynamicForward() {
        let forward = SSHPortForward(kind: .dynamic, listenPort: 1080, targetHost: "", targetPort: 0)

        #expect(forward.arguments == ["-D", "1080"])
        #expect(forward.localListenPort == 1080)
        #expect(forward.validationError == nil)
    }

    @Test("IPv6 literals are bracketed so the spec's own colons stay unambiguous")
    func ipv6IsBracketed() {
        let forward = SSHPortForward(
            kind: .local,
            bindAddress: "::1",
            listenPort: 8080,
            targetHost: "fd00::5",
            targetPort: 80
        )

        #expect(forward.arguments == ["-L", "[::1]:8080:[fd00::5]:80"])
    }

    @Test("An already-bracketed address is not double-bracketed")
    func bracketedStaysBracketed() {
        let forward = SSHPortForward(kind: .dynamic, bindAddress: "[::1]", listenPort: 1080)

        #expect(forward.arguments == ["-D", "[::1]:1080"])
    }

    @Test("Out-of-range and incomplete rules report a reason")
    func validation() {
        #expect(SSHPortForward(kind: .local, listenPort: 0, targetPort: 80).validationError != nil)
        #expect(SSHPortForward(kind: .local, listenPort: 70000, targetPort: 80).validationError != nil)
        #expect(
            SSHPortForward(kind: .local, listenPort: 80, targetHost: "", targetPort: 80)
                .validationError != nil
        )
        #expect(
            SSHPortForward(kind: .local, listenPort: 80, targetHost: "db", targetPort: 0)
                .validationError != nil
        )
        #expect(
            SSHPortForward(kind: .local, bindAddress: "bad host", listenPort: 80, targetPort: 80)
                .validationError != nil
        )
        // A dynamic rule needs no target, so an empty target host is fine.
        #expect(
            SSHPortForward(kind: .dynamic, listenPort: 1080, targetHost: "", targetPort: 0)
                .validationError == nil
        )
    }

    @Test("Display text summarizes the rule for the sidebar")
    func displayText() {
        #expect(
            SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80)
                .displayText == "L 8080 → localhost:80"
        )
        #expect(SSHPortForward(kind: .dynamic, listenPort: 1080).displayText == "SOCKS 1080")
    }
}

@Suite("SSH port forwarding drafts")
struct SSHPortForwardDraftTests {
    @Test("A filled-in draft becomes a forward")
    func draftRoundTrip() {
        let forward = SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80)
        let draft = SSHPortForwardDraft(forward: forward)

        #expect(draft.forward == forward)
        #expect(draft.validationError == nil)
    }

    @Test("Non-numeric ports are reported instead of silently dropped")
    func nonNumericPorts() {
        var draft = SSHPortForwardDraft(kind: .local, listenPort: "eighty", targetPort: "80")
        #expect(draft.forward == nil)
        #expect(draft.validationError != nil)

        draft = SSHPortForwardDraft(kind: .local, listenPort: "8080", targetPort: "")
        #expect(draft.forward == nil)
        #expect(draft.validationError != nil)
    }

    @Test("A dynamic draft needs no target port")
    func dynamicDraft() {
        let draft = SSHPortForwardDraft(kind: .dynamic, listenPort: "1080", targetPort: "")

        #expect(draft.forward?.arguments == ["-D", "1080"])
        #expect(draft.validationError == nil)
    }

    @Test("The first invalid row decides whether the editor can save")
    func collectionValidation() {
        let drafts = [
            SSHPortForwardDraft(kind: .local, listenPort: "8080", targetPort: "80"),
            SSHPortForwardDraft(kind: .local, listenPort: "9090", targetPort: "nope"),
        ]

        #expect(drafts.firstValidationError != nil)
        #expect([drafts[0]].firstValidationError == nil)
        #expect([drafts[0]].forwards.count == 1)
    }
}
