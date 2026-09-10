// AccessibilityID.swift
// Termifier
//
// Stable accessibility identifiers for XCUITest element lookup.

import Foundation

enum AccessibilityID {
    enum Sidebar {
        static let container = "termifier.sidebar"
        static let newGroupButton = "termifier.sidebar.newGroupButton"
        static let agentModeButton = "termifier.sidebar.agentModeButton"
        static func group(_ id: UUID) -> String { "termifier.sidebar.group.\(id.uuidString)" }
        static func tab(_ id: UUID) -> String { "termifier.sidebar.tab.\(id.uuidString)" }
        static func groupNameTextField(_ id: UUID) -> String { "termifier.sidebar.groupNameTextField.\(id.uuidString)" }
        static func groupCollapseButton(_ id: UUID) -> String { "termifier.sidebar.groupCollapseButton.\(id.uuidString)" }
        static func tabCloseButton(_ id: UUID) -> String { "termifier.sidebar.tab.\(id.uuidString).closeButton" }
        static func groupCloseAllButton(_ id: UUID) -> String { "termifier.sidebar.group.\(id.uuidString).closeAllButton" }
        static func tabNameTextField(_ id: UUID) -> String { "termifier.sidebar.tabNameTextField.\(id.uuidString)" }
        static func tabAtIndex(_ groupID: UUID, _ index: Int) -> String {
            "termifier.sidebar.group.\(groupID.uuidString).tab.index.\(index)"
        }
        static func agentRow(id: UUID) -> String { "termifier.sidebar.agentRow.\(id.uuidString)" }
        static func agentRowDisclosure(id: UUID) -> String { "termifier.sidebar.agentRowDisclosure.\(id.uuidString)" }
        static func agentSubRow(id: String) -> String { "termifier.sidebar.agentSubRow.\(id)" }
        static let agentHooksIssuesBanner = "termifier.sidebar.agentHooksIssuesBanner"
        static let agentMonitoringDisabledBanner = "termifier.sidebar.agentMonitoringDisabledBanner"
    }
    enum GroupContextMenu {
        static let close = "termifier.groupMenu.close"
        static let closeOthers = "termifier.groupMenu.closeOthers"
        static let closeBelow = "termifier.groupMenu.closeBelow"
        static let rename = "termifier.groupMenu.rename"
        static let color = "termifier.groupMenu.color"
        static func color(_ color: TabGroupColor) -> String { "termifier.groupMenu.color.\(color.rawValue)" }
    }
    enum TerminalContextMenu {
        static let copy = "termifier.terminalMenu.copy"
        static let paste = "termifier.terminalMenu.paste"
        static let selectAll = "termifier.terminalMenu.selectAll"
        static let splitRight = "termifier.terminalMenu.splitRight"
        static let splitLeft = "termifier.terminalMenu.splitLeft"
        static let splitDown = "termifier.terminalMenu.splitDown"
        static let splitUp = "termifier.terminalMenu.splitUp"
    }
    enum TabBar {
        static let container = "termifier.tabBar"
        static let newTabButton = "termifier.tabBar.newTabButton"
        static func tab(_ id: UUID) -> String { "termifier.tabBar.tab.\(id.uuidString)" }
        static func tabCloseButton(_ id: UUID) -> String { "termifier.tabBar.tab.\(id.uuidString).closeButton" }
        static func tabNameTextField(_ id: UUID) -> String { "termifier.tabBar.tabNameTextField.\(id.uuidString)" }
        static func tabAtIndex(_ index: Int) -> String { "termifier.tabBar.tab.index.\(index)" }
    }
    enum CommandPalette {
        static let container = "termifier.commandPalette"
        static let searchField = "termifier.commandPalette.searchField"
        static let resultsTable = "termifier.commandPalette.resultsTable"
    }
    enum Compose {
        static let container = "termifier.compose"
        static let textView = "termifier.compose.textView"
        static let placeholder = "termifier.compose.placeholder"
    }
    enum Search {
        static let container = "termifier.search"
        static let searchField = "termifier.search.searchField"
        static let matchCount = "termifier.search.matchCount"
        static let previousButton = "termifier.search.previousButton"
        static let nextButton = "termifier.search.nextButton"
        static let closeButton = "termifier.search.closeButton"
    }
    enum Browser {
        static let toolbar = "termifier.browser.toolbar"
        static let backButton = "termifier.browser.backButton"
        static let forwardButton = "termifier.browser.forwardButton"
        static let reloadButton = "termifier.browser.reloadButton"
        static let urlDisplay = "termifier.browser.urlDisplay"
        static let errorBanner = "termifier.browser.errorBanner"
    }
    enum Git {
        static let changesContainer = "termifier.git.changes"
        static let refreshButton = "termifier.git.refreshButton"
        static let modeToggle = "termifier.git.modeToggle"
        static let stagedSection = "termifier.git.staged"
        static let unstagedSection = "termifier.git.unstaged"
        static let untrackedSection = "termifier.git.untracked"
        static let commitsSection = "termifier.git.commits"
        static func fileEntry(_ path: String) -> String { "termifier.git.file.\(path)" }
        static func commitRow(_ hash: String) -> String { "termifier.git.commit.\(hash)" }
        /// `id` is the repository's work-tree root path.
        static func repoSection(_ id: String) -> String { "termifier.git.repoSection.\(id)" }
        /// `id` is the repository's work-tree root path.
        static func refPicker(_ id: String) -> String { "termifier.git.refPicker.\(id)" }
    }
    /// Sessions pane of the Settings window
    /// (Termifier/Features/Settings/SettingsWindowController.swift). Applied
    /// to the four toggle NSSwitch controls so an XCUITest suite can
    /// locate a specific switch by a stable identifier instead of an
    /// ordinal position (`app.switches.firstMatch`), which silently
    /// breaks the moment a row is reordered or another switch is added
    /// above it.
    enum Settings {
        static let persistentSessionsSwitch = "termifier.settings.sessions.persistentSessionsSwitch"
        static let historyPersistenceSwitch = "termifier.settings.sessions.historyPersistenceSwitch"
        static let agentResumeSwitch = "termifier.settings.sessions.agentResumeSwitch"
        static let agentResumeAutoExecuteSwitch = "termifier.settings.sessions.agentResumeAutoExecuteSwitch"
        static let commandTrackingSwitch = "termifier.settings.sessions.commandTrackingSwitch"
        static let smoothScrollingSwitch = "termifier.settings.appearance.smoothScrollingSwitch"
        static let glassOpacityCellsSwitch = "termifier.settings.appearance.glassOpacityCellsSwitch"
        static let lspAutoInstallSwitch = "termifier.settings.lsp.lspAutoInstallSwitch"
        static let lspRequireConfirmationSwitch = "termifier.settings.lsp.lspRequireConfirmationSwitch"
        static let cockpitAutoApproveSwitch = "termifier.settings.sessions.cockpitAutoApproveSwitch"
        static let agentHookApprovalSwitch = "termifier.settings.sessions.agentHookApprovalSwitch"
    }
    enum SessionBrowser {
        static func row(_ id: String) -> String { "termifier.sessionBrowser.row.\(id)" }
        static func attachButton(_ id: String) -> String { "termifier.sessionBrowser.row.\(id).attachButton" }
        static func killButton(_ id: String) -> String { "termifier.sessionBrowser.row.\(id).killButton" }
        static func remoteHostRow(_ host: String) -> String { "termifier.sessionBrowser.remoteHost.\(host)" }
        static func remoteHostAttachButton(_ host: String) -> String { "termifier.sessionBrowser.remoteHost.\(host).attachButton" }
        static func remoteHostInstallButton(_ host: String) -> String { "termifier.sessionBrowser.remoteHost.\(host).installButton" }
        static func herdrRow(_ id: String) -> String { "termifier.sessionBrowser.herdr.\(id)" }
        static func herdrCreateButton(_ id: String) -> String { "termifier.sessionBrowser.herdr.\(id).createButton" }
        static func herdrWorkspaceRow(_ id: String) -> String { "termifier.sessionBrowser.herdrWorkspace.\(id)" }
        static func herdrWorkspaceAttachButton(_ id: String) -> String { "termifier.sessionBrowser.herdrWorkspace.\(id).attachButton" }
        static func herdrWorkspaceKillButton(_ id: String) -> String { "termifier.sessionBrowser.herdrWorkspace.\(id).killButton" }
    }
    /// Chrome-style in-app "your previous session was preserved" bar,
    /// shown at the top of a window when AppDelegate
    /// .hasPreservedSessionSnapshot is true (see RecoveryBarModel,
    /// Termifier/Features/Persistence/). Deliberately `termifier.recoveryBar.*`
    /// (a container + two per-window action buttons), not the bare
    /// `termifier.recoveryBar` some other single-container enums here use
    /// (e.g. Sidebar.container == "termifier.sidebar"), since this bar's own
    /// two buttons need distinguishable identifiers alongside it.
    enum RecoveryBar {
        static let container = "termifier.recoveryBar.container"
        static let restoreButton = "termifier.recoveryBar.restoreButton"
        static let dismissButton = "termifier.recoveryBar.dismissButton"
    }
    /// Cockpit approval banner, shown in a floating panel
    /// (ApprovalPanelWindow) at the screen's top-right corner when
    /// ApprovalBannerModel.current is non-nil (see ApprovalBannerModel,
    /// Termifier/Features/ApprovalInbox/). A macOS-notification-style
    /// layout, at a fixed 344pt (640pt for a request wanting inline
    /// option rows): the app icon on the left, a bold single-line,
    /// middle-truncated title (tool/target label, plus the queue
    /// navigator while more than one request is queued), a one-to-two-
    /// line secondary body (`payload`, tap-to-expand into
    /// `payloadExpanded`), and a vertically centered trailing column
    /// holding one source-specific primary action button plus an
    /// `optionsMenu` pull-down that lists every choice the CLI offers
    /// beyond that primary action (ApprovalBannerView). The panel itself
    /// paints with the same untinted regular glass as a native
    /// notification, independent of the Termifier theme
    /// (ApprovalPanelContentView).
    ///
    /// `payload` carries the FULL rendered text as its accessibility
    /// label (queried while visually truncated to two lines); clicking
    /// it toggles `payloadExpanded`, the scrolling full payload shown
    /// below the body (`ExpandableBodyText`, shared by `.mcpTool`/
    /// `.agentHook`'s payload and `.agentQuestion`'s question text).
    /// `optionsMenu` is an `NSMenu` pull-down -- its own items reach the
    /// accessibility tree as `NSMenuItem` titles, found by title text
    /// rather than identifier, the same way the queue preview menu's rows
    /// already are: every row that ever lands only in a `Menu` (a
    /// `.mcpTool`/`.agentHook` choice row, a question option/"Other…"
    /// row rendered through the Options menu rather than inline, "Add
    /// notes"/"Back"/"Chat about this") carries no identifier of its own
    /// for this reason, and is looked up by title in an XCUITest instead.
    ///
    /// `.mcpTool`'s primary action is "Allow" (`allowButton`); its
    /// `optionsMenu` lists "Always Allow" and "Deny", by title.
    /// `.agentHook`'s primary action is "Yes" (`allowButton`); its
    /// `optionsMenu` lists one row per `AgentHookOffers.permissionUpdates`
    /// element, Termifier's own pane-scoped "Always Allow ... in This Pane"
    /// only when the CLI sent no offer of its own, and "No" -- all by
    /// title. `.agentQuestion` shows no primary action at all for a plain
    /// single-select click (an option click confirms immediately);
    /// "Next"/"Answer" (`answerButton`) appears only while a multi-select
    /// question or a visible free-text field needs confirming. For a
    /// single-select question with no option carrying a `preview`, its
    /// `optionsMenu` lists each option (`optionButton(_:)`), "Other…"
    /// (`otherButton`), "Add notes", "Back" once available, and "Chat
    /// about this" -- the last three by title. For a multi-select
    /// question, or one where any option carries a `preview`, the
    /// options themselves render as an inline list instead (still
    /// `optionButton(_:)`, plus a standing `otherButton` row on the same
    /// list) and `optionsMenu` holds only "Add notes"/"Back"/"Chat about
    /// this" (by title) -- no `otherButton` of its own there, since the
    /// inline list's own row already covers it. `questionText`/
    /// `otherTextField`/`notesTextField`/`questionPosition` cover the
    /// body/input elements that layout adds below the header and body
    /// text. `previewText` is the side-by-side markdown preview box,
    /// shown next to the inline option list only when an option carries a
    /// `preview`. Queue navigation adds `previousButton`/
    /// `nextButton`/`positionLabel`, shown only while more than one
    /// request is queued for this window (see ApprovalBannerModel.
    /// positionInfo). The queue preview menu wraps that same position
    /// label in a `Menu` (`queueMenu`) listing every request in
    /// ApprovalBannerModel.queueEntries, so a click can jump straight to
    /// any queued request via ApprovalBannerModel.select(id:). macOS
    /// collapses that `Menu` into one accessibility element, which leaves
    /// `positionLabel` unreachable from the accessibility tree: the
    /// "N / M" text is exposed as `queueMenu`'s own accessibility label
    /// instead (see ApprovalBannerView.queueNavigator(positionInfo:)).
    enum ApprovalBanner {
        static let container = "termifier.approvalBanner.container"
        static let allowButton = "termifier.approvalBanner.allowButton"
        static let payload = "termifier.approvalBanner.payload"
        static let payloadExpanded = "termifier.approvalBanner.payloadExpanded"
        static let optionsMenu = "termifier.approvalBanner.optionsMenu"
        static let previousButton = "termifier.approvalBanner.previousButton"
        static let nextButton = "termifier.approvalBanner.nextButton"
        static let positionLabel = "termifier.approvalBanner.positionLabel"
        static let queueMenu = "termifier.approvalBanner.queueMenu"
        static let questionText = "termifier.approvalBanner.questionText"
        static func optionButton(_ index: Int) -> String { "termifier.approvalBanner.optionButton.\(index)" }
        static let otherButton = "termifier.approvalBanner.otherButton"
        static let otherTextField = "termifier.approvalBanner.otherTextField"
        static let answerButton = "termifier.approvalBanner.answerButton"
        static let questionPosition = "termifier.approvalBanner.questionPosition"
        static let previewText = "termifier.approvalBanner.previewText"
        static let notesTextField = "termifier.approvalBanner.notesTextField"
        /// The panel's own top-left ×, straddling the glass sheet's
        /// top-left corner (`ApprovalPanelContentView`'s own
        /// `.overlay(alignment: .topLeading)`, drawn into the window's
        /// transparent `ApprovalPanelArranger.gutter`), shown only
        /// while the panel is hovered. Resolves `.dismissed` for a
        /// dismissible request (`ApprovalRequest.isDismissible`);
        /// disabled (but still present, same identifier) for one that
        /// isn't.
        static let dismissButton = "termifier.approvalBanner.dismissButton"
        /// `ApprovalTooltipWindow`'s own content -- the Termifier-drawn
        /// tooltip `ExpandableBodyText`'s `collapsedText` shows on
        /// hover, in place of AppKit's own `.help` (the panel is a
        /// non-activating panel that never becomes key on hover, so a
        /// pointer entering it elsewhere and sliding onto the text never
        /// arms the system tooltip).
        static let tooltip = "termifier.approvalBanner.tooltip"
    }
    enum Diff {
        static let container = "termifier.diff"
        static let toolbar = "termifier.diff.toolbar"
        static let content = "termifier.diff.content"
        static let lineNumberGutter = "termifier.diff.lineNumbers"
    }
    enum DiffReview {
        static let submitButton = "termifier.diff.review.submitButton"
        static let discardButton = "termifier.diff.review.discardButton"
        static let commentBadge = "termifier.diff.review.commentBadge"
        static let commentPopover = "termifier.diff.review.commentPopover"
        static let submitAllButton = "termifier.diff.review.submitAllButton"
        static let discardAllButton = "termifier.diff.review.discardAllButton"
    }
}
