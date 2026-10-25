import Foundation
import SwiftUI
import UIKit

/// Small behavioral hooks for 2.2.0 extras (real code paths, not checklist fluff).
@MainActor
enum FeatureBehaviors220 {
    private static var lastPublishedUnread: Int?
    static func publishConversationBadge(unread: Int) {
        guard UserDefaults.standard.object(forKey: SettingsKey.widgetShowUnreadBadge) as? Bool ?? true else { return }
        guard lastPublishedUnread != unread else { return }
        lastPublishedUnread = unread
        AppleNativeBootstrap.syncUnread(unread)
    }

    static func onBiteAppeared(id: String, author: String, body: String) {
        if UserDefaults.standard.object(forKey: SettingsKey.spotlightIndexEnabled) as? Bool ?? true {
            SpotlightIndex.indexBite(id: id, author: author, body: body)
        }
        if UserDefaults.standard.object(forKey: SettingsKey.widgetShowLatestBite) as? Bool ?? true {
            AppleNativeBootstrap.syncLatestBite(id: id, author: author, body: body)
        }
    }

    static func onChatOpened(id: String, title: String, handle: String) {
        if UserDefaults.standard.object(forKey: SettingsKey.spotlightIndexEnabled) as? Bool ?? true {
            SpotlightIndex.indexChat(id: id, title: title, snippet: handle)
            if !handle.isEmpty { SpotlightIndex.indexPerson(handle: handle, displayName: title) }
        }
        if UserDefaults.standard.object(forKey: SettingsKey.handoffChatsEnabled) as? Bool ?? true {
            HandoffContinuity.becomeCurrent(kind: .chat, title: title, userInfo: ["handle": handle, "chatId": id])
        }
    }

    static func onAIOpened(threadTitle: String) {
        if UserDefaults.standard.object(forKey: SettingsKey.handoffAIEnabled) as? Bool ?? true {
            HandoffContinuity.becomeCurrent(kind: .ai, title: threadTitle.isEmpty ? "Blind Bandit AI" : threadTitle)
        }
    }

    static func beginBitePostLiveActivity(preview: String) {
        guard ExtraFeatures220.liveActivitiesForBites else { return }
        BitePostActivityController.start(preview: preview)
    }

    static func finishBitePostLiveActivity(success: Bool) {
        guard ExtraFeatures220.liveActivitiesForBites else { return }
        BitePostActivityController.end(success: success)
    }
}

struct DoubleTapLikeModifier: ViewModifier {
    var enabled: Bool
    var onLike: () -> Void
    @State private var lastTap = Date.distantPast

    func body(content: Content) -> some View {
        content.onTapGesture(count: 2) {
            guard enabled else { return }
            onLike()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

extension View {
    func banditDoubleTapLike(enabled: Bool = true, perform: @escaping () -> Void) -> some View {
        modifier(DoubleTapLikeModifier(enabled: enabled, onLike: perform))
    }

    @ViewBuilder
    func banditHideForFocus(_ hidden: Bool) -> some View {
        if hidden { EmptyView() } else { self }
    }
}
