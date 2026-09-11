//
//  SSHConfigHostParser.swift
//  Termifier
//
//  Reads the FIELDS of every concrete `Host` block in an ssh_config text
//  (hostname, user, port, identity file, ProxyJump, forwardings) so saved
//  SSH profiles can be imported from `~/.ssh/config` instead of retyped.
//
//  Relationship to `SSHConfigParser` (Features/Sessions): that one is a
//  deliberately minimal, separately specified contract -- it extracts
//  nothing but the ordered list of Host ALIASES for the remote-session
//  picker, keeps duplicates, and is documented and tested as such. This
//  parser answers a different question (what are this host's settings?),
//  so it is a separate type rather than a widening of that contract.
//
//  Pure string -> values; no file access (the caller supplies the text)
//  and therefore no actor isolation.
//
//  DELIBERATE LIMITS, all of which degrade into "import less", never into
//  a wrong profile:
//  - `Include` is not resolved; included files are simply not seen.
//  - `Match` blocks are skipped whole: their conditions cannot be
//    evaluated without a connection attempt.
//  - Only a literal `Host *` block is applied as a default to every
//    alias. Other glob patterns (`*.corp`, `web?`) are not matched
//    against aliases.
//  - Within a block the FIRST value of a keyword wins, mirroring ssh's
//    own "first obtained value" rule; forwardings accumulate instead.
//

import Foundation

struct SSHConfigHost: Equatable, Sendable {
    var alias: String
    var hostName: String?
    var user: String?
    var port: Int?
    var identityFile: String?
    var proxyJump: [String]
    var forwards: [SSHPortForward]

    init(
        alias: String,
        hostName: String? = nil,
        user: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil,
        proxyJump: [String] = [],
        forwards: [SSHPortForward] = []
    ) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.proxyJump = proxyJump
        self.forwards = forwards
    }

    /// What to actually connect to: `HostName` when the block sets one,
    /// otherwise the alias itself (which is what ssh does).
    var effectiveHost: String { hostName ?? alias }
}

enum SSHConfigHostParser {

    static func hosts(from configText: String) -> [SSHConfigHost] {
        let blocks = parseBlocks(configText)
        let globalBlocks = blocks.filter { $0.patterns.contains("*") }

        var order: [String] = []
        var directivesByAlias: [String: [Directive]] = [:]
        for block in blocks {
            for pattern in block.patterns where isConcreteAlias(pattern) {
                if directivesByAlias[pattern] == nil {
                    order.append(pattern)
                    directivesByAlias[pattern] = []
                }
                directivesByAlias[pattern]?.append(contentsOf: block.directives)
            }
        }

        return order.map { alias in
            // Own directives first, `Host *` defaults appended: with
            // first-value-wins below, that makes the global block a
            // fallback, exactly as ssh resolves it for a config where the
            // catch-all comes last. A block that lists BOTH the alias and
            // `*` (`Host prod *`) is already counted as the alias's own,
            // so it is excluded here -- otherwise its forwardings, which
            // accumulate rather than first-win, would be added twice.
            let globals = globalBlocks
                .filter { !$0.patterns.contains(alias) }
                .flatMap(\.directives)
            return build(alias: alias, directives: (directivesByAlias[alias] ?? []) + globals)
        }
    }

    // MARK: - Blocks

    private struct Directive {
        let keyword: String
        let value: String
    }

    private struct Block {
        var patterns: [String]
        var directives: [Directive]
    }

