import XCTest

/// Captures the three App Store screenshots on a clean simulator (`mise run art:screenshots`, which erases it first
/// and sets a clean status bar). Skipped unless `SATCHEL_SCREENSHOT_DIR` is set, so `test:ios-ui` never runs it.
/// The library comes from `-SatchelDemoLibrary` and the shared page from `site/demo/plain-text.html`.
final class StoreScreenshotTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let path = ProcessInfo.processInfo.environment["SATCHEL_SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("set SATCHEL_SCREENSHOT_DIR (mise run art:screenshots)")
        }
        directory = URL(filePath: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @MainActor
    func testCaptureStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SatchelDemoLibrary", "-SatchelOnboardingDone"]
        app.launch()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'The Quiet Revolution of Plain Text'"))
            .firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "no demo library\n\(app.debugDescription)")
        sleep(2)  // thumbnails
        try save("3-library")

        first.tap()
        let report = app.descendants(matching: .any)["render-report"]
        let rendered = expectation(for: NSPredicate(format: "value CONTAINS 'scripts'"), evaluatedWith: report)
        wait(for: [rendered], timeout: 15)
        sleep(1)
        try save("2-page")

        // The share sheet over the demo article in Safari.
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()
        // From the home screen, so Safari's status bar has no "◀ Satchel" back link.
        XCUIDevice.shared.press(.home)
        sleep(1)
        XCUIDevice.shared.system.open(URL(string: "https://cicorias.github.io/satchel-app/demo/plain-text.html")!)
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        let heading = safari.staticTexts["The Quiet Revolution of Plain Text"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 30), "demo page didn't load\n\(safari.debugDescription)")
        try openShareSheet(in: safari)
        // The share sheet's cell, not the "Satchel" link in the article's footer.
        let satchel = safari.cells.matching(NSPredicate(format: "label == 'Satchel'")).firstMatch
        if !satchel.waitForExistence(timeout: 5) { safari.collectionViews.firstMatch.swipeLeft() }
        XCTAssertTrue(satchel.waitForExistence(timeout: 5), "no Satchel in the share sheet")
        satchel.tap()
        let savePage = safari.buttons["save-page"]
        XCTAssertTrue(savePage.waitForExistence(timeout: 20), "no Save page\n\(safari.debugDescription)")
        let note = safari.descendants(matching: .any).matching(identifier: "note").firstMatch
        note.tap()
        note.typeText("Read again before the talk")
        let tags = safari.textFields["tags"]
        tags.tap()
        // Return closes the keyboard, so the whole sheet shows, with the tag suggestions.
        tags.typeText("writing. \n")
        sleep(1)
        try save("1-share")
        safari.buttons["Cancel"].firstMatch.tap()
    }

    @MainActor
    private func save(_ name: String) throws {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: directory.appending(path: "\(name).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
