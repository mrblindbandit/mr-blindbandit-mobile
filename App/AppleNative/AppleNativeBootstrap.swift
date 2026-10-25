import Foundation
import SwiftUI
import WidgetKit

@MainActor
enum AppleNativeBootstrap {
    static func onLaunch() {
        BanditTips.configure()
        refreshWidgets()
    }

    static func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncUnread(_ count: Int) {
        BanditSharedStore.publishUnreadDMs(count)
        refreshWidgets()
    }

    static func syncLatestBite(id: String, author: String, body: String) {
        BanditSharedStore.publishLatestBite(id: id, author: author, body: body)
        SpotlightIndex.indexBite(id: id, author: author, body: body)
        refreshWidgets()
    }

    static func onCallRinging(callID: String, handle: String, displayName: String) {
        LiveCommunicationBridge.prepareIncomingPresentation(handle: handle, displayName: displayName)
        LiveCallActivityController.startOrUpdate(callID: callID, handle: handle, displayName: displayName, phase: "ringing")
    }

    static func onCallConnected(callID: String, handle: String, displayName: String, startedAt: Date, muted: Bool, onSpeaker: Bool) {
        LiveCallActivityController.startOrUpdate(
            callID: callID,
            handle: handle,
            displayName: displayName,
            phase: "connected",
            muted: muted,
            onSpeaker: onSpeaker,
            startedAt: startedAt
        )
    }

    static func onCallEnded() {
        LiveCallActivityController.end()
    }
}
