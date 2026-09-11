import Foundation
import Testing
@testable import Termifier

@Suite("ssh_config host parsing")
struct SSHConfigHostParserTests {
    @Test("Reads a host block's fields in declaration order")
    func basicFields() {
        let config = """
        Host prod
            HostName prod.example.com
            User deploy
            Port 2222
            IdentityFile ~/.ssh/prod_ed25519

        Host staging
            HostName staging.example.com
        """

        let hosts = SSHConfigHostParser.hosts(from: config)

        #expect(hosts.map(\.alias) == ["prod", "staging"])
        #expect(hosts[0].hostName == "prod.example.com")
        #expect(hosts[0].user == "deploy")
        #expect(hosts[0].port == 2222)
        #expect(hosts[0].identityFile == "~/.ssh/prod_ed25519")
        // A block without HostName connects to the alias itself.
        #expect(hosts[1].effectiveHost == "staging.example.com")
        #expect(hosts[1].port == nil)
    }

    @Test("A host without HostName resolves to its own alias")
    func aliasIsTheHost() {
        let hosts = SSHConfigHostParser.hosts(from: "Host box\n  User root\n")

        #expect(hosts[0].effectiveHost == "box")
        #expect(hosts[0].user == "root")
    }

    @Test("Key=value and quoted values are both accepted")
    func separatorsAndQuotes() {
        let config = """
        Host prod
            HostName=prod.example.com
            IdentityFile "~/.ssh/my key"
        """

        let hosts = SSHConfigHostParser.hosts(from: config)

        #expect(hosts[0].hostName == "prod.example.com")
        #expect(hosts[0].identityFile == "~/.ssh/my key")
    }

    @Test("Wildcard and negated patterns never become importable hosts")
    func wildcardsExcluded() {
        let config = """
        Host *
            User defaultuser
        Host *.corp !secret
            User corpuser
        Host prod
            HostName prod.example.com
        """

        let hosts = SSHConfigHostParser.hosts(from: config)

        #expect(hosts.map(\.alias) == ["prod"])
        // `Host *` still applies as a default.
        #expect(hosts[0].user == "defaultuser")
    }

    @Test("A host's own value wins over the Host * default")
    func ownValueWins() {
        let config = """
        Host prod
            User deploy
        Host *
            User defaultuser
            Port 2200
        """

        let hosts = SSHConfigHostParser.hosts(from: config)

        #expect(hosts[0].user == "deploy")
        #expect(hosts[0].port == 2200)
    }

    @Test("The first value of a repeated keyword wins, as in ssh")
    func firstValueWins() {
        let hosts = SSHConfigHostParser.hosts(from: "Host prod\n User first\n User second\n")

        #expect(hosts[0].user == "first")
    }

    @Test("Repeated aliases merge into one host")
    func repeatedAliasesMerge() {
        let config = """
        Host prod
            HostName prod.example.com
        Host prod
            User deploy
        """

        let hosts = SSHConfigHostParser.hosts(from: config)

        #expect(hosts.count == 1)
        #expect(hosts[0].hostName == "prod.example.com")
        #expect(hosts[0].user == "deploy")
    }

    @Test("Match blocks are skipped because their conditions cannot be evaluated")
    func matchBlocksSkipped() {
        let config = """
        Host prod
            HostName prod.example.com
        Match host nothing exec "false"
            User wrong
            ProxyJump wrong-bastion
        Host staging
            HostName staging.example.com
        """

        let hosts = SSHConfigHostParser.hosts(from: config)

        #expect(hosts.map(\.alias) == ["prod", "staging"])
        #expect(hosts[0].user == nil)
        #expect(hosts.allSatisfy { $0.proxyJump.isEmpty })
    }

    @Test("ProxyJump becomes an ordered hop list; none clears it")
    func proxyJump() {
        let config = """
        Host inner
            ProxyJump bastion.example.com, user@middle:2222
        Host direct
            ProxyJump none
        """

        let hosts = SSHConfigHostParser.hosts(from: config)

        #expect(hosts[0].proxyJump == ["bastion.example.com", "user@middle:2222"])
        #expect(hosts[1].proxyJump.isEmpty)
    }

    @Test("Forwardings are read in both spellings ssh accepts")
    func forwardings() {
        let config = """
        Host tunnels
            LocalForward 8080 localhost:80
            LocalForward 127.0.0.1:5432 db.internal:5432
            RemoteForward 9000:localhost:3000
            DynamicForward 1080
        """

        let hosts = SSHConfigHostParser.hosts(from: config)
        let forwards = hosts[0].forwards

        #expect(forwards.count == 4)
        #expect(forwards[0].arguments == ["-L", "8080:localhost:80"])
        #expect(forwards[1].arguments == ["-L", "127.0.0.1:5432:db.internal:5432"])
        #expect(forwards[2].arguments == ["-R", "9000:localhost:3000"])
        #expect(forwards[3].arguments == ["-D", "1080"])
    }

    @Test("Bracketed IPv6 forwardings keep their address intact")
    func ipv6Forwarding() {
        let hosts = SSHConfigHostParser.hosts(
            from: "Host v6\n LocalForward [::1]:8080 [fd00::5]:80\n"
        )

        #expect(hosts[0].forwards.first?.arguments == ["-L", "[::1]:8080:[fd00::5]:80"])
    }

    @Test("Forwarding shapes this importer cannot represent are dropped, not guessed")
    func unsupportedForwardings() {
        let config = """
        Host sockets
            RemoteForward /var/run/remote.sock /var/run/local.sock
            LocalForward 8080
            DynamicForward 1080 extra
        """

        #expect(SSHConfigHostParser.hosts(from: config)[0].forwards.isEmpty)
    }

    @Test("Comments, blank lines and Include arguments contribute nothing")
    func noiseIgnored() {
        let config = """
        # a comment
        Include ~/.ssh/config.d/*

        Host prod
            # another comment
            HostName prod.example.com
        """

        let hosts = SSHConfigHostParser.hosts(from: config)

        #expect(hosts.map(\.alias) == ["prod"])
        #expect(hosts[0].hostName == "prod.example.com")
    }

    @Test("Keywords are case-insensitive")
    func caseInsensitiveKeywords() {
        let hosts = SSHConfigHostParser.hosts(from: "HOST prod\n hostname prod.example.com\n PORT 2222\n")

        #expect(hosts[0].hostName == "prod.example.com")
        #expect(hosts[0].port == 2222)
    }

    @Test("A block naming both an alias and * is applied to that alias only once")
    func aliasAndWildcardInOneBlock() {
        // `Host prod *` is the alias's own block AND the catch-all; its
        // forwardings accumulate, so counting it twice would open the
        // same tunnel twice.
        let config = """
        Host prod *
            LocalForward 8080 localhost:80
        Host staging
            HostName staging.example.com
        """

        let hosts = SSHConfigHostParser.hosts(from: config)

        #expect(hosts.map(\.alias) == ["prod", "staging"])
        #expect(hosts[0].forwards.count == 1)
        // The catch-all still reaches the other host.
        #expect(hosts[1].forwards.count == 1)
    }

    @Test("An empty config yields no hosts")
    func emptyConfig() {
        #expect(SSHConfigHostParser.hosts(from: "").isEmpty)
    }
}
