import XCTest

/// Ticket 12: first-run onboarding, and the "Load remote images" switch that the detail view follows.
final class SettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingShowsOnFirstRunOnly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SatchelResetOnboarding"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Satchel"].waitForExistence(timeout: 10), "no onboarding")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Apps → Safari → Extensions → Satchel'"))
                .firstMatch.exists, "no Safari extension steps")
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-icloud"].exists, "no iCloud status")
        app.buttons["onboarding-done"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5), "onboarding didn't close")

        // Dismissed for good: the next launch goes straight to the library.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Welcome to Satchel"].exists, "onboarding showed again")
    }

    @MainActor
    func testRemoteImagesSettingReachesTheDetailView() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SatchelSeedLibrary", "-SatchelOnboardingDone"]
        app.launch()

        setRemoteImages(false, in: app)
        XCTAssertEqual(blockedImages(in: app), "blocked 2")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        setRemoteImages(true, in: app)
        XCTAssertEqual(blockedImages(in: app), "blocked 0")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        setRemoteImages(false, in: app)
    }

    @MainActor
    private func setRemoteImages(_ on: Bool, in app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let toggle = app.switches["remote-images"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Load Remote Images switch\n\(app.debugDescription)")
        if (toggle.value as? String == "1") != on {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let set = expectation(for: NSPredicate(format: "value == %@", on ? "1" : "0"), evaluatedWith: toggle)
        wait(for: [set], timeout: 5)
        XCTAssertTrue(
            app.staticTexts["settings-sync-status"].exists
                || app.descendants(matching: .any)["settings-sync-status"].exists)
        app.buttons["Done"].tap()
    }

    /// Opens the seeded page and returns the "blocked N" part of its render report.
    @MainActor
    private func blockedImages(in app: XCUIApplication) -> String {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Satchel seeded page'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no seeded page")
        row.tap()
        let report = app.descendants(matching: .any)["render-report"]
        let rendered = expectation(for: NSPredicate(format: "value CONTAINS 'blocked'"), evaluatedWith: report)
        wait(for: [rendered], timeout: 10)
        // Rendering finishes before the report's last field settles; read it once it's in.
        return (report.value as? String).flatMap { $0.components(separatedBy: ", ").last } ?? ""
    }
}
