import UIKit
import SwiftUI

/// Call / DM haptic patterns. Honors Settings → Haptic feedback and Reduce Motion.
@MainActor
enum CallHaptics {
    private static var ringingTimer: Timer?

    static var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hapticsEnabled") }
    }

    private static var motionReduced: Bool {
        UIAccessibility.isReduceMotionEnabled
            || (UserDefaults.standard.object(forKey: "reduceAppMotion") as? Bool ?? false)
    }

    private static var allowed: Bool { hapticsEnabled && !motionReduced }

    static func outgoingStart() {
        guard allowed else { return }
        AppHaptics.soft()
    }

    static func startRingingPulse() {
        stopRingingPulse()
        guard allowed else { return }
        ringingTimer = Timer.scheduledTimer(withTimeInterval: 1.15, repeats: true) { _ in
            Task { @MainActor in
                guard allowed else { return }
                AppHaptics.soft()
            }
        }
    }

    static func stopRingingPulse() {
        ringingTimer?.invalidate()
        ringingTimer = nil
    }

    static func connecting() {
        guard allowed else { return }
        AppHaptics.medium()
    }

    static func connected() {
        guard allowed else { return }
        AppHaptics.success()
    }

    static func disconnected() {
        guard allowed else { return }
        AppHaptics.soft()
    }

    static func busyOrFailed() {
        guard allowed else { return }
        AppHaptics.error()
    }

    static func messageSent() {
        guard allowed else { return }
        AppHaptics.light()
    }

    static func delivered() {
        guard allowed else { return }
        AppHaptics.selection()
    }

    static func read() {
        guard allowed else { return }
        AppHaptics.selection()
    }

    static func voiceNotePress() {
        guard allowed else { return }
        AppHaptics.rigid()
    }

    static func voiceNoteSent() {
        guard allowed else { return }
        AppHaptics.success()
    }

    static func attachmentSent() {
        guard allowed else { return }
        AppHaptics.medium()
    }

    static func inboundMessage() {
        guard allowed else { return }
        AppHaptics.soft()
    }
}
