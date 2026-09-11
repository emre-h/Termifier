//
//  SSHPortForwardDraft.swift
//  Termifier
//
//  The editable, all-strings form of one `SSHPortForward` row in the
//  profile editor. Ports live as text while the user types (a half-typed
//  port is not an `Int`), and become a validated `SSHPortForward` only on
//  save -- so the saved model never holds a value the command builder
//  would have to defend against.
//

import Foundation

struct SSHPortForwardDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: SSHPortForwardKind
    var bindAddress: String
    var listenPort: String
    var targetHost: String
    var targetPort: String

    init(
        id: UUID = UUID(),
        kind: SSHPortForwardKind = .local,
        bindAddress: String = "",
        listenPort: String = "",
        targetHost: String = "localhost",
        targetPort: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.bindAddress = bindAddress
        self.listenPort = listenPort
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    init(forward: SSHPortForward) {
        id = forward.id
        kind = forward.kind
        bindAddress = forward.bindAddress
        listenPort = String(forward.listenPort)
        targetHost = forward.kind.usesTarget ? forward.targetHost : "localhost"
        targetPort = forward.kind.usesTarget ? String(forward.targetPort) : ""
    }

    /// The forward this draft describes, or `nil` when a port field is
    /// not a number -- `validationError` explains which one.
    var forward: SSHPortForward? {
        guard let listen = Int(listenPort.trimmingCharacters(in: .whitespaces)) else { return nil }
        let target = Int(targetPort.trimmingCharacters(in: .whitespaces))
        if kind.usesTarget, target == nil { return nil }
        return SSHPortForward(
            id: id,
            kind: kind,
            bindAddress: bindAddress.trimmingCharacters(in: .whitespaces),
            listenPort: listen,
            targetHost: kind.usesTarget ? targetHost.trimmingCharacters(in: .whitespaces) : "",
            targetPort: target ?? 0
        )
    }

    /// `nil` when the row can be saved. Number-shaped problems are
    /// reported here; everything else defers to `SSHPortForward`'s own
    /// validation so both paths state the same rules.
    var validationError: String? {
        guard let forward else {
            return kind.usesTarget
                ? "Forwarding ports must be numbers."
                : "The SOCKS port must be a number."
        }
        return forward.validationError
    }
}

extension Array where Element == SSHPortForwardDraft {
    /// First validation failure across the rows, or `nil` when every row
    /// is usable.
    var firstValidationError: String? {
        compactMap(\.validationError).first
    }

    /// The forwards to save. Only reached once `firstValidationError` is
    /// `nil`, so a dropped row would be a bug, not silent data loss.
    var forwards: [SSHPortForward] {
        compactMap(\.forward)
    }
}
