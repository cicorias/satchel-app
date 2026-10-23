import CryptoKit
import XCTest

/// Phase 3 tickets 06 and 09: share a page from Safari to the Satchel Share Extension, save it as a link or a page,
/// and find it in the library. CloudKit isn't signed in on the simulator, so items show as not synced yet.
final class ShareExtensionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSharingALinkSavesItToTheLibrary() throws {
        // A unique query parameter makes a new item each run (only tracking parameters are stripped).
        let marker = "satchel-ui-\(Int(Date().timeIntervalSince1970))"
        let safari = try shareToSatchel("https://example.com/?run=\(marker)")

        // The extension's sheet runs in its own process; XCUITest reaches it through Safari's hierarchy.
        let save = safari.buttons["save-link"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no Save link button\n\(safari.debugDescription)")
        save.tap()
        waitForSheetToClose(save)

        let app = XCUIApplication(bundleIdentifier: "com.cedarlogic.satchel")
        app.terminate()
        app.launch()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Example Domain' OR label CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "saved link not in the library\n\(app.debugDescription)")
        snapshot(app, "library-after-share")
    }

    /// Ticket 09: from Safari the sheet offers Save page (the preprocessing script captured the page). Saves it with
    /// tags, then shares it again and keeps the saved copy when asked to replace it (FR-6).
    @MainActor
    func testSharingAPageFromSafariWithTags() throws {
        let url = "https://example.com/?run=satchel-share-page-\(Int(Date().timeIntervalSince1970))"
        var safari = try shareToSatchel(url)
        let savePage = safari.buttons["save-page"]
        XCTAssertTrue(savePage.waitForExistence(timeout: 15), "no Save page button\n\(safari.debugDescription)")
        let tags = safari.textFields["tags"]
        XCTAssertTrue(tags.exists, "no tags field")
        tags.tap()
        tags.typeText("ui-test. share")
        savePage.tap()
        waitForSheetToClose(savePage)

        // Share the same page again: a page over a saved page asks first.
        safari = try shareToSatchel(url)
        XCTAssertTrue(safari.buttons["save-page"].waitForExistence(timeout: 15), "no Save page on the re-share")
        safari.buttons["save-page"].tap()
        let keep = safari.buttons["Keep saved copy"]
        XCTAssertTrue(keep.waitForExistence(timeout: 10), "no Replace saved copy? prompt\n\(safari.debugDescription)")
        snapshot(safari, "replace-prompt")
        keep.tap()
        waitForSheetToClose(safari.buttons["save-page"])

        // The item's ID is "u_" + the first 32 hex digits of SHA-256(normalized URL); this URL is already normalized.
        let digest = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication(bundleIdentifier: "com.cedarlogic.satchel")
        app.terminate()
        app.launch()
        let row = app.descendants(matching: .any)["item-u_\(digest.prefix(32))"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "saved page not in the library\n\(app.debugDescription)")
        XCTAssertTrue(row.label.contains("page"), "the row isn't a page: \(row.label)")
        snapshot(app, "library-after-share-page")
    }

    /// Opens `url` in Safari, opens the share sheet, and picks Satchel. Returns Safari, which hosts the sheet.
    @MainActor
    private func shareToSatchel(_ url: String) throws -> XCUIApplication {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()
        XCUIDevice.shared.system.open(URL(string: url)!)
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
        return safari
    }

    /// The sheet confirms and closes itself; an error would keep it open with a message.
    @MainActor
    private func waitForSheetToClose(_ button: XCUIElement) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: button)
        wait(for: [gone], timeout: 20)
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
