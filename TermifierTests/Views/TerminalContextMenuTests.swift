// TerminalContextMenuTests.swift
// TermifierTests
//
// Covers `TerminalContextMenu.make(hasSelection:canPaste:actions:)` and
// `TerminalContextMenu.canPaste(from:)`
// (Termifier/Views/Split/TerminalContextMenu.swift). The menu shown on
// right-click/Ctrl+click inside a terminal pane must always contain
// exactly 8 items, in this exact order: "Copy", "Paste", "Select All",
// a separator, "Split Right", "Split Left", "Split Down", "Split Up".
// Split order matches File > Split Right/Left/Down/Up in
// `AppDelegate.setupMainMenu()`.
//
// Enabled state: "Copy" is `hasSelection`, "Paste" is `canPaste`;
// every other item is always enabled (`autoenablesItems == false`, so
// AppKit never runs its own validation pass over this menu and the
// enabled flags set here are the ones the user sees). Firing an item's
// `target`/`action` must invoke exactly the matching `Actions` closure
// and no other -- the caller binds those closures to the
// right-CLICKED pane's `SurfaceView`, never the focused one.

import XCTest
import AppKit
@testable import Termifier

@MainActor
final class TerminalContextMenuTests: XCTestCase {

    // MARK: - Fixture

    /// One counter per `Actions` closure, so firing an item can be
    /// asserted to increment ONLY its own counter and none of the others.
    private final class ActionCounters {
        var copy = 0
        var paste = 0
        var selectAll = 0
        var splitRight = 0
        var splitLeft = 0
        var splitDown = 0
        var splitUp = 0
    }

    private func makeCounters() -> (ActionCounters, TerminalContextMenu.Actions) {
        let counters = ActionCounters()
        let actions = TerminalContextMenu.Actions(
            copy: { counters.copy += 1 },
            paste: { counters.paste += 1 },
            selectAll: { counters.selectAll += 1 },
            splitRight: { counters.splitRight += 1 },
            splitLeft: { counters.splitLeft += 1 },
            splitDown: { counters.splitDown += 1 },
            splitUp: { counters.splitUp += 1 }
        )
        return (counters, actions)
    }

    private func makeMenu(hasSelection: Bool = true, canPaste: Bool = true) -> (NSMenu, ActionCounters) {
        let (counters, actions) = makeCounters()
        let menu = TerminalContextMenu.make(hasSelection: hasSelection, canPaste: canPaste, actions: actions)
        return (menu, counters)
    }

    /// Fires `item`'s target/action the way AppKit does when the user
    /// picks it, without running `NSMenu`'s modal tracking loop.
    private func fire(_ item: NSMenuItem) throws {
        let target = try XCTUnwrap(item.target as? NSObject)
        let action = try XCTUnwrap(item.action)
        target.perform(action, with: item)
    }

    // MARK: - Structure

    func test_make_hasEightItems_inSpecifiedOrder() {
        let (menu, _) = makeMenu()

        XCTAssertEqual(menu.items.count, 8)
        XCTAssertEqual(menu.items[0].title, "Copy")
        XCTAssertEqual(menu.items[1].title, "Paste")
        XCTAssertEqual(menu.items[2].title, "Select All")
        XCTAssertTrue(menu.items[3].isSeparatorItem, "index 3 must be the separator between edit and split actions")
        XCTAssertEqual(menu.items[4].title, "Split Right")
        XCTAssertEqual(menu.items[5].title, "Split Left")
        XCTAssertEqual(menu.items[6].title, "Split Down")
        XCTAssertEqual(menu.items[7].title, "Split Up")
    }

    /// `autoenablesItems == false` is what makes the explicit
    /// `isEnabled` flags below authoritative; with AppKit's default
    /// `true` the items would be re-validated against the responder
    /// chain and the `hasSelection`/`canPaste` gates would be ignored.
    func test_make_disablesAutomaticItemEnabling() {
        let (menu, _) = makeMenu()

        XCTAssertFalse(menu.autoenablesItems)
    }

    func test_make_setsAccessibilityIdentifiers() {
        let (menu, _) = makeMenu()

        XCTAssertEqual(menu.items[0].accessibilityIdentifier(), AccessibilityID.TerminalContextMenu.copy)
        XCTAssertEqual(menu.items[1].accessibilityIdentifier(), AccessibilityID.TerminalContextMenu.paste)
        XCTAssertEqual(menu.items[2].accessibilityIdentifier(), AccessibilityID.TerminalContextMenu.selectAll)
        XCTAssertEqual(menu.items[4].accessibilityIdentifier(), AccessibilityID.TerminalContextMenu.splitRight)
        XCTAssertEqual(menu.items[5].accessibilityIdentifier(), AccessibilityID.TerminalContextMenu.splitLeft)
        XCTAssertEqual(menu.items[6].accessibilityIdentifier(), AccessibilityID.TerminalContextMenu.splitDown)
        XCTAssertEqual(menu.items[7].accessibilityIdentifier(), AccessibilityID.TerminalContextMenu.splitUp)
    }

