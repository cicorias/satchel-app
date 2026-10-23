import XCTest

/// Phase 3 ticket 06: share a page from Safari to the Satchel Share Extension, save it as a link, and find it in
/// the library. CloudKit isn't signed in on the simulator, so the item shows as not synced yet.
final class ShareExtensionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSharingALinkSavesItToTheLibrary() throws {
        // A unique query parameter makes a new item each run (only tracking parameters are stripped).
        let marker = "satchel-ui-\(Int(Date().timeIntervalSince1970))"
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()
        XCUIDevice.shared.system.open(URL(string: "https://example.com/?run=\(marker)")!)
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        let heading = safari.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Example Domain'")
        )
        .firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 20), "page didn't load\n\(safari.debugDescription)")

        try openShareSheet(in: safari)
        let satchel = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Satchel' OR label == 'Save to Satchel'")).firstMatch
        if !satchel.waitForExistence(timeout: 5) {
            // Not in the first row of app icons: scroll the row.
            safari.collectionViews.firstMatch.swipeLeft()
        }
        XCTAssertTrue(satchel.waitForExistence(timeout: 5), "no Satchel in the share sheet\n\(safari.debugDescription)")
        satchel.tap()

        // The extension's sheet runs in its own process; XCUITest reaches it through Safari's hierarchy.
        let save = safari.buttons["save-link"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no Save link button\n\(safari.debugDescription)")
        save.tap()
        // The sheet confirms and closes itself; an error would keep it open with a message.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: save)
        wait(for: [gone], timeout: 20)

        let app = XCUIApplication(bundleIdentifier: "com.cedarlogic.satchel")
        app.terminate()
        app.launch()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Example Domain' OR label CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "saved link not in the library\n\(app.debugDescription)")
        snapshot(app, "library-after-share")
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
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no page menu button\n\(safari.debugDescription)")
        for _ in 0..<3 {
            // The left side of the button opens the menu (the right side can toggle Reader).
            menu.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
            if share.waitForExistence(timeout: 3) {
                share.tap()
                return
            }
        }
        snapshot(safari, "no-share")
        XCTFail("no Share action\n\(safari.debugDescription)")
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
