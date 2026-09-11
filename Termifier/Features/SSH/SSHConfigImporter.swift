//
//  SSHConfigImporter.swift
//  Termifier
//
//  Turns parsed `~/.ssh/config` hosts into proposed `SSHConnection`
//  profiles for the import sheet, and says which ones are already saved
//  so a second import does not duplicate the sidebar.
//
//  Import never carries a secret: a config host becomes either an
//  identity-file profile (when the block names a key) or an agent
//  profile, never a password profile -- there is no password to put in
//  the Keychain, and `SSHConnectionStore.add` rejects a password profile
//  without one.
//

import Foundation

/// One importable host, paired with the profile it would create.
struct SSHConfigImportCandidate: Identifiable, Equatable, Sendable {
    var id: String { host.alias }
    let host: SSHConfigHost
    let connection: SSHConnection
    /// A profile with the same name, or the same user/host/port triple,
    /// already exists.
    let isAlreadySaved: Bool
}

enum SSHConfigImporter {

    /// Builds the profile a config host would become. `folder` groups the
    /// whole import under one sidebar section.
    static func connection(from host: SSHConfigHost, folder: String) -> SSHConnection {
        let identityFile = host.identityFile?.trimmingCharacters(in: .whitespaces)
        let hasIdentityFile = !(identityFile ?? "").isEmpty

        return SSHConnection(
            name: host.alias,
            host: host.effectiveHost,
            username: host.user ?? "",
            port: host.port ?? 22,
            authentication: hasIdentityFile ? .identityFile : .agent,
            identityFile: hasIdentityFile ? identityFile : nil,
            folder: folder,
            jumpHosts: host.proxyJump,
            forwards: host.forwards.filter { $0.validationError == nil }
        )
    }

    static func candidates(
        from configText: String,
        existing: [SSHConnection],
        folder: String
    ) -> [SSHConfigImportCandidate] {
        SSHConfigHostParser.hosts(from: configText).map { host in
            let connection = connection(from: host, folder: folder)
            return SSHConfigImportCandidate(
                host: host,
                connection: connection,
                isAlreadySaved: isAlreadySaved(connection, in: existing)
            )
        }
    }

    /// Duplicate detection. Either the profile NAME collides (the config
    /// alias is what the sidebar shows, so two rows with one name are
    /// indistinguishable) or the same endpoint is already reachable --
    /// same user, host and port. Host comparison is case-insensitive
    /// because DNS is.
    static func isAlreadySaved(_ connection: SSHConnection, in existing: [SSHConnection]) -> Bool {
        existing.contains { saved in
            if saved.name.caseInsensitiveCompare(connection.name) == .orderedSame { return true }
            return saved.host.caseInsensitiveCompare(connection.host) == .orderedSame
                && saved.port == connection.port
                && saved.username == connection.username
        }
    }
}

/// Reads the user's `~/.ssh/config`, deriving HOME the same way every
/// other session-related consumer does (`SessionRootResolverProtocol`,
/// never a direct `NSHomeDirectory()`), with an injectable loader so
/// tests never touch a real home directory.
struct SSHConfigFileReader: Sendable {
    private let rootResolver: any SessionRootResolverProtocol
    private let loadConfig: @Sendable (String) -> String?

    init(
        rootResolver: any SessionRootResolverProtocol = SessionRootResolver(),
        loadConfig: @escaping @Sendable (String) -> String? = { path in
            try? String(contentsOfFile: path, encoding: .utf8)
        }
    ) {
        self.rootResolver = rootResolver
        self.loadConfig = loadConfig
    }

    var path: String { rootResolver.resolve() + "/.ssh/config" }

    /// The config text, or `nil` when there is no readable config.
    func read() -> String? { loadConfig(path) }
}
