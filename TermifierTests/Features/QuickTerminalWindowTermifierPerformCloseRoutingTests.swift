//
//  QuickTerminalWindowTermifierPerformCloseRoutingTests.swift
//  TermifierTests
//
//  GitHub issue #45 follow-up. Full root-cause writeup:
//  `NSWindow+TermifierClose.swift`'s header comment.
//
//  Exercises `QuickTerminalWindow.termifierPerformClose(_:)` itself — the
//  parallel of `TermifierWindowTermifierPerformCloseRoutingTests` for
//  `TermifierWindow` — proving the WIRING from "Cmd+W landed on the quick
//  terminal window" all the way to
//  `QuickTerminalController.requestHide()`, not just that
//  `requestHide()` itself behaves correctly in isolation
//  (`QuickTerminalControllerRequestHideTests` already covers that, but
//  assumes without proving that the override actually calls it).
//
//  Added after the initial implementation: this
//  override already exists and is already correct (see
//  `QuickTerminalWindow.swift`'s own doc comment on
//  `termifierPerformClose(_:)`). Both tests below are regression guards
//  against the wiring silently breaking later — e.g. the
//  `delegate as? QuickTerminalController` cast being dropped, or the
//  `else` branch's `super.termifierPerformClose` fallback being removed.
//
//  `QuickTerminalController()` is safe to construct directly: its
//  `init` only registers notification observers (`.ghosttyConfigChange`
//  and `.ghosttyCloseSurface`), and neither creates a window nor a
//  ghostty surface (both deferred to `animateIn()`/`ensureSurface()`,
//  never called here) — see
//  `AppDelegate._setQuickTerminalControllerForTesting`'s own doc
//  comment (AppDelegate.swift) for this exact guarantee, and
//  `QuickTerminalControllerRequestHideTests`'s header for the same
//  reasoning applied to `requestHide()` itself.
//
//  The window built below is NEVER shown (no `makeKeyAndOrderFront`/
//  `orderFront` call anywhere in this file) — matching every other
//  close-path test file's own warning that a REAL window close can
//  crash the XCTest host (see `TermifierWindowControllerCloseWindowTests`'s
//  header and `AppDelegateCloseAllWindowsTests`'s DANGER note). The
//  delegate-is-`QuickTerminalController` case below never reaches
//  AppKit's real close machinery at all (`requestHide()`'s hook seam
//  intercepts it before `animateOut()`); the delegate-is-something-else
//  (fallback) case mirrors `NSWindowTermifierCloseTests`'s own
//  `windowShouldClose(_:) -> false` trick to let
//  `super.termifierPerformClose` -> `performClose(_:)` run for real without
//  ever actually closing anything.
//

import XCTest
import AppKit
@testable import Termifier

@MainActor
final class QuickTerminalWindowTermifierPerformCloseRoutingTests: XCTestCase {

    // MARK: - Test double

    /// Always answers `false` (never actually close) and records how
    /// many times AppKit asked — mirrors `NSWindowTermifierCloseTests
    /// .RecordingDelegate` exactly, for the fallback-to-`super` case
    /// below.
    private final class RecordingDelegate: NSObject, NSWindowDelegate {
        private(set) var windowShouldCloseCallCount = 0

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            windowShouldCloseCallCount += 1
            return false
        }
    }

    // MARK: - Window factory

    private func makeBareWindow() -> QuickTerminalWindow {
        let window = QuickTerminalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Same discipline as `NSWindowTermifierCloseTests.makeBareWindow()`:
        // nothing in this file should reach a real close, but every
        // fixture in this codebase disables this defensively before
        // calling any close-family method on a real window/panel.
        window.isReleasedWhenClosed = false
        return window
    }

    // MARK: - Delegate IS QuickTerminalController: routes to requestHide()

    func test_termifierPerformClose_withQuickTerminalControllerDelegate_invokesRequestHide() {
        let window = makeBareWindow()
        let controller = QuickTerminalController()
        window.delegate = controller
        defer {
            window.delegate = nil
            window.orderOut(nil)
        }
        controller._setVisibleForTesting(true)
        var hookCalled = false
        controller._requestHideHookForTesting = { hookCalled = true }

        window.termifierPerformClose(nil)

        XCTAssertTrue(
            hookCalled,
            "termifierPerformClose(_:) on the quick terminal window must route to " +
            "QuickTerminalController.requestHide(), not a real window close"
        )
    }

    // MARK: - Delegate is NOT QuickTerminalController: falls back to super (regression guard)

    func test_termifierPerformClose_withNonQuickTerminalControllerDelegate_fallsBackToSuper() {
        let window = makeBareWindow()
        let delegate = RecordingDelegate()
        window.delegate = delegate
        defer {
            window.delegate = nil
            window.orderOut(nil)
        }

        window.termifierPerformClose(nil)

        XCTAssertEqual(
            delegate.windowShouldCloseCallCount, 1,
            "When the delegate is not a QuickTerminalController, termifierPerformClose(_:) must fall back to " +
            "NSWindow's base implementation (super.termifierPerformClose), which consults windowShouldClose(_:) " +
            "via performClose(_:) exactly like any other plain window"
        )
    }
}
