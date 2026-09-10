//
//  TermifierWindowTermifierPerformCloseRoutingTests.swift
//  TermifierTests
//
//  GitHub issue #45. Full root-cause writeup:
//  `NSWindow+TermifierClose.swift`'s header comment.
//
//  Exercises `TermifierWindow.termifierPerformClose(_:)` itself (not the pure
//  `TermifierWindowController.closeFocusedTarget` decision function, see
//  `TermifierWindowControllerCloseFocusedTargetTests` for that exhaustive
//  matrix) — proves the WIRING from "Cmd+W landed on this window" all
//  the way to "the right `CloseFocusedTarget` was resolved", via
//  `TermifierWindowController._closeFocusedTargetHookForTesting`, mirroring
//  `TermifierWindowControllerCloseWindowTests`'s identical
//  hook-instead-of-the-real-unsafe-close pattern (a real close is never
//  driven here, so there is no test-host-crash risk — see that file's
//  own header for the danger this avoids).
//
//  Against the CURRENT code, `TermifierWindow.termifierPerformClose(_:)` is an
//  empty override and `TermifierWindowController.performCloseFocusedTarget(_:)`
//  is an empty stub that never touches the hook at all, so BOTH tests
//  below pin the fix: without it the hook is never invoked, and
//  `observed` stays `nil`.
//
//  Fixtures mirror `TermifierWindowControllerCloseWindowTests
//  .makeSurfaceOwningFixture()` (terminal case) and
//  `AppDelegateCloseAllWindowsTests.makeSingleTabFixture()` (browser
//  case, no live ghostty surface needed for a browser tab).
//

import XCTest
import AppKit
@testable import Termifier

@MainActor
final class TermifierWindowTermifierPerformCloseRoutingTests: XCTestCase {

    // MARK: - Fixtures

    private struct TerminalTabFixture {
        let controller: TermifierWindowController
        let tabID: UUID
        let leafID: UUID
    }

    /// Single-pane/single-tab/single-group terminal window.
    /// `SplitTree(leafID:)` auto-assigns `focusedLeafID = leafID` (see
    /// that initializer's own doc comment), so this tab's focused leaf
    /// is unambiguous.
    private func makeTerminalTabFixture() -> TerminalTabFixture {
        let registry = SurfaceRegistry()
        let leafID = UUID()
        let surfaceView = SurfaceView(frame: .zero)
        registry._testInsert(view: surfaceView, id: leafID)

        let tab = Tab(splitTree: SplitTree(leafID: leafID), registry: registry)
        let group = TabGroup(name: "Default", tabs: [tab], activeTabID: tab.id)
        let session = WindowSession(groups: [group], activeGroupID: group.id)
        let window = TermifierWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let controller = TermifierWindowController(window: window, windowSession: session, restoring: true)
        return TerminalTabFixture(controller: controller, tabID: tab.id, leafID: leafID)
    }

    private struct BrowserTabFixture {
        let controller: TermifierWindowController
        let tabID: UUID
    }

    /// Single browser tab: no `SurfaceRegistry` surface needed at all
    /// (mirrors `AppDelegateCloseAllWindowsTests.makeSingleTabFixture()`'s
    /// identical "no live ghostty surface" reasoning).
    private func makeBrowserTabFixture() -> BrowserTabFixture {
        let tab = Tab(content: .browser(url: URL(string: "https://example.com")!))
        let group = TabGroup(name: "Default", tabs: [tab], activeTabID: tab.id)
        let session = WindowSession(groups: [group], activeGroupID: group.id)
        let window = TermifierWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let controller = TermifierWindowController(window: window, windowSession: session, restoring: true)
        return BrowserTabFixture(controller: controller, tabID: tab.id)
    }

    // MARK: - Tests

    /// Pins the fix: see file header.
    func test_termifierPerformClose_terminalTabWithFocusedLeaf_routesToSurfaceTarget() {
        let fixture = makeTerminalTabFixture()
        var observed: CloseFocusedTarget?
        fixture.controller._closeFocusedTargetHookForTesting = { observed = $0 }

        fixture.controller.window?.termifierPerformClose(nil)

        XCTAssertEqual(
            observed, .surface(tabID: fixture.tabID, surfaceID: fixture.leafID),
            "termifierPerformClose(_:) on this window must resolve to .surface for its focused terminal pane"
        )
    }

    /// Pins the fix: see file header.
    func test_termifierPerformClose_browserTab_routesToTabTarget() {
        let fixture = makeBrowserTabFixture()
        var observed: CloseFocusedTarget?
        fixture.controller._closeFocusedTargetHookForTesting = { observed = $0 }

        fixture.controller.window?.termifierPerformClose(nil)

        XCTAssertEqual(
            observed, .tab(fixture.tabID),
            "termifierPerformClose(_:) on a browser-tab window must resolve to .tab, never .surface"
        )
    }
}
