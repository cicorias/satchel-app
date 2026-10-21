import XCTest

/// Drives the system Settings and Safari apps to exercise the Safari Web Extension end to end
/// (ADR-0005 addendum). Run with `mise run test:ios-ui`; tests run in name order, and
/// `testA…` enables the extension that `testB…` relies on.
final class SafariExtensionUITests: XCTestCase {
    private let extensionName = "Satchel"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Settings → Apps → Safari → Extensions → Satchel → Allow Extension.
    @MainActor
    func testA_EnableSafariExtension() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()

        try tap(["Apps"], in: settings)
        try tap(["Safari"], in: settings)
        try tap(["Extensions"], in: settings)
        try tap([extensionName], in: settings)

        let toggle = settings.switches.matching(NSPredicate(format: "label CONTAINS[c] 'Allow'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Allow Extension switch\n\(settings.debugDescription)")
        if (toggle.value as? String) != "1" {
            // Tap the knob side: a plain tap() on the switch's center doesn't toggle it on iOS 26+.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        }
        let on = expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: toggle)
        wait(for: [on], timeout: 5)
        snapshot(settings, "extension-enabled")
    }

    /// Opens a page, then the Satchel popup from Safari's page menu, and checks it shows the tab's title.
    @MainActor
    func testB_PopupShowsCurrentTab() throws {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()
        XCUIDevice.shared.system.open(URL(string: "https://example.com")!)
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))

        // On a Reader-capable page the first tap on the page-menu button can toggle Reader instead of
        // opening the menu, so tap its left (menu) side until the extension's entry shows up.
        let menuButton = safari.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'MoreMenuButton'"))
            .firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10), "no page menu button")
        let item = safari.descendants(matching: .any).matching(NSPredicate(format: "label == %@", extensionName))
            .firstMatch
        var found = false
        for _ in 0..<3 where !found {
            menuButton.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
            found = item.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(found, "no \(extensionName) entry in the page menu\n\(safari.debugDescription)")
        item.tap()

        // First use may ask for website access; grant it for this run.
        for label in ["Allow for One Day", "Allow", "Always Allow"]
        where safari.buttons[label].waitForExistence(timeout: 1) {
            safari.buttons[label].tap()
            break
        }

        let popup = safari.webViews[extensionName]
        XCTAssertTrue(popup.waitForExistence(timeout: 10), "popup didn't open\n\(safari.debugDescription)")
        XCTAssertTrue(
            popup.staticTexts["Example Domain"].waitForExistence(timeout: 10), "popup didn't show the tab title")
        XCTAssertTrue(popup.buttons["Save link"].exists)
        snapshot(safari, "popup")
    }

    // MARK: - Helpers

    /// Taps the first element whose label (or identifier) matches one of `labels`, swiping up to find it.
    @MainActor
    private func tap(
        _ labels: [String], in app: XCUIApplication, swipe: Bool = true, file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for _ in 0..<(swipe ? 8 : 3) {
            for label in labels {
                // Exact label first, then a label/identifier prefix (Safari decorates both with state,
                // e.g. "Page Menu, Reader Available" / "MoreMenuButton?availabilityIndicator=reader").
                let predicate = NSPredicate(
                    format: "label == %@ OR identifier == %@ OR label BEGINSWITH %@ OR identifier BEGINSWITH %@",
                    label, label, label + ",", label + "?")
                for query in [app.cells, app.buttons, app.staticTexts] {
                    let element = query.matching(predicate).firstMatch
                    if element.exists && element.isHittable {
                        element.tap()
                        return
                    }
                }
            }
            if swipe { app.swipeUp() } else { sleep(1) }
        }
        snapshot(app, "missing-\(labels.joined(separator: "-"))")
        XCTFail("couldn't find \(labels)\n\(app.debugDescription)", file: file, line: line)
        throw XCTSkip("navigation failed")
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
