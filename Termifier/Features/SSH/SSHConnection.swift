import Foundation

enum SSHAuthenticationMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case password
    case identityFile
    /// Let ssh pick the credential itself: agent keys, `IdentityFile`
    /// entries from `~/.ssh/config`, and the default `~/.ssh/id_*` keys.
    /// This is what hosts imported from `~/.ssh/config` use when the
    /// config does not name a key file, and the only method that adds no
    /// authentication options to the command line at all.
    case agent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: "Password"
        case .identityFile: "Identity File"
        case .agent: "Agent"
        }
    }
}

struct SSHConnection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var host: String
    var username: String
    var port: Int
    var authentication: SSHAuthenticationMethod
    var identityFile: String?
    /// Sidebar group. Empty means "ungrouped", which sorts above the
    /// named folders.
    var folder: String
    /// `ProxyJump` chain, outermost bastion first. Each entry is a plain
    /// ssh destination (`user@host`, optionally `:port`).
    var jumpHosts: [String]
    /// `-L` / `-R` / `-D` rules opened alongside the interactive session.
    var forwards: [SSHPortForward]
    /// Runs on the remote host right after login; the session then hands
    /// over to the login shell instead of exiting (see
    /// `SSHCommandBuilder.remoteCommandToken(for:)`).
    var startupCommand: String
    /// Default remote directory for drag-and-drop uploads and downloads.
    /// Empty means the remote home directory.
    var remoteDirectory: String

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        username: String = "",
        port: Int = 22,
        authentication: SSHAuthenticationMethod = .identityFile,
        identityFile: String? = nil,
        folder: String = "",
        jumpHosts: [String] = [],
        forwards: [SSHPortForward] = [],
        startupCommand: String = "",
        remoteDirectory: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.port = port
        self.authentication = authentication
        self.identityFile = identityFile
        self.folder = folder
        self.jumpHosts = jumpHosts
        self.forwards = forwards
        self.startupCommand = startupCommand
        self.remoteDirectory = remoteDirectory
    }

    // Decoding is hand-written ONLY so that profiles saved before
    // folders/jump hosts/forwarding existed keep decoding. The store
    // decodes the whole array with `try?` and falls back to an EMPTY
    // list, so a single missing key in the synthesized decoder would
    // silently wipe every saved profile rather than fail loudly.
    private enum CodingKeys: String, CodingKey {
        case id, name, host, username, port, authentication, identityFile
        case folder, jumpHosts, forwards, startupCommand, remoteDirectory
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        authentication = try container.decodeIfPresent(
            SSHAuthenticationMethod.self, forKey: .authentication
        ) ?? .agent
        identityFile = try container.decodeIfPresent(String.self, forKey: .identityFile)
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        jumpHosts = try container.decodeIfPresent([String].self, forKey: .jumpHosts) ?? []
        forwards = try container.decodeIfPresent([SSHPortForward].self, forKey: .forwards) ?? []
        startupCommand = try container.decodeIfPresent(String.self, forKey: .startupCommand) ?? ""
        remoteDirectory = try container.decodeIfPresent(String.self, forKey: .remoteDirectory) ?? ""
    }

    var destination: String {
        username.isEmpty ? host : "\(username)@\(host)"
    }

    /// Ports this Mac listens on while the session is up -- the set
    /// `SSHTunnelMonitor` probes. `-R` rules contribute nothing here
    /// because their listener lives on the remote host.
    var localListenPorts: [Int] {
        forwards.compactMap(\.localListenPort)
    }
}
