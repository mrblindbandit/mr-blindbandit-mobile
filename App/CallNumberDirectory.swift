import Foundation

/// Maps BlindBandit call numbers ↔ handles for the native Dialer.
/// Local + iCloud KVS so the owner's assignments sync across their devices until a server API exists.
enum CallNumberDirectory {
    private static let mapKey = "bb.callNumber.map"
    private static let myNumberKey = "bb.callNumber.mine"

    /// Digits-only form used as lookup key (* and # kept for special short codes).
    static func normalize(_ raw: String) -> String {
        let allowed = Set("0123456789*#")
        return String(raw.filter { allowed.contains($0) })
    }

    /// This profile's BlindBandit call number (what others dial to reach you).
    static var myCallNumber: String {
        get {
            let local = UserDefaults.standard.string(forKey: myNumberKey) ?? ""
            if !local.isEmpty { return local }
            return NSUbiquitousKeyValueStore.default.string(forKey: myNumberKey) ?? ""
        }
        set {
            let n = normalize(newValue)
            UserDefaults.standard.set(n, forKey: myNumberKey)
            NSUbiquitousKeyValueStore.default.set(n, forKey: myNumberKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// number → handle
    private static var map: [String: String] {
        get {
            if let d = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String], !d.isEmpty {
                return d
            }
            if let d = NSUbiquitousKeyValueStore.default.dictionary(forKey: mapKey) as? [String: String] {
                return d
            }
            return [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: mapKey)
            NSUbiquitousKeyValueStore.default.set(newValue, forKey: mapKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    static func assign(number: String, handle: String) {
        let n = normalize(number)
        let h = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !n.isEmpty, !h.isEmpty else { return }
        var m = map
        // One number per handle: drop prior assignments for this handle.
        m = m.filter { $0.value.lowercased() != h.lowercased() }
        m[n] = h
        map = m
    }

    static func unassign(number: String) {
        var m = map
        m.removeValue(forKey: normalize(number))
        map = m
    }

    static func number(forHandle handle: String) -> String? {
        let h = handle.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return map.first { $0.value.lowercased() == h }?.key
    }

    /// Resolve dialed digits to a BlindBandit handle, or nil if unknown.
    static func resolve(_ digits: String) -> String? {
        let n = normalize(digits)
        guard !n.isEmpty else { return nil }
        if let h = map[n] { return h }
        // Soft match: ignore leading 1 for NANP-style entries.
        if n.hasPrefix("1"), n.count == 11, let h = map[String(n.dropFirst())] { return h }
        if let h = map["1" + n] { return h }
        return nil
    }

    static var allAssignments: [(number: String, handle: String)] {
        map.sorted { $0.key < $1.key }.map { (number: $0.key, handle: $0.value) }
    }
}
