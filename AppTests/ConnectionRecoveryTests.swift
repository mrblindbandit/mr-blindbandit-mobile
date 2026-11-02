import XCTest
@testable import Blindbandit

final class ConnectionRecoveryTests: XCTestCase {
    func testKeyLookupTimeoutIsClassifiedAsTransientWithoutCallingItOffline() {
        let error = MessageKeyLookupError(underlying: URLError(.timedOut))
        XCTAssertTrue(CommsNetwork.isTransient(error))
        XCTAssertEqual(CommsNetwork.friendly(error), "Waiting for secure connection…")
    }

    func testKeyLookupNonTransientErrorIsNotRetried() {
        let error = MessageKeyLookupError(underlying: URLError(.badURL))
        XCTAssertFalse(CommsNetwork.isTransient(error))
    }

    func testLegacyQueuedMessagesDoNotAutomaticallyResend() throws {
        let old = #"{"id":"B23E590E-A0DD-4B06-8D23-23F609BD3F2A","handle":"person","body":"hello","created":0}"#
        let item = try JSONDecoder().decode(PendingMessage.self, from: Data(old.utf8))
        XCTAssertNotEqual(item.autoRetry, true)
    }

    func testPreflightRetryFlagSurvivesQueuePersistence() throws {
        var item = PendingMessage(handle: "person", body: "hello")
        item.autoRetry = true
        let decoded = try JSONDecoder().decode(PendingMessage.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.autoRetry, true)
        XCTAssertEqual(decoded.id, item.id)
    }
}
