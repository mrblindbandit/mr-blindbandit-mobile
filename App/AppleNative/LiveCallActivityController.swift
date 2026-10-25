import Foundation
import ActivityKit
import os

private let log = Logger(subsystem: "net.mrblindbandit.app", category: "LiveActivity")

@MainActor
enum LiveCallActivityController {
    private static var current: Activity<CallActivityAttributes>?

    static func startOrUpdate(callID: String, handle: String, displayName: String, phase: String, muted: Bool = false, onSpeaker: Bool = false, startedAt: Date? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let elapsed: Int = {
            guard let startedAt else { return 0 }
            return max(0, Int(Date().timeIntervalSince(startedAt)))
        }()
        let state = CallActivityAttributes.ContentState(phase: phase, elapsedSeconds: elapsed, muted: muted, onSpeaker: onSpeaker)
        BanditSharedStore.publishCall(handle: handle, state: phase, startedAt: startedAt)
        if let current {
            Task { await current.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        let attrs = CallActivityAttributes(callID: callID, handle: handle, displayName: displayName.isEmpty ? handle : displayName)
        do {
            current = try Activity.request(attributes: attrs, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            log.notice("Live Activity started for \(handle, privacy: .public)")
        } catch {
            log.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func end() {
        BanditSharedStore.publishCall(handle: "", state: "idle", startedAt: nil)
        guard let current else { return }
        let final = CallActivityAttributes.ContentState(phase: "ending", elapsedSeconds: 0, muted: false, onSpeaker: false)
        Task {
            await current.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate)
            await MainActor.run { Self.current = nil }
        }
    }
}

@MainActor
enum BitePostActivityController {
    private static var current: Activity<BitePostActivityAttributes>?

    static func start(preview: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        let attrs = BitePostActivityAttributes(draftPreview: String(preview.prefix(80)))
        let state = BitePostActivityAttributes.ContentState(stage: "uploading", progress: 0.05, detail: "Uploading Bite…")
        do {
            current = try Activity.request(attributes: attrs, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
        } catch {
            log.error("Bite LA failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func update(progress: Double, stage: String, detail: String) {
        guard let current else { return }
        let state = BitePostActivityAttributes.ContentState(stage: stage, progress: min(1, max(0, progress)), detail: detail)
        Task { await current.update(ActivityContent(state: state, staleDate: nil)) }
    }

    static func end(success: Bool) {
        guard let current else { return }
        let state = BitePostActivityAttributes.ContentState(
            stage: success ? "posted" : "failed",
            progress: success ? 1 : 0,
            detail: success ? "Bite posted" : "Post failed"
        )
        Task {
            await current.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 3))
            await MainActor.run { Self.current = nil }
        }
    }
}
