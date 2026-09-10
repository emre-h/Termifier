// SurfaceViewContextMenuTests.swift
// TermifierTests
//
// Covers `SurfaceView.menu(for:)` (Termifier/GhosttyBridge/SurfaceView.swift),
// the override AppKit calls to resolve the context menu for a
// right-click/Ctrl+click inside a terminal pane. Only that override's
// return value is asserted, by constructing an `NSEvent` and calling it
// directly -- never the actual popup: `NSMenu.popUpContextMenu` runs a
// modal tracking loop that must not be exercised in a unit test. Same
// discipline as `ClickContainerNSViewContextMenuTests`.
//
// The menu's own structure and enabled-state rules live in
// `TerminalContextMenuTests`; what these tests pin is the WIRING --
// that the override returns that menu at all, that a `SurfaceView`
// whose `surfaceController` is still nil (the window between
// `SurfaceView(frame:)` and `ghostty_surface_new`, and the only state a
// unit test can construct) degrades to "no selection" rather than
// crashing, and that the split items act on THIS view.
//
// Not covered here, because it needs a live ghostty surface: the gate
// in `rightMouseDown(with:)` that suppresses the menu entirely while
// the running program has mouse reporting enabled. That gate predates
// this menu -- `menu(for:)` is simply never reached when
// `sendMouseButton` reports the press consumed, since only the `super`
// call falls through to AppKit's default menu handling.

import XCTest
import AppKit
@testable import Termifier

@MainActor
final class SurfaceViewContextMenuTests: XCTestCase {

    private func makeRightClickEvent() throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    func test_menuForEvent_returnsTerminalContextMenuStructure() throws {
        let view = SurfaceView(frame: .zero)
        let event = try makeRightClickEvent()

        let menu = try XCTUnwrap(view.menu(for: event))

        XCTAssertEqual(menu.items.map(\.title), [
            "Copy", "Paste", "Select All", "", "Split Right", "Split Left", "Split Down", "Split Up",
        ])
    }

    /// `surfaceController == nil` must read as "nothing selected", not
    /// trap: `hasSelection` is reached through an optional chain that
    /// defaults to `false`.
    func test_menuForEvent_withNoSurfaceController_disablesCopy() throws {
        let view = SurfaceView(frame: .zero)
        let event = try makeRightClickEvent()

        let menu = try XCTUnwrap(view.menu(for: event))

        XCTAssertNil(view.surfaceController, "precondition: a bare SurfaceView has no ghostty surface yet")
        XCTAssertFalse(menu.items[0].isEnabled)
    }

    /// The split items must remain enabled on a controller-less view:
    /// their enabled state is structural, not surface-dependent (a nil
    /// controller simply makes the action a no-op, as it does for the
    /// File menu's own split items).
    func test_menuForEvent_withNoSurfaceController_keepsSplitItemsEnabled() throws {
        let view = SurfaceView(frame: .zero)
        let event = try makeRightClickEvent()

        let menu = try XCTUnwrap(view.menu(for: event))

        for index in 4...7 {
            XCTAssertTrue(menu.items[index].isEnabled, "\(menu.items[index].title) must stay enabled")
        }
    }

    /// Firing a split item on a controller-less view must be a silent
    /// no-op rather than a crash -- the closure routes through
    /// `SurfaceView.splitRight(_:)`, whose `surfaceController?` chain
    /// absorbs the nil.
    func test_firingSplitRight_withNoSurfaceController_doesNotCrash() throws {
        let view = SurfaceView(frame: .zero)
        let event = try makeRightClickEvent()
        let menu = try XCTUnwrap(view.menu(for: event))
        let item = menu.items[4]
        let target = try XCTUnwrap(item.target as? NSObject)
        let action = try XCTUnwrap(item.action)

        target.perform(action, with: item)
    }

    /// Each right-click builds a fresh menu, so selection/clipboard
    /// state is re-read per click rather than cached from the first one.
    func test_menuForEvent_calledTwice_returnsDistinctMenus() throws {
        let view = SurfaceView(frame: .zero)
        let event = try makeRightClickEvent()

        let first = try XCTUnwrap(view.menu(for: event))
        let second = try XCTUnwrap(view.menu(for: event))

        XCTAssertFalse(first === second, "menu(for:) must rebuild, not return a cached menu")
    }
}
