import XCTest
import CallKit
@testable import Blindbandit

@MainActor
final class PushRouteTests: XCTestCase {
    func testConversationIDWithHandle() {
        let route = PushRoute.parse(["type": "message", "conversation_id": "c1", "from_handle": "@Kaeleb"])
        XCTAssertEqual(route, .conversation(id: "c1", handle: "kaeleb"))
    }

    func testLiveServerDeepLinkUsesC() {
        XCTAssertEqual(PushRoute.parse(["deep_link": "/mobile/messages/?c=abc"]), .conversation(id: "abc", handle: nil))
    }

    func testContractDeepLinkUsesID() {
        XCTAssertEqual(PushRoute.parse(["deep_link": "/mobile/messages/?id=xyz", "from_handle": "sam"]),
                       .conversation(id: "xyz", handle: "sam"))
    }

    func testFromHandleFallbackWhenNoID() {
        XCTAssertEqual(PushRoute.parse(["type": "message", "from_handle": "sam"]), .conversation(id: nil, handle: "sam"))
    }

    func testGroupAndCall() {
        XCTAssertEqual(PushRoute.parse(["type": "group_message", "group_id": "g1"]), .group(id: "g1"))
        XCTAssertEqual(PushRoute.parse(["type": "call", "call_id": "k1"]), .call(id: "k1"))
        XCTAssertEqual(PushRoute.parse(["deep_link": "/mobile/calls/?id=k2"]), .call(id: "k2"))
        XCTAssertEqual(PushRoute.parse(["deep_link": "/mobile/groups/?id=g2"]), .group(id: "g2"))
    }

    func testEmptyPayloadIsNil() {
        XCTAssertNil(PushRoute.parse([:]))
    }

    func testVoIPPayload() {
        let parsed = CallKitManager.parseVoIP(["type": "call", "call_id": "k9", "kind": "video", "from_handle": "sam", "from_name": "Sam Lee"])
        XCTAssertEqual(parsed.type, "call")
        XCTAssertEqual(parsed.call?.id, "k9")
        XCTAssertEqual(parsed.call?.from_name, "Sam Lee")
        XCTAssertTrue(parsed.call?.isVideo ?? false)
        XCTAssertNil(CallKitManager.parseVoIP(["type": "call"]).call)
    }

    func testCallerIdentityNeverUsesIDs() {
        let one = CallKitManager.identity(handle: "sam", name: "Sam Lee", groupID: nil, groupName: nil)
        XCTAssertEqual(one.handle, "@sam")
        XCTAssertEqual(one.name, "Sam Lee")
        let noName = CallKitManager.identity(handle: "sam", name: "", groupID: nil, groupName: nil)
        XCTAssertEqual(noName.name, "@sam")
        let group = CallKitManager.identity(handle: "", name: "", groupID: "g1", groupName: "Family", memberCount: 3)
        XCTAssertEqual(group.name, "Family (3 people)")
        XCTAssertEqual(CallKitManager.groupID(forHandle: group.handle), "g1")
    }

