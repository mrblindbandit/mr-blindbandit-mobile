import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct MuteCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Mute Blind Bandit call"
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("banditControlMuteCall"), object: nil)
        return .result()
    }
}

@available(iOS 18.0, *)
struct EndCallIntent: AppIntent {
    static var title: LocalizedStringResource = "End Blind Bandit call"
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("banditControlEndCall"), object: nil)
        return .result()
    }
}

@available(iOS 18.0, *)
struct StartBlindBanditCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Blind Bandit call"
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: Notification.Name("blindbanditCallDeepLinkReceived"),
            object: nil,
            userInfo: ["source": "controlCenter"]
        )
        return .result()
    }
}

@available(iOS 18.0, *)
struct MuteCallControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "net.mrblindbandit.app.control.mute") {
            ControlWidgetButton(action: MuteCallIntent()) {
                Label("Mute", systemImage: "mic.slash.fill")
            }
        }
        .displayName("Mute call")
        .description("Mute the active Blind Bandit call.")
    }
}

@available(iOS 18.0, *)
struct EndCallControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "net.mrblindbandit.app.control.end") {
            ControlWidgetButton(action: EndCallIntent()) {
                Label("End call", systemImage: "phone.down.fill")
            }
        }
        .displayName("End call")
        .description("End the active Blind Bandit call.")
    }
}

@available(iOS 18.0, *)
struct StartCallControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "net.mrblindbandit.app.control.start") {
            ControlWidgetButton(action: StartBlindBanditCallIntent()) {
                Label("Bandit call", systemImage: "phone.fill")
            }
        }
        .displayName("Start Blind Bandit call")
        .description("Open Blind Bandit to start a call.")
    }
}
