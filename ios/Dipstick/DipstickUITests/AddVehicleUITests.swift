import XCTest

/// End-to-end flow test: add a vehicle through the UI and confirm it lands in the
/// list. Requires the backend (vehicle-service on localhost:8081) to be running,
/// so it's kept out of the plain `testExample` launch check.
final class AddVehicleUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddVehicleAppearsInList() throws {
        let app = XCUIApplication()
        app.launch()

        // A unique name so repeated runs don't collide.
        let name = "UITest Car \(Int(Date().timeIntervalSince1970))"

        app.navigationBars["Vehicles"].buttons["Add Vehicle"].tap()

        let nameField = app.textFields["e.g. Daily Driver"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText(name)

        app.textFields["Year"].tap()
        app.textFields["Year"].typeText("2020")

        app.textFields["Make"].tap()
        app.textFields["Make"].typeText("Subaru")

        app.textFields["Current mileage"].tap()
        app.textFields["Current mileage"].typeText("31000")

        app.navigationBars["New Vehicle"].buttons["Save"].tap()

        // Back on the list, the new row should exist.
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }
}