    func testStatusStamps() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))
        let locale = Locale(identifier: "en_US")
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12)))
        let today = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 5, minute: 8)))
        let yesterday = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 21, minute: 14)))
        XCTAssertEqual(MessageStatus.stamp(today.timeIntervalSince1970 * 1000, now: now, calendar: cal, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " "), "5:08 AM")
        XCTAssertEqual(MessageStatus.stamp(yesterday.timeIntervalSince1970 * 1000, now: now, calendar: cal, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " "), "Yesterday 9:14 PM")
    }

    func testMuteTimersExpire() {
        let now = Date()
        let map: [String: Double] = ["a": 0, "b": now.addingTimeInterval(60).timeIntervalSince1970, "c": now.addingTimeInterval(-1).timeIntervalSince1970]
        XCTAssertEqual(LocalComms.activeMutes(map, now: now), ["a", "b"])
    }

    func testGroupDetailNestedWithIntVerified() throws {
        let json = #"{"group":{"id":"g1","name":"Crew","member_count":2,"my_role":"Admin"},"members":[{"profile_id":"p1","handle":"a","verified":1},{"profile_id":"p2","handle":"b","verified":"0"}]}"#
        let d = try JSONDecoder().decode(BlindbanditGroupDetail.self, from: Data(json.utf8))
        XCTAssertEqual(d.members.count, 2)
        XCTAssertTrue(d.members[0].verified)
        XCTAssertFalse(d.members[1].verified)
    }

    func testIncomingEmptyItems() throws {
        let d = try JSONDecoder().decode(ItemsPayload<BlindbanditIncomingCall>.self, from: Data(#"{"items":[]}"#.utf8))
        XCTAssertTrue(d.items.isEmpty)
    }

    func testRecentsHandleMapsBack() {
        XCTAssertEqual(CallKitManager.recentsHandle("@bbfoundation"), "bbfoundation")
        XCTAssertEqual(CallKitManager.recentsHandle("bbfoundation"), "bbfoundation")
    }

    func testEndReasonForRecents() {
        XCTAssertEqual(CallKitManager.endReason(wasConnected: true), .remoteEnded)
        XCTAssertEqual(CallKitManager.endReason(wasConnected: false), .unanswered)
    }

    func testPushRouteShapes() {
        let c = "ac463c39-06e0-449e-99a5-2056158bbd41"
        XCTAssertEqual(PushRoute.parse(["conversationId": c]), .conversation(id: c, handle: nil))
        XCTAssertEqual(PushRoute.parse(["c": c, "sender_handle": "bbfoundation"]), .conversation(id: c, handle: "bbfoundation"))
        XCTAssertEqual(PushRoute.parse(["thread_id": c]), .conversation(id: c, handle: nil))
        XCTAssertEqual(PushRoute.parse(["aps": ["thread-id": c, "alert": ["body": "hi"]]]), .conversation(id: c, handle: nil))
        XCTAssertEqual(PushRoute.parse(["data": ["conversation_id": c]]), .conversation(id: c, handle: nil))
        XCTAssertEqual(PushRoute.parse(["payload": ["link": "/mobile/messages/?id=\(c)"]]), .conversation(id: c, handle: nil))
        XCTAssertEqual(PushRoute.parse(["url": "https://mrblindbandit.net/mobile/messages/?c=\(c)"]), .conversation(id: c, handle: nil))
        XCTAssertEqual(PushRoute.parse(["link": "https://mrblindbandit.net/mobile/groups/?id=g9"]), .group(id: "g9"))
        XCTAssertEqual(PushRoute.parse(["deep_link": "/mobile/calls/?id=k9"]), .call(id: "k9"))
        XCTAssertEqual(PushRoute.parse(["data": ["group_id": "g1"]]), .group(id: "g1"))
        XCTAssertEqual(PushRoute.parse(["data": ["call_id": "k1", "type": "call"]]), .call(id: "k1"))
        XCTAssertEqual(PushRoute.parse(["handle": "@bbfoundation", "aps": ["alert": "New message"]]), .conversation(id: nil, handle: "bbfoundation"))
        XCTAssertEqual(PushRoute.parse(["data": "{\"conversation_id\":\"\(c)\"}"]), .conversation(id: c, handle: nil))
        XCTAssertNil(PushRoute.parse(["aps": ["alert": "hello"]]))
        XCTAssertFalse(PushRoute.keySummary(["data": ["conversation_id": c]]).contains(c))
    }

    func testStatusCaptionsIncludeTime() {
        let now = Date()
        let ms = now.timeIntervalSince1970 * 1000
        XCTAssertTrue(MessageStatus.caption(sent: ms, delivered: nil, read: nil, showRead: true, now: now).hasPrefix("Sent "))
        XCTAssertTrue(MessageStatus.caption(sent: ms, delivered: ms, read: nil, showRead: true, now: now).hasPrefix("Delivered "))
        XCTAssertTrue(MessageStatus.caption(sent: ms, delivered: ms, read: ms, showRead: true, now: now).hasPrefix("Read "))
        XCTAssertTrue(MessageStatus.caption(sent: ms, delivered: ms, read: ms, showRead: false, now: now).hasPrefix("Delivered "))
    }

    func testGroupReadByCaption() throws {
        let json = #"{"id":"m1","sender_handle":"me","body":"hi","created_at":1700000000000,"read_by":[{"handle":"sam","read_at":1700000060000},{"display_name":"Ana"}]}"#
        let m = try JSONDecoder().decode(BlindbanditGroupMessage.self, from: Data(json.utf8))
        XCTAssertEqual(m.read_by, ["@sam", "Ana"])
        XCTAssertTrue(MessageStatus.groupCaption(for: m).hasPrefix("Read by @sam, Ana "))
        let counted = try JSONDecoder().decode(BlindbanditGroupMessage.self, from: Data(#"{"id":"m2","body":"x","created_at":"2026-10-23T06:00:00Z","read_count":3}"#.utf8))
        XCTAssertEqual(MessageStatus.groupCaption(for: counted), "Read by 3")
        XCTAssertGreaterThan(counted.created_at, 1_700_000_000_000)
    }
}
