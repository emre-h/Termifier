// IPCIdentityHeaderParityTests.swift
// TermifierTests
//
// Ties TermifierMCPServer.resolveSurfaceID's two-header contract together
// across every agent CLI so a manager cannot silently drop one of the
// two headers without a test failing here.
// Every config manager that writes a termifier-ipc MCP entry must emit
// both X-Termifier-Surface-ID and X-Termifier-Session-ID, because
// TermifierMCPServer.resolveSurfaceID needs the session header to
// identify a pane inside a persistent termifier-session. A per-manager
// test file pins its own manager's exact output and has no reason to
// compare itself against the other four, so a manager dropping one
// header is only caught here.
//
// Coverage: drives enableIPC on every config manager that owns a
// termifier-ipc MCP entry -- ClaudeConfigManager, CodexConfigManager,
// GrokConfigManager, OpenCodeConfigManager, HermesConfigManager, the
// same five IPCConfigManager.enableIPC calls -- into its own scratch
// config path, then asserts the emitted config carries both
// X-Termifier-Surface-ID and X-Termifier-Session-ID. Claude and OpenCode write
// JSON and are asserted by parsing the headers dictionary; Codex and
// Grok write TOML and Hermes writes YAML, none of which this codebase
// parses with a real library, so those three are asserted the same way
// their own per-manager test files already do: a substring check for
// each header's exact literal line. A failing assertion names both the
// manager and the specific header it is missing, and a passing run
// proves the header survived that manager's own escaping/placeholder
// syntax (Claude/Grok's `${VAR:-}`, Codex's env_http_headers name
// mapping, OpenCode's `{env:VAR}`, Hermes's quoted YAML scalar) rather
// than merely proving the literal string was written somewhere in the
// file.
//
// PiExtensionManager is deliberately not covered here. It has no
// enableIPC(port:token:configPath:) of this shape: install() writes a
// fixed TypeScript file that resolves its own pane identity at pi's
// runtime via `TERMIFIER_SESSION_ID || TERMIFIER_SURFACE_ID` and sends whichever
// one wins in a single X-Termifier-Surface-ID header -- there is no second
// header for a "carries both" assertion to find, by design, since the
// choice between the two identities is made in pi's own process rather
// than by Termifier at config-write time. That fallback expression is
// already pinned by PiExtensionManagerTests's own
// test_scriptBody_guardsOnPaneIdentityAndHerdrBeforeRegisteringAnything,
// so pi's identity resolution has coverage; it is just not the
// two-header coverage this file exists to give the other five.
//
// Adding a sixth agent CLI whose config manager writes a termifier-ipc MCP
// entry (i.e. a sixth axis in IPCConfigManager.enableIPC) must add a
// matching test method here, in the same way this file's five methods
// already mirror IPCConfigManager.enableIPC's five calls.

import XCTest
@testable import Termifier

final class IPCIdentityHeaderParityTests: XCTestCase {

    // MARK: - Properties

    private var rootDir: String!
    private var claudeConfigPath: String!
    private var codexConfigPath: String!
    private var grokConfigPath: String!
    private var openCodeConfigDir: String!
    private var hermesConfigPath: String!

    private let port = 41830
    private let token = "abc123"

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path

        let claudeDir = rootDir + "/claude"
        let codexDir = rootDir + "/codex"
        let grokDir = rootDir + "/grok"
        let hermesDir = rootDir + "/hermes"
        openCodeConfigDir = rootDir + "/opencode"

