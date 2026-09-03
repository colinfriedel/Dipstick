import XCTest

/// Drives the detail screen tabs and logs a fill-up end-to-end. Needs both
/// backend services running (vehicle-service :8081, activity-service :8082).
final class ActivityScreensUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDetailTabsAndLogFillUp() throws {
        let app = XCUIApplication()
        app.launch()

        // Open the first vehicle.
        let firstVehicle = app.collectionViews.buttons.element(boundBy: 0)
        XCTAssertTrue(firstVehicle.waitForExistence(timeout: 5))
        firstVehicle.tap()

        // Fuel tab is the default.
        XCTAssertTrue(app.segmentedControls.buttons["Fuel"].waitForExistence(timeout: 3))
        attachScreenshot(app, name: "detail-fuel")

        // Log a fill-up.
        app.navigationBars.buttons["Log Fill-up"].tap()
        let odometer = app.textFields["Odometer"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 2))
        odometer.tap(); odometer.typeText("62050")
        app.textFields["Gallons"].tap(); app.textFields["Gallons"].typeText("10.2")
        app.textFields["Total cost"].tap(); app.textFields["Total cost"].typeText("37.15")
        app.navigationBars["Log Fill-up"].buttons["Save"].tap()

        // The new entry's date row should show up in the list.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'gal'")).firstMatch.waitForExistence(timeout: 5))

        // Maintenance tab.
        app.segmentedControls.buttons["Maintenance"].tap()
        attachScreenshot(app, name: "detail-maintenance")

        // Stats tab.
        app.segmentedControls.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["Average MPG"].waitForExistence(timeout: 3))
        attachScreenshot(app, name: "detail-stats")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
