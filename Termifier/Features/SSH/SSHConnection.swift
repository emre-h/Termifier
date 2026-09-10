import Foundation

enum SSHAuthenticationMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case password
    case identityFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: "Password"
        case .identityFile: "Identity File"
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

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        username: String = "",
        port: Int = 22,
        authentication: SSHAuthenticationMethod = .identityFile,
        identityFile: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.port = port
        self.authentication = authentication
        self.identityFile = identityFile
    }

    var destination: String {
        username.isEmpty ? host : "\(username)@\(host)"
    }
}