    // MARK: - Enabled state

    func test_make_withSelection_enablesCopy() {
        let (menu, _) = makeMenu(hasSelection: true)

        XCTAssertTrue(menu.items[0].isEnabled)
    }

    func test_make_withoutSelection_disablesCopy() {
        let (menu, _) = makeMenu(hasSelection: false)

        XCTAssertFalse(menu.items[0].isEnabled)
    }

    func test_make_withPasteableClipboard_enablesPaste() {
        let (menu, _) = makeMenu(canPaste: true)

        XCTAssertTrue(menu.items[1].isEnabled)
    }

    func test_make_withEmptyClipboard_disablesPaste() {
        let (menu, _) = makeMenu(canPaste: false)

        XCTAssertFalse(menu.items[1].isEnabled)
    }

    /// Select All and the four split items never depend on selection or
    /// clipboard state: splitting an empty, unselected pane is valid.
    func test_make_withNoSelectionAndNoClipboard_keepsSelectAllAndSplitsEnabled() {
        let (menu, _) = makeMenu(hasSelection: false, canPaste: false)

        for index in [2, 4, 5, 6, 7] {
            XCTAssertTrue(menu.items[index].isEnabled, "item \(index) (\(menu.items[index].title)) must stay enabled")
        }
    }

    // MARK: - Actions

    func test_firingCopy_invokesOnlyCopyAction() throws {
        let (menu, counters) = makeMenu()

        try fire(menu.items[0])

        XCTAssertEqual(counters.copy, 1)
        XCTAssertEqual(counters.paste + counters.selectAll, 0)
        XCTAssertEqual(counters.splitRight + counters.splitLeft + counters.splitDown + counters.splitUp, 0)
    }

    func test_firingPaste_invokesOnlyPasteAction() throws {
        let (menu, counters) = makeMenu()

        try fire(menu.items[1])

        XCTAssertEqual(counters.paste, 1)
        XCTAssertEqual(counters.copy + counters.selectAll, 0)
        XCTAssertEqual(counters.splitRight + counters.splitLeft + counters.splitDown + counters.splitUp, 0)
    }

    func test_firingSelectAll_invokesOnlySelectAllAction() throws {
        let (menu, counters) = makeMenu()

        try fire(menu.items[2])

        XCTAssertEqual(counters.selectAll, 1)
        XCTAssertEqual(counters.copy + counters.paste, 0)
        XCTAssertEqual(counters.splitRight + counters.splitLeft + counters.splitDown + counters.splitUp, 0)
    }

    /// The four split items must map to four DISTINCT closures: a
    /// copy/paste slip between them would split the pane the wrong way
    /// while every structural assertion above still passed.
    func test_firingEachSplitItem_invokesOnlyItsOwnAction() throws {
        let cases: [(index: Int, name: String, count: (ActionCounters) -> Int)] = [
            (4, "Split Right", { $0.splitRight }),
            (5, "Split Left", { $0.splitLeft }),
            (6, "Split Down", { $0.splitDown }),
            (7, "Split Up", { $0.splitUp }),
        ]

        for testCase in cases {
            let (menu, counters) = makeMenu()

            try fire(menu.items[testCase.index])

            XCTAssertEqual(testCase.count(counters), 1, "\(testCase.name) must invoke its own action")
            let total = counters.copy + counters.paste + counters.selectAll
                + counters.splitRight + counters.splitLeft + counters.splitDown + counters.splitUp
            XCTAssertEqual(total, 1, "\(testCase.name) must invoke no other action")
        }
    }

    // MARK: - canPaste(from:)

    /// A private, uniquely named pasteboard rather than `.general`: the
    /// test host must never clobber the developer's real clipboard.
    private func makeScratchPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.termifier.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    func test_canPaste_withTextOnPasteboard_isTrue() {
        let pasteboard = makeScratchPasteboard()
        pasteboard.setString("echo hi", forType: .string)

        XCTAssertTrue(TerminalContextMenu.canPaste(from: pasteboard))
    }

    func test_canPaste_withClearedPasteboard_isFalse() {
        let pasteboard = makeScratchPasteboard()

        XCTAssertFalse(TerminalContextMenu.canPaste(from: pasteboard))
    }
}
