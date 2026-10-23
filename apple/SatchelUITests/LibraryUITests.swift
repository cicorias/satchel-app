import XCTest

/// Ticket 10: the library's search, filters, detail view, export, and delete, on items the app seeds when launched
/// with `-SatchelSeedLibrary` (Debug builds; see `UITestSeed`).
final class LibraryUITests: XCTestCase {
    private let pageTitle = "Satchel seeded page"
    private let linkTitle = "Satchel seeded link"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Remote images off, so the detail view must load nothing from the network.
        app.launchArguments = ["-SatchelSeedLibrary", "-SatchelRemoteImagesOff", "-SatchelOnboardingDone"]
        app.launch()
        XCTAssertTrue(row(pageTitle, in: app).waitForExistence(timeout: 10), "no seeded page\n\(app.debugDescription)")
        return app
    }

    @MainActor
    private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    @MainActor
    func testSearchAndFilters() throws {
        var app = launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no search field")
        search.tap()
        search.typeText("seeded page")
        XCTAssertTrue(row(pageTitle, in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(row(linkTitle, in: app).exists, "the search matched the link too")

        // Body text is searched too: only the page's Markdown has "footnote".
        search.buttons["Clear text"].tap()
        search.typeText("footnote")
        XCTAssertTrue(row(pageTitle, in: app).waitForExistence(timeout: 5), "body text isn't searched")
        XCTAssertFalse(row(linkTitle, in: app).exists)

        // Start over without the search (iOS 27's search bar has no Cancel button to leave it).
        app.terminate()
        app = launch()
        app.buttons["filter"].tap()
        app.buttons["Links"].tap()
        XCTAssertTrue(row(linkTitle, in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(row(pageTitle, in: app).exists, "the Links filter shows pages")
        app.buttons["filter"].tap()
        app.buttons["All"].tap()
    }

    /// The page's body tries an inline script, an event handler, and two remote images; none may run or load.
    @MainActor
    func testDetailRendersWithoutScriptsOrRemoteLoads() throws {
        let app = launch()
        row(pageTitle, in: app).tap()
        let webView = app.webViews["markdown-view"]
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "no rendered page")
        XCTAssertTrue(
            webView.staticTexts.matching(NSPredicate(format: "label CONTAINS 'A page with a'")).firstMatch
                .waitForExistence(timeout: 10), "the body didn't render\n\(webView.debugDescription)")
        XCTAssertTrue(webView.links["link to Example"].exists, "links aren't rendered")

        let report = app.descendants(matching: .any)["render-report"]
        let rendered = expectation(
            for: NSPredicate(format: "value == 'scripts 0, handlers 0, resources 0, violations 0, blocked 2'"),
            evaluatedWith: report)
        wait(for: [rendered], timeout: 10)
    }

    @MainActor
    func testExportOffersTheMarkdownFile() throws {
        let app = launch()
        row(pageTitle, in: app).tap()
        let export = app.buttons["export"]
        XCTAssertTrue(export.waitForExistence(timeout: 10), "no Export button")
        export.tap()
        let sheet = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'ActivityListView' OR label CONTAINS 'Save to Files'")
        ).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no share sheet\n\(app.debugDescription)")
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", pageTitle))
            .firstMatch
        XCTAssertTrue(file.exists, "the share sheet doesn't name the file\n\(app.debugDescription)")
    }

    @MainActor
    func testDeleteRemovesTheItem() throws {
        let app = launch()
        let link = row(linkTitle, in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: link)
        wait(for: [gone], timeout: 10)
    }
}
