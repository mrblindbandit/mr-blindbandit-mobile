import Foundation
import Intents
import os

#if canImport(CarPlay)
import CarPlay
#endif

private let log = Logger(subsystem: "net.mrblindbandit.app", category: "CarPlay")

/// CarPlay calling via INStartCallIntent / templates as far as entitlements allow.
enum CarPlayCalling {
    static func handleStartCallIntent(_ intent: INStartCallIntent) -> Bool {
        let handle: String? = {
            if let p = intent.contacts?.first?.personHandle?.value { return p }
            if let n = intent.contacts?.first?.displayName { return n }
            return nil
        }()
        guard let handle, !handle.isEmpty else { return false }
        log.notice("CarPlay/Siri start call handle=\(handle, privacy: .public)")
        NotificationCenter.default.post(
            name: .blindbanditCallDeepLinkReceived,
            object: nil,
            userInfo: ["handle": handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")), "source": "carPlay"]
        )
        return true
    }
}

#if canImport(CarPlay)
@MainActor
final class BanditCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let call = CPListItem(text: "Start Blind Bandit call", detailText: "Search a @handle in the phone app")
        call.handler = { _, completion in
            NotificationCenter.default.post(name: .banditOpenAIChat, object: nil) // soft handoff; calls via Siri/INStartCallIntent
            completion()
        }
        let unread = BanditSharedStore.unreadDMCount
        let messages = CPListItem(text: "Unread messages", detailText: unread == 0 ? "None" : "\(unread) unread")
        let section = CPListSection(items: [call, messages])
        let list = CPListTemplate(title: "Blind Bandit", sections: [section])
        interfaceController.setRootTemplate(list, animated: true) { _, _ in }
        log.notice("CarPlay connected")
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }
}
#endif
