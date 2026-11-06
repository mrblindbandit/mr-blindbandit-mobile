import XCTest
@testable import Blindbandit

final class CallAndFeedRegressionTests: XCTestCase {
    func testStereoStaysWhenMediaVolumeIsActive() {
        XCTAssertEqual(CallCapturePlan.choose(mediaVolumeActive: true), .stereoMedia)
    }

    func testVoiceChatSessionPublishesIntelligibleMono() {
        XCTAssertEqual(CallCapturePlan.choose(mediaVolumeActive: false), .monoIntelligible)
        XCTAssertEqual(CallCapturePlan.monoHighQualityProfile, 4)
        XCTAssertFalse(CallAudioPolicy.noiseSuppression)
        XCTAssertFalse(CallAudioPolicy.aiNoiseSuppression)
        XCTAssertTrue(CallAudioPolicy.echoCancellation)
    }

    func testCallTitleHidesRawIds() {
        XCTAssertEqual(CallPeerLabel.spoken(name: "Emma", handle: "emma"), "Emma")
        XCTAssertEqual(CallPeerLabel.spoken(name: "4829103", handle: "emma"), "@emma")
        XCTAssertEqual(CallPeerLabel.spoken(name: "", handle: "4829103"), "Caller")
        XCTAssertEqual(CallPeerLabel.spoken(name: "profile_abc", handle: ""), "Caller")
        XCTAssertEqual(CallPeerLabel.spoken(name: "", handle: "Blindbandit caller"), "Blindbandit caller")
    }

    func testPublicPhotoAddressUsesTheWebsite() {
        XCTAssertEqual(PublicMediaURL.httpsString("/assets/a.jpg"), "https://mrblindbandit.net/assets/a.jpg")
        XCTAssertEqual(PublicMediaURL.httpsString("https://cdn.mrblindbandit.net/a.jpg"), "https://cdn.mrblindbandit.net/a.jpg")
        XCTAssertEqual(PublicMediaURL.httpsString("http://mrblindbandit.net/a.jpg"), "https://mrblindbandit.net/a.jpg")
        XCTAssertNil(PublicMediaURL.httpsString("javascript:alert(1)"))
        XCTAssertNil(PublicMediaURL.httpsString("file:///tmp/a.jpg"))
        let nested = PublicMediaURL.firstHTTPS(in: ["data": ["public_url": "/media/me.jpg"]])
        XCTAssertEqual(nested, "https://mrblindbandit.net/media/me.jpg")
    }

    func testCallProviderDefaultsToAgoraAndObeysLiveKit() {
        XCTAssertEqual(CallProviderPlan.createField(serverPreferred: nil, agoraConfigured: nil), "agora")
        XCTAssertEqual(CallProviderPlan.createField(serverPreferred: "agora", agoraConfigured: true), "agora")
        XCTAssertNil(CallProviderPlan.createField(serverPreferred: "livekit", agoraConfigured: true))
        XCTAssertNil(CallProviderPlan.createField(serverPreferred: "agora", agoraConfigured: false))
        XCTAssertFalse(CallProviderPlan.messageTransportNote.isEmpty)
    }

    func testAdminButtonsUseLiveRoutes() {
        let mute = AdminRoutePlan.userAction(action: "mute_posts", userId: "profile_1")
        XCTAssertEqual(mute.method, "PATCH")
        XCTAssertEqual(mute.path, "v1/social/admin/users/profile_1/restrictions")
        XCTAssertEqual(mute.body["mute_posts"], "true")
        XCTAssertNil(mute.unavailableReason)
        let push = AdminRoutePlan.userAction(action: "test_push", userId: "profile_1", title: "Hi", message: "There")
        XCTAssertEqual(push.path, "v1/social/admin/notifications/test")
        XCTAssertEqual(push.body["user_id"], "profile_1")
        let disconnect = AdminRoutePlan.userAction(action: "force_disconnect", userId: "profile_1")
        XCTAssertEqual(disconnect.path, "v1/social/admin/users/profile_1/calls/disconnect")
        let wipe = AdminRoutePlan.userAction(action: "wipe_sessions", userId: "profile_1")
        XCTAssertNotNil(wipe.unavailableReason)
        XCTAssertTrue(wipe.path.isEmpty)
    }

    func testSharedFeedDropsPrivateStates() {
        XCTAssertTrue(BiteFeedPolicy.includeInSharedFeed(visibility: nil, status: nil))
        XCTAssertTrue(BiteFeedPolicy.includeInSharedFeed(visibility: "public", status: "published"))
        XCTAssertFalse(BiteFeedPolicy.includeInSharedFeed(visibility: "draft", status: nil))
        XCTAssertFalse(BiteFeedPolicy.includeInSharedFeed(visibility: "private", status: "ok"))
        XCTAssertFalse(BiteFeedPolicy.includeInSharedFeed(visibility: nil, status: "deleted"))
        XCTAssertFalse(BiteFeedPolicy.shouldEmitSound(visible: false, soundEnabled: true, inCall: false))
        XCTAssertFalse(BiteFeedPolicy.shouldEmitSound(visible: true, soundEnabled: true, inCall: true))
        XCTAssertTrue(BiteFeedPolicy.shouldEmitSound(visible: true, soundEnabled: true, inCall: false))
    }
}