        let scratchDirs: [String] = [claudeDir, codexDir, grokDir, hermesDir, openCodeConfigDir]
        for dir in scratchDirs {
            try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        claudeConfigPath = claudeDir + "/claude.json"
        codexConfigPath = codexDir + "/config.toml"
        grokConfigPath = grokDir + "/config.toml"
        hermesConfigPath = hermesDir + "/config.yaml"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: rootDir)
        rootDir = nil
        super.tearDown()
    }

    // MARK: - ClaudeConfigManager (JSON)

    func test_claudeConfigManager_enableIPC_emitsBothIdentityHeaders() throws {
        try ClaudeConfigManager.enableIPC(port: port, token: token, configPath: claudeConfigPath)

        let data = try Data(contentsOf: URL(fileURLWithPath: claudeConfigPath))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mcpServers = parsed?["mcpServers"] as? [String: Any]
        let termifierIPC = mcpServers?["termifier-ipc"] as? [String: Any]
        let headers = termifierIPC?["headers"] as? [String: String]

        XCTAssertEqual(headers?["X-Termifier-Surface-ID"], "${TERMIFIER_SURFACE_ID:-}",
                       "ClaudeConfigManager: termifier-ipc headers are missing X-Termifier-Surface-ID")
        XCTAssertEqual(headers?["X-Termifier-Session-ID"], "${TERMIFIER_SESSION_ID:-}",
                       "ClaudeConfigManager: termifier-ipc headers are missing X-Termifier-Session-ID -- " +
                       "without it, TermifierMCPServer.resolveSurfaceID cannot identify a pane inside a " +
                       "persistent termifier-session")
    }

    // MARK: - CodexConfigManager (TOML)

    func test_codexConfigManager_enableIPC_emitsBothIdentityHeaders() throws {
        try CodexConfigManager.enableIPC(port: port, token: token, configPath: codexConfigPath)

        let content = try String(contentsOfFile: codexConfigPath, encoding: .utf8)

        XCTAssertTrue(content.contains(#""X-Termifier-Surface-ID" = "TERMIFIER_SURFACE_ID""#),
                      "CodexConfigManager: env_http_headers is missing the X-Termifier-Surface-ID mapping")
        XCTAssertTrue(content.contains(#""X-Termifier-Session-ID" = "TERMIFIER_SESSION_ID""#),
                      "CodexConfigManager: env_http_headers is missing the X-Termifier-Session-ID mapping -- " +
                      "without it, TermifierMCPServer.resolveSurfaceID cannot identify a pane inside a " +
                      "persistent termifier-session")
    }

    // MARK: - GrokConfigManager (TOML)

    func test_grokConfigManager_enableIPC_emitsBothIdentityHeaders() throws {
        try GrokConfigManager.enableIPC(port: port, token: token, configPath: grokConfigPath)

        let content = try String(contentsOfFile: grokConfigPath, encoding: .utf8)

        XCTAssertTrue(content.contains("X-Termifier-Surface-ID = \"${TERMIFIER_SURFACE_ID:-}\""),
                      "GrokConfigManager: [mcp_servers.termifier-ipc.headers] is missing X-Termifier-Surface-ID")
        XCTAssertTrue(content.contains("X-Termifier-Session-ID = \"${TERMIFIER_SESSION_ID:-}\""),
                      "GrokConfigManager: [mcp_servers.termifier-ipc.headers] is missing X-Termifier-Session-ID " +
                      "-- without it, TermifierMCPServer.resolveSurfaceID cannot identify a pane inside a " +
                      "persistent termifier-session")
    }

    // MARK: - OpenCodeConfigManager (JSON)

    func test_openCodeConfigManager_enableIPC_emitsBothIdentityHeaders() throws {
        try OpenCodeConfigManager.enableIPC(port: port, token: token, configDir: openCodeConfigDir)

        let jsonPath = openCodeConfigDir + "/opencode.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mcp = parsed?["mcp"] as? [String: Any]
        let termifierIPC = mcp?["termifier-ipc"] as? [String: Any]
        let headers = termifierIPC?["headers"] as? [String: String]

        XCTAssertEqual(headers?["X-Termifier-Surface-ID"], "{env:TERMIFIER_SURFACE_ID}",
                       "OpenCodeConfigManager: termifier-ipc headers are missing X-Termifier-Surface-ID")
        XCTAssertEqual(headers?["X-Termifier-Session-ID"], "{env:TERMIFIER_SESSION_ID}",
                       "OpenCodeConfigManager: termifier-ipc headers are missing X-Termifier-Session-ID -- " +
                       "without it, TermifierMCPServer.resolveSurfaceID cannot identify a pane inside a " +
                       "persistent termifier-session")
    }

    // MARK: - HermesConfigManager (YAML)

    func test_hermesConfigManager_enableIPC_emitsBothIdentityHeaders() throws {
        try HermesConfigManager.enableIPC(port: port, token: token, configPath: hermesConfigPath)

        let content = try String(contentsOfFile: hermesConfigPath, encoding: .utf8)

        XCTAssertTrue(content.contains("X-Termifier-Surface-ID: \"${TERMIFIER_SURFACE_ID}\""),
                      "HermesConfigManager: managed block is missing X-Termifier-Surface-ID")
        XCTAssertTrue(content.contains("X-Termifier-Session-ID: \"${TERMIFIER_SESSION_ID}\""),
                      "HermesConfigManager: managed block is missing X-Termifier-Session-ID -- without it, " +
                      "TermifierMCPServer.resolveSurfaceID cannot identify a pane inside a persistent " +
                      "termifier-session")
    }
}
