import XCTest

/// Drives the App Store app preview tour while `mise run art:preview` records the simulator's screen: the first-run
/// welcome, the library, saving a page from Safari's share sheet, reading it, and searching. Skipped unless
/// `SATCHEL_PREVIEW_DIR` is set. Writes `events.json` (the tour's start and end, in seconds since 1970) there, so the
/// script can trim the recording to just the tour.
final class StorePreviewTests: XCTestCase {
    private var directory: URL!
    private var events: [String: Double] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let path = ProcessInfo.processInfo.environment["SATCHEL_PREVIEW_DIR"], !path.isEmpty else {
            throw XCTSkip("set SATCHEL_PREVIEW_DIR (mise run art:preview)")
        }
        directory = URL(filePath: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func mark(_ name: String) {
        events[name] = Date().timeIntervalSince1970
    }

    @MainActor
    func testRecordAppPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SatchelResetOnboarding", "-SatchelDemoLibrary", "-SatchelDemoPreview"]
        let demoURL = URL(string: "https://cicorias.github.io/satchel-app/demo/plain-text.html")!

        // Before the tour: open the article once, so Safari's first-launch Start Page doesn't flash in the video.
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCUIDevice.shared.system.open(demoURL)
        _ = safari.staticTexts["The Quiet Revolution of Plain Text"].firstMatch.waitForExistence(timeout: 30)
        XCUIDevice.shared.press(.home)

        // 1. First run: the welcome page.
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Satchel"].waitForExistence(timeout: 15), "no onboarding")
        mark("start")
        sleep(2)
        app.swipeUp()
        sleep(1)
        app.buttons["onboarding-done"].tap()

        // 2. The library.
        let library = app.navigationBars["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        sleep(1)

        // 3. Save a page from Safari's share sheet.
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.system.open(demoURL)
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(
            safari.staticTexts["The Quiet Revolution of Plain Text"].firstMatch.waitForExistence(timeout: 30),
            "demo page didn't load")
        try openShareSheet(in: safari)
        let satchel = safari.cells.matching(NSPredicate(format: "label == 'Satchel'")).firstMatch
        if !satchel.waitForExistence(timeout: 5) { safari.collectionViews.firstMatch.swipeLeft() }
        XCTAssertTrue(satchel.waitForExistence(timeout: 5), "no Satchel in the share sheet")
        satchel.tap()
        let savePage = safari.buttons["save-page"]
        XCTAssertTrue(savePage.waitForExistence(timeout: 20), "no Save page")
        let tags = safari.textFields["tags"]
        tags.tap()
        XCTAssertTrue(safari.keyboards.firstMatch.waitForExistence(timeout: 5), "no keyboard for the tags")
        tags.typeText("writing. markdown\n")
        sleep(1)
        savePage.tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: savePage)
        wait(for: [closed], timeout: 20)

        // 4. Back in Satchel: the page is at the top. Read it.
        app.activate()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'The Quiet Revolution of Plain Text'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the saved page isn't in the library")
        sleep(1)
        row.tap()
        let report = app.descendants(matching: .any)["render-report"]
        let rendered = expectation(for: NSPredicate(format: "value CONTAINS 'scripts'"), evaluatedWith: report)
        wait(for: [rendered], timeout: 15)
        sleep(1)
        app.webViews.firstMatch.swipeUp()
        sleep(1)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 5. Search the library's text.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("sourdough")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'A Field Guide to Sourdough'")).firstMatch
                .waitForExistence(timeout: 5))
        sleep(2)
        mark("end")

        let data = try JSONSerialization.data(withJSONObject: events, options: [.sortedKeys])
        try data.write(to: directory.appending(path: "events.json"))
    }

    /// iOS 26+ Safari keeps Share in the page menu; older layouts have a toolbar Share button.
    @MainActor
    private func openShareSheet(in safari: XCUIApplication) throws {
        let share = safari.buttons.matching(NSPredicate(format: "label == 'Share' OR identifier == 'ShareButton'"))
            .firstMatch
        if share.waitForExistence(timeout: 2) && share.isHittable {
            share.tap()
            return
        }
        let menu = safari.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'MoreMenuButton'")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no page menu button")
        for _ in 0..<3 {
            menu.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
            if share.waitForExistence(timeout: 3) {
                share.tap()
                return
            }
        }
        XCTFail("no Share action\n\(safari.debugDescription)")
    }
}
