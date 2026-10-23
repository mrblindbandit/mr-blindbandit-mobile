import Foundation

/// Safety numbers (SPEC.md §1.7; exact layout in vectors/p256-v1.json).
struct SafetyNumber: Equatable {
    static let iterations = 5200
    let groups: [String]
    let qrPayload: String

    static func fingerprint(signPubs: [Data], handle: String) -> Data {
        let keys = signPubs.sorted { $0.lexicographicallyPrecedes($1) }.reduce(Data(), +)
        var h = Data([0x00, 0x01]) + keys + Data(handle.utf8)
        for _ in 0..<iterations { h = E2EECrypto.sha512(h + keys) }
        return h.prefix(30)
    }

    static func digitGroups(_ fp: Data) -> [String] {
        let bytes = [UInt8](fp)
        return (0..<6).map { i in
            let v = bytes[(i * 5)..<(i * 5 + 5)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            return String(format: "%05llu", v % 100000)
        }
    }

    init(myHandle: String, mySignPubs: [Data], theirHandle: String, theirSignPubs: [Data]) {
        let me = (myHandle.lowercased(), SafetyNumber.fingerprint(signPubs: mySignPubs, handle: myHandle.lowercased()))
        let them = (theirHandle.lowercased(), SafetyNumber.fingerprint(signPubs: theirSignPubs, handle: theirHandle.lowercased()))
        let ordered = [me, them].sorted { $0.0 < $1.0 }
        groups = SafetyNumber.digitGroups(ordered[0].1) + SafetyNumber.digitGroups(ordered[1].1)
        qrPayload = "bbsafety:1:\(ordered[0].0):\(E2EECrypto.hex(ordered[0].1)):\(ordered[1].0):\(E2EECrypto.hex(ordered[1].1))"
    }

    var display: String { groups.joined(separator: " ") }

    /// "Group 1 of 12: 1 2 3 4 5" so VoiceOver reads each digit.
    func spokenGroup(_ index: Int) -> String {
        "Group \(index + 1) of \(groups.count): " + groups[index].map(String.init).joined(separator: " ")
    }

    /// A scanned code matches when it carries the same two fingerprints (in either order).
    func matches(scanned: String) -> Bool {
        let a = scanned.split(separator: ":").map(String.init)
        let b = qrPayload.split(separator: ":").map(String.init)
        guard a.count == 6, b.count == 6, a[0] == "bbsafety", a[1] == "1" else { return false }
        return Set([a[2] + a[3], a[4] + a[5]]) == Set([b[2] + b[3], b[4] + b[5]])
    }
}
