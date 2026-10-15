import XCTest

/// App Store screenshots, taken from the running app by `make screenshots`.
/// Skipped unless that target sets RINGTONE_SCREENSHOTS, so a plain test run never
/// depends on the generated demo track.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["RINGTONE_SCREENSHOTS"] == "1", "Run through `make screenshots`.")
    }

    @MainActor
    func testStoreScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        let file = try XCTUnwrap(env["RINGTONE_DEMO_FILE"], "Path of the demo track")
        let app = XCUIApplication()
        app.launchArguments = ["-openFile", file]
        if let language = env["RINGTONE_SHOT_LANG"] {
            let locale = language == "en" ? "en_US" : "zh_TW"
            app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        }
        app.launch()

        let overview = app.descendants(matching: .any)["overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 15))
        // Centre the clip on the first chorus (60–90 s of the 180 s demo track),
        // so the shot shows a loud stretch selected against quieter verses.
        // The element includes the strip's 20 pt side padding.
        let inset: CGFloat = 20
        let width = overview.frame.width
        let dx = (inset + 75.0 / 180.0 * (width - inset * 2)) / width
        overview.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
        sleep(1)
        shot("01-editor")

        app.buttons["play"].tap()
        sleep(3)
        shot("02-preview")
        app.buttons["play"].tap()

        app.buttons["makeRingtone"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        shot("03-name")

        // Second button is "Make"; the first is the cancel action.
        alert.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 15))
        sleep(2)
        shot("04-share")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
