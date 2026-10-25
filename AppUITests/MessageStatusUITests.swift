import XCTest

/// Delivery status must be its own VoiceOver element under an outgoing message (Messenger/WhatsApp parity).
final class MessageStatusUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStatusElementUnderOutgoingMessage() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMessageStatus", "-UITestSkipAppLock"]
        app.launch()

        let message = app.descendants(matching: .any)["outgoing-message"]
        let status = app.descendants(matching: .any)["message-status"]
        XCTAssertTrue(message.waitForExistence(timeout: 20))
        XCTAssertTrue(status.exists, "No separate status element under the outgoing message")
        XCTAssertTrue(status.label.hasPrefix("Delivered "), "Unexpected status: \(status.label)")
        XCTAssertNotEqual(message.label, status.label)
        XCTAssertFalse(message.label.contains("Delivered"), "Status is merged into the bubble")
        XCTAssertGreaterThanOrEqual(status.frame.minY, message.frame.maxY - 1, "Status is not below the message")
        XCTAssertTrue(app.descendants(matching: .any)["message-time"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["typing-indicator"].exists, "Typing indicator is not its own element")
    }

    /// Empty-inbox harness: must NOT show native "Couldn't load" when there is no loadError.
    func testEmptyInboxDoesNotShowCouldntLoad() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMessagesEmpty", "-UITestSkipAppLock"]
        app.launch()

        let empty = app.descendants(matching: .any)["messages-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 20), "Empty inbox fixture missing")
        XCTAssertFalse(app.staticTexts["Couldn't load"].exists, "Empty inbox must not show Couldn't load")
    }

    /// Dial-tone harness exposes the US dial tone accessibility name used for outgoing ringback.
    func testOutgoingDialToneNameIsUSDialTone() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestDialTone", "-UITestSkipAppLock"]
        app.launch()

        let tone = app.descendants(matching: .any)["outgoing-dial-tone"]
        XCTAssertTrue(tone.waitForExistence(timeout: 20))
        XCTAssertEqual(tone.label, "US dial tone")
    }
}
