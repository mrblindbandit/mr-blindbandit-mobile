import SwiftUI
import UIKit
import AVFoundation
import WebKit

// MARK: - Design system
//
// One small set of tokens shared by every screen. Text always uses Dynamic Type text styles,
// touch targets are at least 44 pt, and colours meet WCAG AA contrast on both backgrounds.

enum Brand {
    static let gold = Color(red: 1.0, green: 0.835, blue: 0.31)       // #FFD54F
    static let goldDeep = Color(red: 0.72, green: 0.53, blue: 0.0)    // #B88700, AA on white
    static let ink = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let minTouch: CGFloat = 44
    static let corner: CGFloat = 18

    /// Accent that stays readable in both light and dark mode, and in high contrast.
    static func accent(_ scheme: ColorScheme, highContrast: Bool) -> Color {
        if highContrast { return scheme == .dark ? .yellow : .black }
        return scheme == .dark ? gold : goldDeep
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Match system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Keys for every persisted setting so views and services agree on names.
enum SettingsKey {
    static let appearance = "appearance"
    static let highContrast = "highContrast"
    static let hapticsEnabled = "hapticsEnabled"
    static let speechFeedback = "speechFeedback"
    static let speechRate = "speechRate"
    static let reduceAppMotion = "reduceAppMotion"
    static let announcePageLoads = "announcePageLoads"
    static let keepScreenAwake = "keepScreenAwake"
    static let uiSounds = "uiSounds"
    static let startCallsWithCameraOff = "startCallsWithCameraOff"
    static let notifyMessages = "notifyMessages"
    static let notifyCalls = "notifyCalls"
    static let requireDeviceUnlock = "requireDeviceUnlock"
}

struct BrandCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(SettingsKey.highContrast) private var highContrast = false
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Brand.corner, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.corner, style: .continuous)
                    .strokeBorder(highContrast ? Color.primary : Color.clear, lineWidth: 2)
            )
    }
}

struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(SettingsKey.highContrast) private var highContrast = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Brand.minTouch + 8)
            .foregroundStyle(scheme == .dark ? Color.black : Color.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(highContrast ? (scheme == .dark ? Color.yellow : Color.black) : (scheme == .dark ? Brand.gold : Brand.ink))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Speech feedback

/// Short spoken confirmations for people who do not run VoiceOver (for example low-vision users).
/// When VoiceOver is on we post an accessibility announcement instead so speech never overlaps.
@MainActor
enum SpeechFeedback {
    private static let synthesizer = AVSpeechSynthesizer()

    static func say(_ text: String) {
        guard !text.isEmpty else { return }
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsKey.speechFeedback) as? Bool ?? false else { return }
        let rate = defaults.object(forKey: SettingsKey.speechRate) as? Double ?? 1.0
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Float(min(max(Double(AVSpeechUtteranceDefaultSpeechRate) * rate, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}

// MARK: - Local data

@MainActor
enum LocalDataEraser {
    /// Removes every setting, cached web session and stored identifier on this device.
    static func eraseAll() {
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
