import Foundation
import os

private let log = Logger(subsystem: "net.mrblindbandit.app", category: "LiveActivity")

/// Live Activities / Dynamic Island are deferred until BlindbanditWidgets is re-embedded with ASC
/// App IDs + signing. ActivityKit must not link into the main binary without a WidgetKit Live
/// Activity extension — ASC rejects that as Invalid Binary (builds 31–32 never appeared on TF).
@MainActor
enum LiveCallActivityController {
    static func startOrUpdate(callID: String, handle: String, displayName: String, phase: String, muted: Bool = false, onSpeaker: Bool = false, startedAt: Date? = nil) {
        BanditSharedStore.publishCall(handle: handle, state: phase, startedAt: startedAt)
        log.debug("LA stub — widgets not embedded (call \(handle, privacy: .public) \(phase, privacy: .public))")
    }

    static func end() {
        BanditSharedStore.publishCall(handle: "", state: "idle", startedAt: nil)
    }
}

@MainActor
enum BitePostActivityController {
    static func start(preview: String) {}
    static func update(progress: Double, stage: String, detail: String) {}
    static func end(success: Bool) {}
}
