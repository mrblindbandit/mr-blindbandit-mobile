import XCTest
@testable import Blindbandit

final class PushPreviewSanitizerTests: XCTestCase {
    func testRecognizesCallFrameKeyWithoutExposingIt() {
        let body = #"{"index":0,"call_id":"29904bbb-9578-4143-8dc3-7b4d1f1839d7","key":"UhXO7RcJV0n3Xk","nonce":"secret"}"#
        XCTAssertTrue(PushPreviewSanitizer.isCallControl(body))
        XCTAssertTrue(PushPreviewSanitizer.containsSensitiveJSON(body))
    }

    func testNormalMessageIsNotClassifiedAsSensitive() {
        XCTAssertFalse(PushPreviewSanitizer.containsSensitiveJSON("See you after the show"))
        XCTAssertFalse(PushPreviewSanitizer.isCallControl(#"{"body":"hello"}"#))
    }
}
