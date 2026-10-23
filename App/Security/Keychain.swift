import Foundation
import Security

/// Small keychain wrapper. Items live in the shared access group (so the Notification Service Extension can read them)
/// and fall back to the app's default group when the entitlement isn't present (unsigned simulator/CI builds).
enum Keychain {
    static let service = "net.mrblindbandit.e2ee"

    /// "$(AppIdentifierPrefix)net.mrblindbandit.shared", expanded at build time into Info.plist.
    static var sharedGroup: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "BBKeychainGroup") as? String, !g.isEmpty, !g.hasPrefix("$(") else { return nil }
        return g
    }

    private static func base(_ account: String, synced: Bool, group: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        q[kSecAttrSynchronizable as String] = synced ? kCFBooleanTrue : kCFBooleanFalse
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    @discardableResult
    static func set(_ data: Data, account: String, synced: Bool = false) -> Bool {
        delete(account)
        let groups: [String?] = sharedGroup == nil ? [nil] : [sharedGroup, nil]
        let syncs: [Bool] = synced ? [true, false] : [false]
        for group in groups {
            for sync in syncs {
                var q = base(account, synced: sync, group: group)
                q[kSecValueData as String] = data
                q[kSecAttrAccessible as String] = sync ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                if SecItemAdd(q as CFDictionary, nil) == errSecSuccess { return true }
            }
        }
        return false
    }

    static func get(_ account: String) -> Data? {
        for group in [sharedGroup, nil] {
            var q = base(account, synced: false, group: group)
            q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data { return d }
            if group == nil { break }
        }
        return nil
    }

    static func delete(_ account: String) {
        for group in [sharedGroup, nil] {
            var q = base(account, synced: false, group: group)
            q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            SecItemDelete(q as CFDictionary)
            if group == nil { break }
        }
    }

    static func getCodable<T: Decodable>(_ type: T.Type, _ account: String) -> T? {
        get(account).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    @discardableResult
    static func setCodable<T: Encodable>(_ value: T, _ account: String, synced: Bool = false) -> Bool {
        guard let d = try? JSONEncoder().encode(value) else { return false }
        return set(d, account: account, synced: synced)
    }
}
