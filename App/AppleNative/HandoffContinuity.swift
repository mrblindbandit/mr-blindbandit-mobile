import Foundation
import UIKit

enum HandoffKind: String {
    case chat = "net.mrblindbandit.app.handoff.chat"
    case ai = "net.mrblindbandit.app.handoff.ai"
    case bites = "net.mrblindbandit.app.handoff.bites"
}

@MainActor
enum HandoffContinuity {
    static func becomeCurrent(kind: HandoffKind, title: String, userInfo: [AnyHashable: Any] = [:]) {
        let activity = NSUserActivity(activityType: kind.rawValue)
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.userInfo = userInfo
        activity.becomeCurrent()
    }

    static func resign() {
        NSUserActivity().invalidate()
    }

    nonisolated static func handle(_ activity: NSUserActivity) -> Bool {
        switch activity.activityType {
        case HandoffKind.chat.rawValue:
            if let handle = activity.userInfo?["handle"] as? String {
                NotificationCenter.default.post(
                    name: .blindbanditMessageDeepLinkReceived,
                    object: nil,
                    userInfo: ["handle": handle, "source": "handoff"]
                )
                return true
            }
        case HandoffKind.ai.rawValue:
            NotificationCenter.default.post(name: .banditOpenAIChat, object: nil)
            return true
        case HandoffKind.bites.rawValue:
            NotificationCenter.default.post(name: .banditOpenBitesTab, object: nil)
            return true
        default:
            break
        }
        return false
    }
}
