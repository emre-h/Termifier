//
//  AgentSessionMetaBridgeTests.swift
//  TermifierTests
//
//  Covers `AgentSessionMetaBridge`: bridges an agent hook
//  event's self-reported session ID into the termifier-session daemon's
//  per-session meta map, via a fake `SessionDaemonClientProtocol` and
//  a real, test-owned `SessionSurfaceMap` instance — no real daemon
//  process.
//
//  Coverage:
//  - A surfaceID with a tracked termifier-session calls
//    daemonClient.setMeta with the resolved sessionID, the
//    SessionResumePlanner-encoded meta key, and the agent session ID
//  - A surfaceID with NO tracked termifier-session (an ordinary,
//    non-persistent pane) never calls setMeta at all
//

import XCTest
@testable import Termifier

/// Records every `setMeta(id:key:value:)` call — a process boundary
/// stand-in, no real `termifier-session` binary involved.
private final class FakeMetaBridgeDaemonClient: SessionDaemonClientProtocol, @unchecked Sendable {
    private(set) var metaSetCalls: [(id: String, key: String, value: String)] = []

    func sessionState(id: String) async -> SessionQueryResult { .unreachable }
    func kill(id: String) async {}
    func listAll() async -> [SessionInfo] { [] }

    func setMeta(id: String, key: String, value: String) async {
        metaSetCalls.append((id, key, value))
    }
}

@MainActor
final class AgentSessionMetaBridgeTests: XCTestCase {

    private var daemonClient: FakeMetaBridgeDaemonClient!
    private var surfaceMap: SessionSurfaceMap!
    private var bridge: AgentSessionMetaBridge!

    override func setUp() {
        super.setUp()
        daemonClient = FakeMetaBridgeDaemonClient()
        // A fresh instance per test — never touch `.shared`.
        surfaceMap = SessionSurfaceMap()
        bridge = AgentSessionMetaBridge(daemonClient: daemonClient, surfaceMap: surfaceMap)
    }

    override func tearDown() {
        bridge = nil
        surfaceMap = nil
        daemonClient = nil
        super.tearDown()
    }

    // MARK: - Tracked session -> setMeta called with resolved id + encoded key

    func test_recordAgentSession_trackedSurface_callsSetMetaWithResolvedSessionIDAndEncodedKey() async {
        let termifierSessionID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        let surfaceID = UUID()
        surfaceMap.register(sessionID: termifierSessionID, surfaceID: surfaceID)

        await bridge.recordAgentSession(
            surfaceID: surfaceID, agentKind: AgentEntry.claudeCodeKind, agentSessionID: "claude-conv-42"
        )

        XCTAssertEqual(daemonClient.metaSetCalls.count, 1,
                       "A surface with a tracked termifier-session must record exactly one setMeta call")
        let call = daemonClient.metaSetCalls.first
        XCTAssertEqual(call?.id, termifierSessionID,
                       "setMeta must target the termifier-session ID resolved from SessionSurfaceMap, not the surface UUID")
        XCTAssertEqual(call?.key, SessionResumePlanner.encodeMetaKey(kind: AgentEntry.claudeCodeKind),
                       "setMeta's key must use SessionResumePlanner's meta-key convention")
        XCTAssertEqual(call?.value, "claude-conv-42")
    }

    // MARK: - Untracked surface (non-persistent pane) -> no-op

    func test_recordAgentSession_untrackedSurface_neverCallsSetMeta() async {
        let surfaceID = UUID()
        // Deliberately no surfaceMap.register call.

        await bridge.recordAgentSession(
            surfaceID: surfaceID, agentKind: AgentEntry.claudeCodeKind, agentSessionID: "claude-conv-42"
        )

        XCTAssertTrue(daemonClient.metaSetCalls.isEmpty,
                     "A surface with no tracked termifier-session must never call setMeta")
    }
}
