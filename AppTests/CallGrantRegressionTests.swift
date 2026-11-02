import XCTest
@testable import Blindbandit

final class CallGrantRegressionTests: XCTestCase {
    private func response(_ fields: [String: Any]) throws -> BlindbanditCallResponse {
        try JSONDecoder().decode(BlindbanditCallResponse.self,
            from: JSONSerialization.data(withJSONObject: fields))
    }

    func testProductionAgoraAccountGrant() throws {
        let call = try response([
            "id": "call-1", "rtc_provider": "agora", "livekit": NSNull(),
            "rtc": ["app_id": "app", "channel": "room", "token": "account-token", "user_account": "user-1"]
        ])
        XCTAssertTrue(call.usesAgora)
        XCTAssertEqual(call.agora?.userAccount, "user-1")
        XCTAssertNil(call.livekit)
    }

    func testLegacyNumericAgoraGrant() throws {
        let call = try response([
            "id": "call-2", "provider": "agora",
            "agora": ["app_id": "app", "channel": "room", "token": "numeric-token", "uid": "42"]
        ])
        XCTAssertTrue(call.usesAgora)
        XCTAssertEqual(call.agora?.uid, 42)
        XCTAssertNil(call.agora?.userAccount)
    }

    func testAgoraTokenCannotBecomeLiveKitToken() {
        XCTAssertThrowsError(try response([
            "id": "broken", "rtc_provider": "agora", "token": "agora-token", "room": "room"
        ]))
    }

    func testFlatLiveKitRemainsSupported() throws {
        let call = try response(["id": "call-3", "token": "lk-token", "room": "room"])
        XCTAssertFalse(call.usesAgora)
        XCTAssertEqual(call.livekit?.token, "lk-token")
    }
}