    private static func parseBlocks(_ configText: String) -> [Block] {
        var blocks: [Block] = []
        var current: Block?
        // A Match block's directives are dropped wholesale: its condition
        // (`exec`, `final`, `canonical`, …) cannot be evaluated here, so
        // applying its contents could produce a profile that connects
        // somewhere the user's ssh never would.
        var inMatchBlock = false

        for rawLine in configText.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let (keyword, value) = directive(from: String(rawLine)) else { continue }

            if keyword.caseInsensitiveCompare("Host") == .orderedSame {
                if let current { blocks.append(current) }
                inMatchBlock = false
                current = Block(patterns: patterns(from: value), directives: [])
                continue
            }
            if keyword.caseInsensitiveCompare("Match") == .orderedSame {
                if let current { blocks.append(current) }
                current = nil
                inMatchBlock = true
                continue
            }
            guard !inMatchBlock else { continue }
            current?.directives.append(Directive(keyword: keyword, value: value))
        }
        if let current { blocks.append(current) }
        return blocks
    }

    /// Splits one config line into keyword and value, honoring both
    /// separators ssh accepts (`Key value` and `Key=value`) and stripping
    /// a quoted value's quotes. Returns `nil` for comments, blank lines
    /// and keyword-only lines.
    private static func directive(from rawLine: String) -> (keyword: String, value: String)? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        let separators: Set<Character> = [" ", "\t", "="]
        guard let splitIndex = line.firstIndex(where: { separators.contains($0) }) else { return nil }
        let keyword = String(line[line.startIndex..<splitIndex])
        var value = line[line.index(after: splitIndex)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t="))
        guard !keyword.isEmpty, !value.isEmpty else { return nil }

        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        return (keyword, value)
    }

    private static func patterns(from value: String) -> [String] {
        value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// A pattern that names exactly one host, so it can become a profile.
    private static func isConcreteAlias(_ pattern: String) -> Bool {
        !pattern.contains("*") && !pattern.contains("?") && !pattern.hasPrefix("!")
    }

    // MARK: - Field extraction

    private static func build(alias: String, directives: [Directive]) -> SSHConfigHost {
        var host = SSHConfigHost(alias: alias)
        var seen = Set<String>()

        for directive in directives {
            let keyword = directive.keyword.lowercased()
            let isForwarding = keyword == "localforward"
                || keyword == "remoteforward"
                || keyword == "dynamicforward"
            // First value wins for scalars; forwardings accumulate
            // because ssh opens every one of them.
            if !isForwarding {
                guard !seen.contains(keyword) else { continue }
                seen.insert(keyword)
            }

            switch keyword {
            case "hostname":
                host.hostName = directive.value
            case "user":
                host.user = directive.value
            case "port":
                host.port = Int(directive.value)
            case "identityfile":
                host.identityFile = directive.value
            case "proxyjump":
                host.proxyJump = proxyJumpHops(from: directive.value)
            case "localforward":
                if let forward = forward(kind: .local, value: directive.value) {
                    host.forwards.append(forward)
                }
            case "remoteforward":
                if let forward = forward(kind: .remote, value: directive.value) {
                    host.forwards.append(forward)
                }
            case "dynamicforward":
                if let forward = forward(kind: .dynamic, value: directive.value) {
                    host.forwards.append(forward)
                }
            default:
                continue
            }
        }
        return host
    }

    /// `ProxyJump` hops, or an empty list for the literal `none`
    /// (ssh's way of cancelling an inherited ProxyJump).
    private static func proxyJumpHops(from value: String) -> [String] {
        guard value.caseInsensitiveCompare("none") != .orderedSame else { return [] }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parses a forwarding value in either spelling ssh accepts:
    /// `8080 localhost:80` (space separated) or `8080:localhost:80`
    /// (colon separated), each optionally prefixed with a bind address.
    /// Returns `nil` for a shape this importer cannot represent -- Unix
    /// socket forwardings, `RemoteForward` without a target -- rather
    /// than guessing.
    private static func forward(kind: SSHPortForwardKind, value: String) -> SSHPortForward? {
        let fields = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = fields.first else { return nil }

        if kind == .dynamic {
            guard let listen = hostPort(from: first), fields.count == 1 else { return nil }
            return SSHPortForward(
                kind: .dynamic,
                bindAddress: listen.host ?? "",
                listenPort: listen.port,
                targetHost: "",
                targetPort: 0
            )
        }

        let listenField: String
        let targetField: String
        switch fields.count {
        case 1:
            // Colon-separated single token: [bind:]port:host:hostport.
            guard let split = splitColonSpec(first) else { return nil }
            listenField = split.listen
            targetField = split.target
        case 2:
            listenField = fields[0]
            targetField = fields[1]
        default:
            return nil
        }

        guard let listen = hostPort(from: listenField),
              let target = hostPort(from: targetField),
              let targetHost = target.host else { return nil }

        return SSHPortForward(
            kind: kind,
            bindAddress: listen.host ?? "",
            listenPort: listen.port,
            targetHost: targetHost,
            targetPort: target.port
        )
    }

    /// Splits `[bind:]port:host:hostport` into its listen and target
    /// halves by taking the LAST two colon-separated fields as the
    /// target, which keeps a bracketed IPv6 literal on either side
    /// intact.
    private static func splitColonSpec(_ spec: String) -> (listen: String, target: String)? {
        let fields = splitOutsideBrackets(spec)
        guard fields.count >= 3 else { return nil }
        let target = fields.suffix(2).joined(separator: ":")
        let listen = fields.dropLast(2).joined(separator: ":")
        return (listen, target)
    }

    /// Splits on `:` except inside `[...]`, so `[::1]:80` yields
    /// `["[::1]", "80"]` rather than one field per IPv6 group.
    private static func splitOutsideBrackets(_ value: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            switch character {
            case "[":
                depth += 1
                current.append(character)
            case "]":
                depth -= 1
                current.append(character)
            case ":" where depth == 0:
                fields.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    /// Parses `port`, `host:port` or `[::1]:port`. The host is `nil` when
    /// the field is a bare port.
    private static func hostPort(from field: String) -> (host: String?, port: Int)? {
        let fields = splitOutsideBrackets(field)
        guard let portField = fields.last, let port = Int(portField),
              SSHPortForward.isValidPort(port) else { return nil }
        guard fields.count > 1 else { return (nil, port) }
        var host = fields.dropLast().joined(separator: ":")
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        return (host.isEmpty ? nil : host, port)
    }
}
