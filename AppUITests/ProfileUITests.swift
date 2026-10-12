import XCTest

/// Signs in with the reviewer account (CI secrets REVIEWER_EMAIL / REVIEWER_PASSWORD, passed as
/// TEST_RUNNER_ env vars), walks first-launch onboarding, opens Profile and checks it finishes loading.
final class ProfileUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testProfileLoadsAfterSignIn() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["REVIEWER_EMAIL"], let password = env["REVIEWER_PASSWORD"], !email.isEmpty, !password.isEmpty else {
            throw XCTSkip("Reviewer credentials are not configured")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipAppLock"]
        app.launch()

        let emailEntry = app.buttons["Continue with email"]
        if emailEntry.waitForExistence(timeout: 30) {
            emailEntry.tap()
            let emailField = app.textFields["Email address"]
            XCTAssertTrue(emailField.waitForExistence(timeout: 10))
            emailField.tap(); emailField.typeText(email)
            let passwordField = app.secureTextFields.firstMatch
            passwordField.tap(); passwordField.typeText(password)
            app.buttons["Sign in"].firstMatch.tap()
        }

        // First-launch onboarding: skip every permission and the username step.
        for _ in 0..<6 {
            if app.buttons["Skip for now"].waitForExistence(timeout: 3) { app.buttons["Skip for now"].tap(); break }
            if app.buttons["Skip"].exists { app.buttons["Skip"].tap() }
        }
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            alert.buttons.element(boundBy: 0).tap(); return true
        }

        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 45), "Did not reach the main tabs after sign-in")
        more.tap()
        app.buttons["Profile & account"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Username"].firstMatch.waitForExistence(timeout: 10))

        // The fix: loading must end within the timeout (loaded or an error with Retry), never spin forever.
        let loading = app.staticTexts["Updating profile details"]
        let deadline = Date().addingTimeInterval(20)
        while loading.exists && Date() < deadline { sleep(1) }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Profile"; shot.lifetime = .keepAlways
        add(shot)
        XCTAssertFalse(loading.exists, "Profile is still loading after 20 seconds")
    }
}
