//
//  AgentHookScriptSessionIDTests.swift
//  TermifierTests
//
//  Covers AgentHookScript.scriptBody's termifier-session
//  awareness: a persistent-session pane's identity survives ghostty
//  surface re-creation (reconnect), while its TERMIFIER_SURFACE_ID does
//  not — so the hook must send whichever is stable, preferring
//  TERMIFIER_SESSION_ID over TERMIFIER_SURFACE_ID when both are set.
//
//  Coverage:
//  - scriptBody references TERMIFIER_SESSION_ID at all
//  - The value posted in the X-Termifier-Surface-ID header uses the
//    standard POSIX sh fallback expression `${TERMIFIER_SESSION_ID:-
//    $TERMIFIER_SURFACE_ID}`, so a persistent-session pane's termifier-session
//    ID is preferred whenever it is set, falling back to the existing
//    TERMIFIER_SURFACE_ID otherwise
//  - The guard must fail-open (exit 0)
//    only when BOTH TERMIFIER_SURFACE_ID and TERMIFIER_SESSION_ID are unset —
//    not just TERMIFIER_SURFACE_ID as before. A real /bin/sh execution test
//    (AgentHookScriptSessionIDPipelineTests) proves this end to end
//    with only TERMIFIER_SESSION_ID set.
//

import XCTest
@testable import Termifier

final class AgentHookScriptSessionIDTests: XCTestCase {

    func test_scriptBody_referencesTermifierSessionID() {
        XCTAssertTrue(AgentHookScript.scriptBody.contains("TERMIFIER_SESSION_ID"),
                     "scriptBody must reference TERMIFIER_SESSION_ID so a persistent-session pane's stable " +
                     "identity can be forwarded instead of its surface ID")
    }

    func test_scriptBody_headerValue_prefersSessionIDOverSurfaceIDViaShFallback() {
        XCTAssertTrue(
            AgentHookScript.scriptBody.contains("${TERMIFIER_SESSION_ID:-$TERMIFIER_SURFACE_ID}"),
            "The value sent in the X-Termifier-Surface-ID header must be the standard POSIX sh fallback " +
            "expression `${TERMIFIER_SESSION_ID:-$TERMIFIER_SURFACE_ID}`, preferring TERMIFIER_SESSION_ID (stable " +
            "across reconnect) over TERMIFIER_SURFACE_ID (not stable across reconnect) whenever it is set"
        )
    }

    // Replaces the original contract's
    // "guard only checks TERMIFIER_SURFACE_ID" test. The corrected guard
    // must fail-open only when NEITHER variable is set, so that a
    // future call site which sets TERMIFIER_SESSION_ID without
    // TERMIFIER_SURFACE_ID (not possible today, but the guard must not
    // silently rely on that invariant holding forever) still gets its
    // event forwarded. See AgentHookScriptSessionIDPipelineTests for
    // the real end-to-end proof via an actual /bin/sh execution.
    func test_scriptBody_guardExitsOnlyWhenBothSurfaceIDAndSessionIDAreUnset() {
        let body = AgentHookScript.scriptBody
        XCTAssertTrue(
            body.contains("[ -z \"$TERMIFIER_SURFACE_ID\" ]") && body.contains("[ -z \"$TERMIFIER_SESSION_ID\" ]"),
            "The guard must test both TERMIFIER_SURFACE_ID and TERMIFIER_SESSION_ID for emptiness, not just " +
            "TERMIFIER_SURFACE_ID as before"
        )
        XCTAssertTrue(body.contains("exit 0"), "The fail-open exit-0 contract must be preserved")
    }
}
