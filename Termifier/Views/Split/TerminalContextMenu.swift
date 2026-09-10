// TerminalContextMenu.swift
// Termifier

import AppKit

/// Builds the context menu shown on right-click/Ctrl+click inside a
/// terminal pane (`SurfaceView.menu(for:)`). Same closure-injected
/// `Actions` shape as `TabContextMenu`/`GroupContextMenu`: this type
/// knows the menu's structure and enabled state, nothing about the
/// ghostty surface the items act on.
///
/// The split items deliberately duplicate File > Split Right/Left/Down/
/// Up rather than re-targeting those menu items: the main menu's
/// nil-target items resolve through `-[NSApplication targetForAction:]`
/// to the FOCUSED surface, whereas a context menu must act on the pane
/// that was actually right-clicked, focused or not. The caller supplies
/// closures bound to that pane's own `SurfaceView`.
enum TerminalContextMenu {
    struct Actions {
        var copy: () -> Void
        var paste: () -> Void
        var selectAll: () -> Void
        var splitRight: () -> Void
        var splitLeft: () -> Void
        var splitDown: () -> Void
        var splitUp: () -> Void
    }

    @MainActor
    static func make(hasSelection: Bool, canPaste: Bool, actions: Actions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(ClosureMenuItem(
            title: "Copy", symbolName: "doc.on.doc", identifier: AccessibilityID.TerminalContextMenu.copy,
            isEnabled: hasSelection, handler: actions.copy
        ))

        menu.addItem(ClosureMenuItem(
            title: "Paste", symbolName: "doc.on.clipboard", identifier: AccessibilityID.TerminalContextMenu.paste,
            isEnabled: canPaste, handler: actions.paste
        ))

        menu.addItem(ClosureMenuItem(
            title: "Select All", symbolName: "selection.pin.in.out",
            identifier: AccessibilityID.TerminalContextMenu.selectAll, handler: actions.selectAll
        ))

        menu.addItem(.separator())

        // Same order as File > Split Right/Left/Down/Up in
        // `AppDelegate.setupMainMenu()`.
        menu.addItem(ClosureMenuItem(
            title: "Split Right", symbolName: "rectangle.righthalf.inset.filled",
            identifier: AccessibilityID.TerminalContextMenu.splitRight, handler: actions.splitRight
        ))

        menu.addItem(ClosureMenuItem(
            title: "Split Left", symbolName: "rectangle.lefthalf.inset.filled",
            identifier: AccessibilityID.TerminalContextMenu.splitLeft, handler: actions.splitLeft
        ))

        menu.addItem(ClosureMenuItem(
            title: "Split Down", symbolName: "rectangle.bottomhalf.inset.filled",
            identifier: AccessibilityID.TerminalContextMenu.splitDown, handler: actions.splitDown
        ))

        menu.addItem(ClosureMenuItem(
            title: "Split Up", symbolName: "rectangle.tophalf.inset.filled",
            identifier: AccessibilityID.TerminalContextMenu.splitUp, handler: actions.splitUp
        ))

        return menu
    }

    /// Whether `pasteboard` currently holds something the terminal could
    /// paste as text. Read once per menu construction (i.e. per
    /// right-click) rather than through `validateMenuItem(_:)`, because
    /// `autoenablesItems == false` above opts this menu out of AppKit's
    /// validation pass entirely -- the same trade the other context
    /// menus in this codebase already make.
    @MainActor
    static func canPaste(from pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.canReadObject(forClasses: [NSString.self], options: nil)
    }
}
