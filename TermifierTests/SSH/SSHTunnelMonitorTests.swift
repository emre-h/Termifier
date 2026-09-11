import Foundation
import Testing
@testable import Termifier

@MainActor
@Suite("SSH tunnel monitor")
struct SSHTunnelMonitorTests {
    private func connection(_ forwards: [SSHPortForward]) -> SSHConnection {
        SSHConnection(name: "Tunnelled", host: "example.com", forwards: forwards)
    }

    @Test("A profile without forwardings has no status to show")
    func noForwards() async {
        let monitor = SSHTunnelMonitor(probe: { _ in true })

        #expect(monitor.status(for: connection([])) == SSHTunnelStatus.none)
    }

    @Test("Every listening local port means the tunnels are up")
    func allUp() async {
        let monitor = SSHTunnelMonitor(probe: { _ in true })
        let profile = connection([
            SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80),
            SSHPortForward(kind: .dynamic, listenPort: 1080),
        ])

        await monitor.refresh(connections: [profile])

        #expect(monitor.listeningPorts == [8080, 1080])
        #expect(monitor.status(for: profile) == .up)
    }

    @Test("Some ports bound is reported as partial, none as down")
    func partialAndDown() async {
        let monitor = SSHTunnelMonitor(probe: { port in port == 8080 })
        let profile = connection([
            SSHPortForward(kind: .local, listenPort: 8080, targetHost: "localhost", targetPort: 80),
            SSHPortForward(kind: .local, listenPort: 9090, targetHost: "localhost", targetPort: 90),
        ])

        await monitor.refresh(connections: [profile])
        #expect(monitor.status(for: profile) == .partial)

        let dead = SSHTunnelMonitor(probe: { _ in false })
        await dead.refresh(connections: [profile])
        #expect(dead.status(for: profile) == .down)
    }

    @Test("Remote-only forwardings are reported as not observable from here")
    func remoteOnly() async {
        // -R listens on the remote host, so a local probe would always
        // say "down" -- which would be a lie, not a measurement.
        let monitor = SSHTunnelMonitor(probe: { _ in false })
        let profile = connection([
            SSHPortForward(kind: .remote, listenPort: 9000, targetHost: "localhost", targetPort: 3000)
        ])

        await monitor.refresh(connections: [profile])

        #expect(monitor.listeningPorts.isEmpty)
        #expect(monitor.status(for: profile) == .remoteOnly)
    }

    @Test("Refreshing with nothing to probe clears the previous result")
    func clearsWhenNothingToProbe() async {
        let monitor = SSHTunnelMonitor(probe: { _ in true })
        let profile = connection([SSHPortForward(kind: .dynamic, listenPort: 1080)])

        await monitor.refresh(connections: [profile])
        #expect(!monitor.listeningPorts.isEmpty)

        await monitor.refresh(connections: [])
        #expect(monitor.listeningPorts.isEmpty)
    }

    @Test("Each distinct port is probed once, however many profiles share it")
    func probesEachPortOnce() async {
        let counter = Counter()
        let monitor = SSHTunnelMonitor(probe: { port in
            await counter.increment(port)
            return true
        })
        let forward = SSHPortForward(kind: .dynamic, listenPort: 1080)

        await monitor.refresh(connections: [connection([forward]), connection([forward])])

        #expect(await counter.counts == [1080: 1])
    }

    private actor Counter {
        var counts: [Int: Int] = [:]
        func increment(_ port: Int) { counts[port, default: 0] += 1 }
    }
}
