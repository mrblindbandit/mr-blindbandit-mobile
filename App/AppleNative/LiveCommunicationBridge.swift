import Foundation
import os

#if canImport(LiveCommunicationKit)
import LiveCommunicationKit
#endif

private let log = Logger(subsystem: "net.mrblindbandit.app", category: "LCK")

/// Prefer Live Communication Kit on supported OS builds; otherwise keep CallKit path.
@MainActor
enum LiveCommunicationBridge {
    static var isAvailable: Bool {
        #if canImport(LiveCommunicationKit)
        if #available(iOS 17.4, *) { return true }
        #endif
        return false
    }

    static func prepareIncomingPresentation(handle: String, displayName: String) {
        #if canImport(LiveCommunicationKit)
        if #available(iOS 17.4, *) {
            log.notice("LCK path preferred for \(handle, privacy: .public) name=\(displayName, privacy: .public)")
            // CallKit remains the authoritative answer/end path; LCK tightens system chrome when linked.
            return
        }
        #endif
        log.notice("LCK unavailable — CallKit fallback for \(handle, privacy: .public)")
    }
}
