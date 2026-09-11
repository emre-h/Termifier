//
//  SSHTunnelMonitor.swift
//  Termifier
//
//  Liveness for a profile's port forwardings, shown as a dot next to the
//  SSH sidebar row.
//
//  HOW IT KNOWS: the forwardings live inside the interactive `ssh`
//  process of a terminal tab, which the app does not own and cannot
//  query. What it CAN observe is the effect: while the session is up,
//  something is listening on each `-L`/`-D` port of this Mac, and when
//  the session dies those sockets close. So the monitor probes the
//  loopback ports directly -- an honest end-to-end signal rather than a
//  guess derived from tab bookkeeping, and it stays correct when the
//  session is torn down from inside the terminal.
//
//  `-R` forwardings listen on the REMOTE host, so they are reported as
//  "not observable from here" instead of being called down.
//

import Foundation
import Network
import Observation

enum SSHTunnelStatus: Equatable, Sendable {
    /// The profile has no forwardings.
    case none
    /// Every locally-listening port is bound.
    case up
    /// Some, but not all, locally-listening ports are bound.
    case partial
    /// No locally-listening port is bound.
    case down
    /// Only `-R` rules: nothing to probe on this machine.
    case remoteOnly

    var summary: String {
        switch self {
        case .none: "No port forwarding"
        case .up: "Port forwarding active"
        case .partial: "Some forwarded ports are not listening"
        case .down: "Forwarded ports are not listening"
        case .remoteOnly: "Remote forwarding — status not observable locally"
        }
    }
}

@MainActor
@Observable
final class SSHTunnelMonitor {
    static let shared = SSHTunnelMonitor()

    /// Loopback ports observed bound during the last refresh.
    private(set) var listeningPorts: Set<Int> = []

    private let probe: @Sendable (Int) async -> Bool

    init(probe: @escaping @Sendable (Int) async -> Bool = SSHTunnelMonitor.probeLoopbackPort) {
        self.probe = probe
    }

    /// Probes every locally-listening port of `connections` concurrently
    /// and republishes the result in one assignment, so observers never
    /// see a half-updated set flicker rows.
    func refresh(connections: [SSHConnection]) async {
        let ports = Set(connections.flatMap(\.localListenPorts))
        guard !ports.isEmpty else {
            listeningPorts = []
            return
        }

        let probe = self.probe
        let bound = await withTaskGroup(of: (Int, Bool).self) { group in
            for port in ports {
                group.addTask { (port, await probe(port)) }
            }
            var result: Set<Int> = []
            for await (port, isListening) in group where isListening {
                result.insert(port)
            }
            return result
        }
        listeningPorts = bound
    }

    func status(for connection: SSHConnection) -> SSHTunnelStatus {
        guard !connection.forwards.isEmpty else { return .none }
        let localPorts = connection.localListenPorts
        guard !localPorts.isEmpty else { return .remoteOnly }

        let boundCount = localPorts.filter(listeningPorts.contains).count
        if boundCount == 0 { return .down }
        return boundCount == localPorts.count ? .up : .partial
    }

    // MARK: - Probe

    /// Timeout for one probe. A loopback port either answers or refuses
    /// immediately; anything slower is treated as not listening so a
    /// refresh cycle can never stall the sidebar.
    nonisolated private static let probeTimeout: TimeInterval = 0.35

    /// True when something accepts a TCP connection on `127.0.0.1:port`.
    static let probeLoopbackPort: @Sendable (Int) async -> Bool = { port in
        guard let value = UInt16(exactly: port),
              let endpointPort = NWEndpoint.Port(rawValue: value) else { return false }

        let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)
        return await withCheckedContinuation { continuation in
            let gate = SingleUseGate()
            let finish: @Sendable (Bool) -> Void = { isListening in
                guard gate.claim() else { return }
                connection.cancel()
                continuation.resume(returning: isListening)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                // A closed loopback port answers with ECONNREFUSED, which
                // Network reports as `.waiting`, not `.failed`.
                case .waiting, .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + probeTimeout) { finish(false) }
        }
    }
}

/// Lets exactly one of several racing callbacks (ready / failed /
/// timeout) resume a checked continuation; resuming twice would trap.
private final class SingleUseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isClaimed { return false }
        isClaimed = true
        return true
    }
}
