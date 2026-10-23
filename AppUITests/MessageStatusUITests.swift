import XCTest

/// The delivery status must be its own VoiceOver element directly below an outgoing message.
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
}
