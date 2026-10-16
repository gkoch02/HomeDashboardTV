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

        let demo = app.buttons["Demo data"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
        XCTAssertTrue(focused.firstMatch.waitForExistence(timeout: 5), "something in the panel has focus")

        // Down to the address row (a Pi on the LAN may have taken first focus), then right.
        for _ in 0..<8 where !demo.hasFocus {
            let onAddressRow = app.textFields.firstMatch.hasFocus || app.buttons["Connect"].hasFocus
            remote.press(onAddressRow ? .right : .down)
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
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "a click opens settings")
        XCTAssertTrue(done.hasFocus, "focus lands in the panel")

        remote.press(.menu)
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Menu closes settings")

        remote.press(.select)
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the dashboard has focus again, so a click reopens settings")
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
