import UIKit
import SwiftUI

@MainActor
enum AppHaptics {
    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    static func light() {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
    }

    static func medium() {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.85)
    }

    static func heavy() {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred(intensity: 1.0)
    }

    static func soft() {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
    }

    static func rigid() {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
    }

    static func selection() {
        guard enabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func success() {
        guard enabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    static func error() {
        guard enabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }

    static func doublePulse() {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            guard enabled else { return }
            let second = UIImpactFeedbackGenerator(style: .light)
            second.prepare()
            second.impactOccurred(intensity: 0.7)
        }
    }

    static func creatorComplete() {
        guard enabled else { return }
        let first = UIImpactFeedbackGenerator(style: .rigid)
        first.prepare()
        first.impactOccurred(intensity: 0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard enabled else { return }
            let notification = UINotificationFeedbackGenerator()
            notification.prepare()
            notification.notificationOccurred(.success)
        }
    }
}

struct HapticButtonStyle: ButtonStyle {
    enum Strength { case light, medium, heavy }
    var strength: Strength = .light

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed else { return }
                switch strength {
                case .light: AppHaptics.light()
                case .medium: AppHaptics.medium()
                case .heavy: AppHaptics.heavy()
                }
            }
    }
}
