import XCTest

/// Drives the app with the Siri Remote, as on the TV: focus has to reach the settings panel
/// and come back to the dashboard, or the remote does nothing at all.
final class RemoteTests: XCTestCase {
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    /// A first launch opens settings with nothing chosen; the remote must be able to move
    /// through the panel and pick the demo week.
    func testFirstLaunchSettingsTakeTheRemote() {
        let app = XCUIApplication()
        // An empty stored connection is a first launch, whatever an earlier run saved.
        app.launchArguments = ["-connection", "", "-layout", "dashboard"]
        app.launch()

        // Focus sits on a list row: the cell, not the button inside it.
        let demo = app.cells["Demo data"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        // A Pi's row, or the address field when none has turned up.
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
        XCTAssertTrue(focused.firstMatch.waitForExistence(timeout: 5), "something in the drawer has focus")

        // A first launch opens on the Source page; down its list to Demo data.
        for _ in 0..<10 where !demo.hasFocus {
            remote.press(.down)
        }
        XCTAssertTrue(demo.hasFocus, "the remote reaches Demo data")

        remote.press(.select)
        XCTAssertTrue(demo.waitForNonExistence(timeout: 5), "choosing a source closes settings")
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10), "the demo week shows")
    }

    /// From the dashboard, a click opens settings with focus inside, and Menu closes them.
    func testClickOpensSettingsAndMenuClosesThem() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES", "-layout", "dashboard"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))

        remote.press(.select)
        // The row reads "Layout, Dashboard": its name, then the value.
        let layout = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'Layout'")).firstMatch
        XCTAssertTrue(layout.waitForExistence(timeout: 5), "a click opens settings")
        XCTAssertTrue(layout.waitForHasFocus(timeout: 5), "focus lands in the drawer")

        remote.press(.select)
        let night = app.cells["Night"]
        XCTAssertTrue(night.waitForExistence(timeout: 5), "Layout opens the layout list")
        remote.press(.menu)
        XCTAssertTrue(layout.waitForHasFocus(timeout: 5), "Menu goes back a page first")

        remote.press(.menu)
        XCTAssertTrue(layout.waitForNonExistence(timeout: 5), "then Menu closes settings")

        remote.press(.select)
        XCTAssertTrue(layout.waitForExistence(timeout: 5), "the dashboard has focus again, so a click reopens settings")
    }

    /// Left and right step through the layouts, wrapping at either end.
    func testLeftAndRightCycleLayouts() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES", "-layout", "dashboard"]
        app.launch()
        let today = app.staticTexts["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))

        remote.press(.left)
        XCTAssertTrue(today.waitForNonExistence(timeout: 5), "left wraps from Dashboard to Night")

        remote.press(.right)
        XCTAssertTrue(today.waitForExistence(timeout: 5), "right wraps from Night back to Dashboard")

        remote.press(.right)
        XCTAssertTrue(today.waitForNonExistence(timeout: 5), "right moves on to Agenda")
    }
}

private extension XCUIElement {
    /// Focus moves after an animation, so wait for it.
    func waitForHasFocus(timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
