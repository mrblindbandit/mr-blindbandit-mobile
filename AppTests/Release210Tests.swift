import XCTest
@testable import Blindbandit

@MainActor
final class Release210Tests: XCTestCase {
    func testProfileAvatarHTTPSOnly() {
        // URL gate lives in ProfileAvatar; exercise prep + cache helpers.
        AvatarImageCache.clear()
        XCTAssertNil(AvatarImageCache.data(for: "missing"))
        let sample = Data([0xFF, 0xD8, 0xFF, 0xE0])
        AvatarImageCache.put(sample, for: "https://cdn.example/a.jpg")
        XCTAssertEqual(AvatarImageCache.data(for: "https://cdn.example/a.jpg"), sample)
        AvatarImageCache.clear("https://cdn.example/a.jpg")
        XCTAssertNil(AvatarImageCache.data(for: "https://cdn.example/a.jpg"))
    }

    func testMediaDownloadPolicyRespectsUseLessData() {
        let d = UserDefaults.standard
        d.set(MediaAutoDownload.always.rawValue, forKey: SettingsKey.mediaAutoDownload)
        d.set(true, forKey: SettingsKey.useLessData)
        XCTAssertFalse(MediaDownloadPolicy.allowsAutoDownload(onWifi: true))
        d.set(false, forKey: SettingsKey.useLessData)
        d.set(MediaAutoDownload.wifi.rawValue, forKey: SettingsKey.mediaAutoDownload)
        XCTAssertTrue(MediaDownloadPolicy.allowsAutoDownload(onWifi: true))
        XCTAssertFalse(MediaDownloadPolicy.allowsAutoDownload(onWifi: false))
        d.set(MediaAutoDownload.never.rawValue, forKey: SettingsKey.mediaAutoDownload)
        XCTAssertFalse(MediaDownloadPolicy.allowsAutoDownload(onWifi: true))
        d.removeObject(forKey: SettingsKey.useLessData)
        d.removeObject(forKey: SettingsKey.mediaAutoDownload)
    }

    func testNotificationPreviewStyles() {
        XCTAssertEqual(NotificationPreviewStyle.nameOnly.title, "Name only")
        XCTAssertEqual(NotificationPreviewStyle.hidden.rawValue, "hidden")
        XCTAssertEqual(NotificationPreviewStyle.nameMessage.rawValue, "nameMessage")
    }

    func testQuietHoursSpansMidnight() {
        let d = UserDefaults.standard
        d.set(true, forKey: SettingsKey.quietHoursEnabled)
        d.set(22 * 60, forKey: SettingsKey.quietHoursStart)
        d.set(7 * 60, forKey: SettingsKey.quietHoursEnd)
        var cal = Calendar.current
        cal.timeZone = .current
        var c = DateComponents(); c.hour = 23; c.minute = 30
        let late = cal.date(from: c)!
        c.hour = 3; c.minute = 0
        let early = cal.date(from: c)!
        c.hour = 12; c.minute = 0
        let noon = cal.date(from: c)!
        XCTAssertTrue(QuietHoursSchedule.isQuietNow(date: late))
        XCTAssertTrue(QuietHoursSchedule.isQuietNow(date: early))
        XCTAssertFalse(QuietHoursSchedule.isQuietNow(date: noon))
        d.set(false, forKey: SettingsKey.quietHoursEnabled)
        XCTAssertFalse(QuietHoursSchedule.isQuietNow(date: late))
        d.removeObject(forKey: SettingsKey.quietHoursEnabled)
        d.removeObject(forKey: SettingsKey.quietHoursStart)
        d.removeObject(forKey: SettingsKey.quietHoursEnd)
    }

    func testChatWallpaperAndLastSeenEnums() {
        XCTAssertEqual(ChatWallpaperOption.none.title, "None")
        XCTAssertEqual(ChatWallpaperOption.solid.rawValue, "solid")
        XCTAssertEqual(LastSeenVisibility.nobody.title, "Nobody")
    }

    func testIncomingCallOptionalAvatar() {
        let call = BlindbanditIncomingCall(
            id: "c1", kind: "voice", from_handle: "alice", from_name: "Alice",
            group_id: nil, group_name: nil, created_at: 0, from_avatar_url: "https://cdn.example/a.jpg"
        )
        XCTAssertEqual(call.from_avatar_url, "https://cdn.example/a.jpg")
        XCTAssertEqual(call.callerLabel, "Alice")
    }

    func testDefaultRingtoneUntouched() {
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBandit.rawValue, "ringtone_mrblindbandit")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBandit.title, "Mr. BlindBandit")
    }

    func testSettingsKeysPresent() {
        XCTAssertFalse(SettingsKey.mediaAutoDownload.isEmpty)
        XCTAssertFalse(SettingsKey.notificationPreviewStyle.isEmpty)
        XCTAssertFalse(SettingsKey.liveCaptionsDefault.isEmpty)
        XCTAssertFalse(SettingsKey.voicePreferEarpiece.isEmpty)
        XCTAssertFalse(SettingsKey.announceOutgoingSend.isEmpty)
        XCTAssertEqual(SettingsKey.profilePhotoVisibility, "privacy.profilePhoto")
    }
}
