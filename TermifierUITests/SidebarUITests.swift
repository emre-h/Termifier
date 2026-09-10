// SidebarUITests.swift
// TermifierUITests

import XCTest

final class SidebarUITests: TermifierUITestCase {

    func test_sidebarVisibleByDefault() {
        let sidebar = app.descendants(matching: .any)
            .matching(identifier: "termifier.sidebar")
            .firstMatch
        XCTAssertTrue(waitFor(sidebar), "Sidebar should be visible by default")
    }

    func test_toggleSidebar_hidesAndShows() {
        let sidebar = app.descendants(matching: .any)
            .matching(identifier: "termifier.sidebar")
            .firstMatch
        XCTAssertTrue(waitFor(sidebar), "Sidebar should initially be visible")

        // Hide sidebar
        toggleSidebarViaMenu()
        waitForNonExistence(sidebar)

        // Show sidebar
        toggleSidebarViaMenu()
        XCTAssertTrue(waitFor(sidebar), "Sidebar should be visible again after toggle")
    }

    func test_sidebarShowsGroupAndTab() {
        let groupCount = countElements(matching: "termifier.sidebar.group.", excludingSuffix: "Button")
        XCTAssertEqual(groupCount, 1, "Should have one group initially")

        let tabCount = countElements(matching: "termifier.sidebar.tab.", excludingSuffix: ".closeButton")
        XCTAssertEqual(tabCount, 1, "Should have one tab in sidebar initially")
    }
}
