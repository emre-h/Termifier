//
//  SSHPortForward.swift
//  Termifier
//
//  One port-forwarding rule attached to a saved SSH profile. Pure value
//  type plus pure argument/validation helpers -- everything here is
//  driven from unit tests without spawning ssh, exactly like
//  `SSHCommandBuilder`, whose output these arguments become part of.
//

import Foundation

/// The three forwarding directions OpenSSH supports on the command line.
/// Raw values are persisted inside `SSHConnection`, so they must stay
/// stable across releases.
enum SSHPortForwardKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// `-L`: this Mac listens, traffic exits from the remote host.
    case local
    /// `-R`: the remote host listens, traffic exits from this Mac.
    case remote
    /// `-D`: this Mac listens as a SOCKS proxy.
    case dynamic

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .local: "-L"
        case .remote: "-R"
        case .dynamic: "-D"
        }
    }

    var title: String {
        switch self {
        case .local: "Local (-L)"
        case .remote: "Remote (-R)"
        case .dynamic: "SOCKS (-D)"
        }
    }

    /// `-D` takes only a listen port; the other two also need a target
    /// `host:port` pair. Drives both argument construction and which
    /// fields the editor shows.
    var usesTarget: Bool { self != .dynamic }

    /// Whether the LISTENING socket ends up on this Mac. `-R` listens on
    /// the remote host, so its liveness cannot be probed locally -- see
    /// `SSHTunnelMonitor`.
    var listensLocally: Bool { self != .remote }
}

struct SSHPortForward: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: SSHPortForwardKind
    /// Optional `bind_address` part of the spec. Empty means "let ssh
    /// decide", which is loopback-only for `-L`/`-D` and follows
    /// `GatewayPorts` for `-R`.
    var bindAddress: String
    var listenPort: Int
    /// Ignored for `.dynamic`.
    var targetHost: String
    /// Ignored for `.dynamic`.
    var targetPort: Int

    init(
        id: UUID = UUID(),
        kind: SSHPortForwardKind = .local,
        bindAddress: String = "",
        listenPort: Int,
        targetHost: String = "localhost",
        targetPort: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.bindAddress = bindAddress
        self.listenPort = listenPort
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    /// The `ssh` arguments for this rule, e.g. `["-L", "8080:localhost:80"]`.
    /// Colons are the spec's own separators, so an IPv6 literal in either
    /// the bind address or the target host is wrapped in brackets -- the
    /// form ssh_config(5) documents for exactly this ambiguity.
    var arguments: [String] {
        var spec = ""
        if !bindAddress.isEmpty {
            spec += Self.bracketedIfIPv6(bindAddress) + ":"
        }
        spec += String(listenPort)
        if kind.usesTarget {
            spec += ":" + Self.bracketedIfIPv6(targetHost) + ":" + String(targetPort)
        }
        return [kind.flag, spec]
    }

    /// Short human-readable summary for the sidebar and the editor list.
    var displayText: String {
        let listen = bindAddress.isEmpty ? String(listenPort) : "\(bindAddress):\(listenPort)"
        switch kind {
        case .local: return "L \(listen) → \(targetHost):\(targetPort)"
        case .remote: return "R \(listen) → \(targetHost):\(targetPort)"
        case .dynamic: return "SOCKS \(listen)"
        }
    }

    /// The port this Mac ends up listening on, or `nil` for `-R` (whose
    /// listener lives on the remote host).
    var localListenPort: Int? {
        kind.listensLocally ? listenPort : nil
    }

    /// `nil` when the rule is usable, otherwise a message the editor can
    /// show verbatim. Validation happens before the rule is saved so a
    /// malformed spec never reaches the command line, where ssh would
    /// reject the whole session rather than the single bad rule.
    var validationError: String? {
        guard Self.isValidPort(listenPort) else {
            return "Listen port must be between 1 and 65535."
        }
        if !bindAddress.isEmpty, Self.containsSeparatorOrSpace(bindAddress) {
            return "Bind address must not contain spaces or commas."
        }
        guard kind.usesTarget else { return nil }
        let host = targetHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return "Target host is required." }
        guard !Self.containsSeparatorOrSpace(host) else {
            return "Target host must not contain spaces or commas."
        }
        guard Self.isValidPort(targetPort) else {
            return "Target port must be between 1 and 65535."
        }
        return nil
    }

    static func isValidPort(_ port: Int) -> Bool { (1...65535).contains(port) }

    private static func containsSeparatorOrSpace(_ value: String) -> Bool {
        value.contains(where: { $0.isWhitespace }) || value.contains(",")
    }

    /// Wraps a bare IPv6 literal in brackets. A value that is already
    /// bracketed, or that is a hostname/IPv4 address (no colon), is
    /// returned unchanged.
    private static func bracketedIfIPv6(_ value: String) -> String {
        guard value.contains(":"), !value.hasPrefix("[") else { return value }
        return "[\(value)]"
    }
}
