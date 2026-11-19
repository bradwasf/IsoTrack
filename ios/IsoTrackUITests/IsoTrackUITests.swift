import XCTest

/// End-to-end smoke tests. They launch with `--uitest-reset`, which points
/// the app at a throwaway file — real data is never touched.
final class IsoTrackUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        // A failed landscape test stops before it can rotate back.
        XCUIDevice.shared.orientation = .portrait
    }

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset"]
        app.launch()
        return app
    }

    private func launchDemo(tab: String? = nil, schedule: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [schedule ? "--demo-schedule" : "--demo-data"] + (tab.map { ["--tab", $0] } ?? [])
        app.launch()
        return app
    }

    /// Attaches a screenshot of every display. iPhone Duo has two, and which
    /// one is live depends on whether the phone is open.
    private func snap(_ name: String, _ app: XCUIApplication) {
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "\(name)-screen\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testOnboardingThenFirstDose() throws {
        let app = launchFresh()
        snap("01-welcome", app)

        // Mid-course path shows the "taken so far" field; a new course doesn't.
        app.buttons["I'm already mid-course"].tap()
        XCTAssertTrue(app.textFields["prior-field"].waitForExistence(timeout: 3))
        app.buttons["Back"].tap()
        app.buttons["Start a new course"].tap()
        let weight = app.textFields["weight-field"]
        XCTAssertTrue(weight.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["prior-field"].exists)

        let start = app.buttons["Start tracking"]
        XCTAssertFalse(start.isEnabled, "needs a weight first")
        weight.tap()
        weight.typeText("165")
        snap("02-setup", app)
        app.swipeUp()
        XCTAssertTrue(start.isEnabled)
        start.tap()

        // First dose goes through the form because there's no "usual" yet.
        let first = app.buttons["log-first"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        snap("03-today-empty", app)
        first.tap()
        XCTAssertTrue(app.buttons["20 mg"].waitForExistence(timeout: 3))
        app.buttons["20 mg"].tap()
        snap("04-dose-sheet", app)
        app.buttons["add-dose"].tap()

        XCTAssertTrue(app.staticTexts["Logged today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["20 mg · 1 × 20 mg"].exists)
        snap("05-today-logged", app)
    }

    func testOneTapLogsTheUsualDose() throws {
        let app = launchDemo()
        let log = app.buttons["log-usual"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        XCTAssertTrue(log.isHittable, "the log button must be on screen without scrolling")
        log.tap()
        XCTAssertTrue(app.staticTexts["Logged today"].waitForExistence(timeout: 5))
        XCTAssertFalse(log.exists)
        snap("06-demo-logged", app)
    }

    func testTickingOffScheduledDoses() throws {
        let app = launchDemo(schedule: true)
        // The tick boxes are toggles, so XCUITest sees them as switches.
        let first = app.switches["slot-0"]
        let second = app.switches["slot-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable, "the tick boxes must be on screen without scrolling")
        XCTAssertEqual(first.value as? String, "not taken")
        XCTAssertFalse(app.buttons["log-usual"].exists, "the schedule replaces the one-tap button")
        snap("15-schedule-empty", app)

        first.tap()
        XCTAssertTrue(app.staticTexts["1 of 2 taken"].waitForExistence(timeout: 3))
        XCTAssertEqual(first.value as? String, "taken")
        snap("16-schedule-half", app)

        second.tap()
        XCTAssertTrue(app.staticTexts["All done for today"].waitForExistence(timeout: 3))
        snap("17-schedule-done", app)

        // Unticking takes the dose back off.
        second.tap()
        XCTAssertTrue(app.staticTexts["1 of 2 taken"].waitForExistence(timeout: 3))

        // The day sheet shows the same tick boxes, plus room for an extra dose.
        app.buttons["Other dose"].tap()
        XCTAssertTrue(app.staticTexts["Scheduled"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Add an extra dose"].exists)
        snap("21-schedule-day-sheet", app)
    }

    func testSettingUpAScheduleFromToday() throws {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["split-dose"].waitForExistence(timeout: 5))
        app.buttons["split-dose"].tap()
        XCTAssertTrue(app.navigationBars["Dose schedule"].waitForExistence(timeout: 3))
        snap("18-schedule-setup-empty", app)

        // First dose: the suggested name and the usual pills, as offered.
        app.buttons["add-slot"].tap()
        XCTAssertTrue(app.navigationBars["New dose"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["slot-label"].value as? String, "First meal")
        snap("19-slot-editor", app)
        app.buttons["save-slot"].tap()

        // Second dose: a different strength.
        app.buttons["add-slot"].tap()
        XCTAssertTrue(app.navigationBars["New dose"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["slot-label"].value as? String, "Second meal")
        app.buttons["30 mg"].tap()
        app.buttons["save-slot"].tap()
        snap("20-schedule-two-doses", app)
        app.buttons["Done"].tap()

        // Today now shows a tick box for each.
        XCTAssertTrue(app.switches["slot-1"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["log-usual"].exists)
        app.switches["slot-0"].tap()
        XCTAssertTrue(app.staticTexts["1 of 2 taken"].waitForExistence(timeout: 3))
    }

    func testTabsAndSheets() throws {
        let app = launchDemo(tab: "care")
        XCTAssertTrue(app.buttons["Check in"].waitForExistence(timeout: 5))
        snap("07-care", app)
        app.buttons["Check in"].tap()
        XCTAssertTrue(app.navigationBars["Check-in"].waitForExistence(timeout: 3))
        snap("08-check-in", app)
        app.buttons["Cancel"].tap()

        app.buttons["Add appointment"].tap()
        XCTAssertTrue(app.navigationBars["New appointment"].waitForExistence(timeout: 3))
        snap("09-appointment", app)
        app.buttons["Cancel"].tap()

        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        snap("10-settings", app)
        app.buttons["Cancel"].tap()
    }

    func testJourneyCalendarOpensADay() throws {
        let app = launchDemo(tab: "journey")
        XCTAssertTrue(app.staticTexts["Milestones"].waitForExistence(timeout: 5))
        snap("12-journey", app)

        // Step back a month and forward again.
        let previous = app.buttons["Previous month"]
        if !previous.isHittable { app.swipeUp() }
        XCTAssertTrue(previous.isHittable)
        XCTAssertFalse(app.buttons["Next month"].isEnabled, "can't go past the current month")
        previous.tap()
        XCTAssertTrue(app.buttons["Next month"].isEnabled)
        snap("13-journey-previous-month", app)
        app.buttons["Next month"].tap()

        // Yesterday is logged in the demo data; its sheet lists the dose.
        app.buttons["Recent doses"].firstMatch.tap()
        XCTAssertTrue(app.buttons["add-dose"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Logged"].exists)
        snap("14-day-sheet", app)
    }

    func testLandscapeKeepsTheLogButtonReachable() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchDemo()
        let log = app.buttons["log-usual"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        snap("11-landscape", app)
        if !log.isHittable { app.swipeUp() }
        XCTAssertTrue(log.isHittable)
    }
}
