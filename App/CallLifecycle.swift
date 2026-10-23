import Foundation
import os

/// 2.0.6: calls this device has ended (hung up, declined, remote-ended). Any later invite / VoIP push
/// for one of these IDs is reported to CallKit and ended immediately so a finished call never rings again.
enum EndedCalls {
    private static let key = "calls.ended.206"
    private static let pendingKey = "calls.pendingEnd.206"
    static let staleAfter: TimeInterval = 50 // ring timeout is 45 s

    private static var store: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func mark(_ id: String) {
        guard !id.isEmpty else { return }
        var s = store
        let now = Date().timeIntervalSince1970
        s = s.filter { now - $0.value < 86_400 }
        s[id] = now
        store = s
    }

    static func contains(_ id: String) -> Bool { store[id] != nil }

    /// created_at is milliseconds since 1970 (0 = unknown, never stale).
    static func isStale(createdAtMs: Double, now: Date = Date()) -> Bool {
        guard createdAtMs > 0 else { return false }
        return now.timeIntervalSince1970 - createdAtMs / 1000 > staleAfter
    }

    static func shouldIgnore(id: String, createdAtMs: Double) -> Bool {
        contains(id) || isStale(createdAtMs: createdAtMs)
    }

    // MARK: Reliable /end (retry, persisted across launches)

    static var pendingEnds: [String] {
        get { UserDefaults.standard.stringArray(forKey: pendingKey) ?? [] }
        set { UserDefaults.standard.set(Array(Set(newValue)), forKey: pendingKey) }
    }

    /// Marks the call ended locally, then POSTs /end with backoff (0.5, 1, 2, 4, 8 s). Unsent ends retry on next launch.
    static func endReliably(_ id: String) async {
        mark(id)
        pendingEnds.append(id)
        for attempt in 0..<6 {
            if await BlindbanditAPI.endCallChecked(id: id) {
                pendingEnds.removeAll { $0 == id }
                CallTiming.log("end \(id) ok after \(attempt + 1) attempt(s)")
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
        }
        CallTiming.log("end \(id) still pending; will retry on next launch")
    }

    static func flushPending() async {
        for id in pendingEnds { await endReliably(id) }
    }
}

/// Step timings for "Call takes long to start". Visible in Console (category calls) and Settings logs.
enum CallTiming {
    static let logger = Logger(subsystem: "net.mrblindbandit.app", category: "calls")
    private static var t0 = Date()
    static func start(_ what: String) { t0 = Date(); log("start \(what)") }
    static func step(_ what: String) { log("\(what) +\(Int(Date().timeIntervalSince(t0) * 1000)) ms") }
    static func log(_ s: String) {
        logger.info("\(s, privacy: .public)")
        var lines = UserDefaults.standard.stringArray(forKey: "calls.timingLog") ?? []
        lines.append("\(ISO8601DateFormatter().string(from: Date())) \(s)")
        UserDefaults.standard.set(Array(lines.suffix(60)), forKey: "calls.timingLog")
    }
}
