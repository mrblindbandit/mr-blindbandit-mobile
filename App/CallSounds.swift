import AVFoundation
import UIKit

/// Connect / DM UI audio — ringback, selectable ringtones & notification tones (full ambient pack).
/// Honors Settings → Sounds master toggle and iOS Silent switch (`.ambient`).
@MainActor
enum CallSounds {
    enum Ringtone: String, CaseIterable, Identifiable {
        /// 2.0.6 default: the owner's Mr. BlindBandit ringtone (ringtone_mrblindbandit.caf, 29.5 s IMA4).
        case mrBlindBandit = "ringtone_mrblindbandit"
        case mrBlindBanditClassic = "ringtone_mrblindbandit_classic"
        case mrBlindBanditAlt = "ringtone_mrblindbandit_alt"
        case mrBlindBanditNight = "ringtone_mrblindbandit_night"
        case mrBlindBanditPulse = "ringtone_mrblindbandit_pulse"
        case mrBlindBanditHeat = "ringtone_mrblindbandit_heat"
        case mrBlindBanditRise = "ringtone_mrblindbandit_rise"
        case `default` = "ringtone"
        case gold = "ringtone_gold"
        case pulse = "ringtone_pulse"
        case chime = "ringtone_chime"
        case ambientAurora = "ringtone_ambient_aurora"
        case ambientBloom = "ringtone_ambient_bloom"
        case ambientGlass = "ringtone_ambient_glass"
        case ambientNight = "ringtone_ambient_night"
        case ambientRain = "ringtone_ambient_rain"
        case ambientSpace = "ringtone_ambient_space"
        case ambientDawn = "ringtone_ambient_dawn"
        case ambientLagoon = "ringtone_ambient_lagoon"
        case ambientEmber = "ringtone_ambient_ember"
        case ambientHorizon = "ringtone_ambient_horizon"
        case ambientVelvet = "ringtone_ambient_velvet"
        case ambientCrown = "ringtone_ambient_crown"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .mrBlindBandit: return "Mr. BlindBandit"
            case .mrBlindBanditClassic: return "Classic"
            case .mrBlindBanditAlt: return "Alt"
            case .mrBlindBanditNight: return "Night"
            case .mrBlindBanditPulse: return "Pulse"
            case .mrBlindBanditHeat: return "Heat"
            case .mrBlindBanditRise: return "Rise"
            case .default: return "Original"
            case .gold: return "Gold"
            case .pulse: return "Pulse Tone"
            case .chime: return "Chime"
            case .ambientAurora: return "Aurora"
            case .ambientBloom: return "Bloom"
            case .ambientGlass: return "Glass"
            case .ambientNight: return "Night Ambient"
            case .ambientRain: return "Rain"
            case .ambientSpace: return "Space"
            case .ambientDawn: return "Dawn"
            case .ambientLagoon: return "Lagoon"
            case .ambientEmber: return "Ember"
            case .ambientHorizon: return "Horizon"
            case .ambientVelvet: return "Velvet"
            case .ambientCrown: return "Crown"
            }
        }
    }

    enum NotificationTone: String, CaseIterable, Identifiable {
        case message = "notif_message"
        case call = "notif_call"
        case delivered = "notif_delivered"
        case read = "notif_read"
        case ambientSoft = "notif_ambient_soft"
        case ambientGlow = "notif_ambient_glow"
        case ambientDrop = "notif_ambient_drop"
        case ambientPetal = "notif_ambient_petal"
        case ambientWind = "notif_ambient_wind"
        case ambientHalo = "notif_ambient_halo"
        case ambientRipple = "notif_ambient_ripple"
        case ambientSpark = "notif_ambient_spark"
        case ambientMoss = "notif_ambient_moss"
        case ambientLantern = "notif_ambient_lantern"
        case ambientTide = "notif_ambient_tide"
        case ambientBell = "notif_ambient_bell"
        case ambientMist = "notif_ambient_mist"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .message: return "Message"
            case .call: return "Call"
            case .delivered: return "Delivered"
            case .read: return "Read"
            case .ambientSoft: return "Soft"
            case .ambientGlow: return "Glow"
            case .ambientDrop: return "Drop"
            case .ambientPetal: return "Petal"
            case .ambientWind: return "Wind"
            case .ambientHalo: return "Halo"
            case .ambientRipple: return "Ripple"
            case .ambientSpark: return "Spark"
            case .ambientMoss: return "Moss"
            case .ambientLantern: return "Lantern"
            case .ambientTide: return "Tide"
            case .ambientBell: return "Bell"
            case .ambientMist: return "Mist"
            }
        }
    }

    /// Settings → "Ambient UI sounds": swaps every UI cue for its soft-bell `ambient_` variant.
    static var ambientUITheme: Bool {
        get { UserDefaults.standard.bool(forKey: "ambientUITheme") }
        set { UserDefaults.standard.set(newValue, forKey: "ambientUITheme") }
    }

    private static var oneShot: AVAudioPlayer?
    private static var loopPlayer: AVAudioPlayer?

    static var playUISounds: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKey.uiSounds) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.uiSounds) }
    }

    static var selectedRingtone: Ringtone {
        get {
            migrateDefaultRingtone()
            return Ringtone(rawValue: UserDefaults.standard.string(forKey: "selectedRingtone") ?? "") ?? .mrBlindBandit
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedRingtone")
            UserDefaults(suiteName: "group.net.mrblindbandit.app")?.set(callKitRingtoneFile, forKey: "ringtoneFile")
            CallKitManager.shared.refreshRingtone()
        }
    }

    /// One-time 2.0.6 migration: anyone on the old default ("ringtone", or never chose) moves to Mr. BlindBandit;
    /// people who picked another tone keep it.
    nonisolated static func migrateDefaultRingtone(_ d: UserDefaults = .standard) {
        guard !d.bool(forKey: "ringtone.migrated.206") else { return }
        let cur = d.string(forKey: "selectedRingtone")
        if cur == nil || cur == "ringtone" { d.set("ringtone_mrblindbandit", forKey: "selectedRingtone") }
        d.set(true, forKey: "ringtone.migrated.206")
    }

    /// File name CallKit / UNNotificationSound use (must be in the main bundle, ≤ 30 s).
    nonisolated static var callKitRingtoneFile: String? {
        migrateDefaultRingtone()
        let raw = UserDefaults.standard.string(forKey: "selectedRingtone") ?? "ringtone_mrblindbandit"
        for ext in ["caf", "mp3"] {
            if Bundle.main.url(forResource: raw, withExtension: ext) != nil
                || Bundle.main.url(forResource: raw, withExtension: ext, subdirectory: "Sounds") != nil { return "\(raw).\(ext)" }
        }
        return Bundle.main.url(forResource: "ringtone_mrblindbandit", withExtension: "caf") != nil ? "ringtone_mrblindbandit.caf" : nil
    }

    static var selectedNotificationTone: NotificationTone {
        get { NotificationTone(rawValue: UserDefaults.standard.string(forKey: "selectedNotificationTone") ?? "") ?? .message }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectedNotificationTone") }
    }

    /// True while dial tone or US ringback should keep looping (CallKit must not kill it).
    static var isOutgoingProgressActive: Bool { outgoingProgress != .idle }

    /// CallKit / LiveKit-safe session. Outgoing progress uses playAndRecord so mic publish
    /// never hits LiveKit "Audio session category does not support recording" after ambient.
    private static func prepareSession(forCallProgress: Bool = false) {
        let session = AVAudioSession.sharedInstance()
        let progress = forCallProgress || outgoingProgress != .idle
        if progress {
            try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers, .duckOthers])
        } else {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers, .duckOthers])
        }
        try? session.setActive(true)
    }

    /// After CallKit `didActivate`, restart dial/ringback on the voiceChat session.
    static func resumeOutgoingProgressIfNeeded() {
        guard outgoingProgress != .idle else { return }
        prepareSession(forCallProgress: true)
        if let player = loopPlayer, !player.isPlaying {
            player.prepareToPlay()
            player.play()
        } else if outgoingProgress == .ringback {
            startRingback()
        } else if outgoingProgress == .dialTone {
            startDialTone()
        }
    }

    private static func url(named name: String) -> URL? {
        // Outbound US progress tones must never swap to ambient_ringback_outgoing.
        if ambientUITheme,
           !name.hasPrefix("ringtone"),
           !name.hasPrefix("notif_ambient"),
           !name.hasPrefix("ambient_"),
           !name.hasPrefix("ringback_us_"),
           let themed = url(named: "ambient_" + name) { return themed }
        for ext in ["caf"] {
            if let u = Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds") { return u }
        }
        return Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Resources/Sounds")
    }

    private static func playOneShot(named name: String, volume: Float = 0.7) {
        guard playUISounds else { return }
        guard UIApplication.shared.applicationState != .background else { return }
        // Preserve playAndRecord when dial/ringback (or an active CallKit session) is live.
        prepareSession(forCallProgress: outgoingProgress != .idle)
        guard let url = url(named: name) else { return }
        do {
            oneShot = try AVAudioPlayer(contentsOf: url)
            oneShot?.volume = min(max(volume, 0.05), 0.85)
            oneShot?.prepareToPlay()
            oneShot?.play()
        } catch {}
    }

    private static func playLoop(named name: String, volume: Float = 0.45) {
        guard playUISounds else { return }
        // Outbound US dial/ringback must use playAndRecord so CallKit+LiveKit can publish mic.
        let outbound = name.hasPrefix("ringback_us_")
        prepareSession(forCallProgress: outbound)
        stopLoop()
        guard let url = url(named: name) else { return }
        do {
            loopPlayer = try AVAudioPlayer(contentsOf: url)
            loopPlayer?.numberOfLoops = -1
            loopPlayer?.volume = min(max(volume, 0.05), 0.55)
            loopPlayer?.prepareToPlay()
            loopPlayer?.play()
        } catch {}
    }

    static func stopPreview() {
        oneShot?.stop()
        stopLoop()
    }

    static func stopLoop() {
        loopPlayer?.stop()
        loopPlayer = nil
    }

    /// Outgoing progress names (UITest / VoiceOver harnesses).
    static let outgoingDialToneName = "US dial tone"
    static let outgoingRingbackToneName = "US ringback"
    /// Compatibility alias used by the dial-tone UITest harness (phase 1 name).
    static let outgoingProgressToneName = outgoingDialToneName

    private enum OutgoingProgress {
        case idle, dialTone, ringback
    }
    private static var outgoingProgress: OutgoingProgress = .idle

    /// Phase 1 — connecting / pre-ring: continuous US dial tone only (350 Hz + 440 Hz).
    /// No fallback to legacy ringback_outgoing / ambient_ringback_outgoing.
    static func startDialTone() {
        if outgoingProgress == .dialTone, loopPlayer?.isPlaying == true { return }
        guard url(named: "ringback_us_dialtone") != nil else { return }
        playLoop(named: "ringback_us_dialtone", volume: 0.42)
        outgoingProgress = .dialTone
    }

    /// Phase 2 — callee ringing: US ringback only (440 Hz + 480 Hz, 2 s on / 4 s off).
    static func startRingback() {
        if outgoingProgress == .ringback, loopPlayer?.isPlaying == true { return }
        guard url(named: "ringback_us_ringback") != nil else { return }
        playLoop(named: "ringback_us_ringback", volume: 0.42)
        outgoingProgress = .ringback
    }

    static func stopRingback() {
        dialerIdle = false
        outgoingProgress = .idle
        stopLoop()
    }

    /// Stops dial tone and/or ringback (answer / hangup / fail).
    static func stopOutgoingProgress() { stopRingback() }

    // MARK: DTMF (in-call keypad) — ITU Q.23 dual-tone, ~140 ms beep

    private static let dtmfPairs: [String: (Double, Double)] = [
        "1": (697, 1209), "2": (697, 1336), "3": (697, 1477),
        "4": (770, 1209), "5": (770, 1336), "6": (770, 1477),
        "7": (852, 1209), "8": (852, 1336), "9": (852, 1477),
        "*": (941, 1209), "0": (941, 1336), "#": (941, 1477),
    ]
    private static var dtmfPlayer: AVAudioPlayer?

    /// Classic telephone DTMF for in-call keypad taps (0–9, *, #).
    static func playDTMF(_ key: String) {
        guard playUISounds else { return }
        guard let (lo, hi) = dtmfPairs[key] else { return }
        // Never drop to ambient mid-call — CallKit/LiveKit need playAndRecord.
        prepareSession(forCallProgress: true)
        let sr = 44100.0
        let duration = 0.14
        let n = Int(duration * sr)
        var samples = [Int16](repeating: 0, count: n)
        let amp = 0.32
        let fade = Int(0.006 * sr)
        for i in 0..<n {
            let t = Double(i) / sr
            var v = amp * (sin(2 * .pi * lo * t) + sin(2 * .pi * hi * t))
            if i < fade { v *= Double(i) / Double(fade) }
            else if i > n - fade { v *= Double(n - i) / Double(fade) }
            samples[i] = Int16(max(-1, min(1, v)) * 32000)
        }
        var data = Data()
        // Minimal WAV header + PCM
        let dataSize = samples.count * 2
        let fileSize = 36 + dataSize
        func le32(_ x: Int) { data.append(contentsOf: withUnsafeBytes(of: UInt32(x).littleEndian) { Array($0) }) }
        func le16(_ x: Int) { data.append(contentsOf: withUnsafeBytes(of: UInt16(x).littleEndian) { Array($0) }) }
        data.append(contentsOf: [0x52,0x49,0x46,0x46]) // RIFF
        le32(fileSize)
        data.append(contentsOf: [0x57,0x41,0x56,0x45,0x66,0x6D,0x74,0x20]) // WAVEfmt 
        le32(16); le16(1); le16(1); le32(Int(sr)); le32(Int(sr) * 2); le16(2); le16(16)
        data.append(contentsOf: [0x64,0x61,0x74,0x61]) // data
        le32(dataSize)
        for s in samples {
            // bitPattern: PCM sample can be negative; UInt16(Int) traps on < 0
            data.append(contentsOf: withUnsafeBytes(of: UInt16(bitPattern: s).littleEndian) { Array($0) })
        }
        do {
            dtmfPlayer = try AVAudioPlayer(data: data)
            dtmfPlayer?.volume = 0.7
            dtmfPlayer?.prepareToPlay()
            dtmfPlayer?.play()
        } catch {}
    }

    // MARK: Dialer landline session (More → Dialer)

    /// True while Dialer is open waiting for the first digit (idle dial tone).
    private static var dialerIdle = false

    /// Open Dialer → continuous US dial tone until a digit or Call/End.
    static func openDialerIdleTone() {
        dialerIdle = true
        startDialTone()
    }

    /// Each keypad press: kill idle dial tone on first digit, then ITU DTMF.
    static func dialerKeyPress(_ key: String) {
        if dialerIdle || outgoingProgress == .dialTone {
            dialerIdle = false
            stopOutgoingProgress()
        }
        playDTMF(key)
    }

    /// Leave Dialer / End — stop dial, ringback, howler, reorder.
    static func closeDialer() {
        dialerIdle = false
        stopOutgoingProgress()
        stopLoop()
    }

    /// Off-hook howler (ROH) — optional landline cue after long idle or failed End.
    static func startHowler() {
        dialerIdle = false
        guard url(named: "ringback_us_howler") != nil else { return }
        playLoop(named: "ringback_us_howler", volume: 0.32)
        outgoingProgress = .idle
    }

    /// Reorder / all-circuits-busy (480/620 alternate) — optional.
    static func startReorderTone() {
        dialerIdle = false
        guard url(named: "ringback_us_reorder") != nil else { return }
        playLoop(named: "ringback_us_reorder", volume: 0.36)
        outgoingProgress = .idle
    }

    static func playRingtone(preview: Bool = false) {
        if preview {
            stopLoop()
            playOneShot(named: selectedRingtone.rawValue, volume: 0.65)
        } else {
            playLoop(named: selectedRingtone.rawValue, volume: 0.5)
        }
    }

    /// Outbound tap: dial tone only (connecting). No legacy call_initiated / ringback_outgoing cue.
    static func callInitiated() {
        startDialTone()
        CallHaptics.outgoingStart()
        CallHaptics.startRingingPulse()
    }

    static func callConnecting() { CallHaptics.connecting() }

    static func callConnected() {
        stopRingback()
        stopLoop()
        CallHaptics.stopRingingPulse()
        playOneShot(named: "call_connected", volume: 0.55)
        CallHaptics.connected()
    }

    static func hangup() {
        stopRingback()
        stopLoop()
        CallHaptics.stopRingingPulse()
        playOneShot(named: "hangup", volume: 0.65)
        CallHaptics.disconnected()
    }

    static func busyOrFailed() {
        stopRingback()
        stopLoop()
        CallHaptics.stopRingingPulse()
        playOneShot(named: "busy_tone", volume: 0.55)
        CallHaptics.busyOrFailed()
    }

    static func messageSent() {
        playOneShot(named: "message_sent", volume: 0.55)
        CallHaptics.messageSent()
    }

    static func attachmentSent() {
        playOneShot(named: "attachment_sent", volume: 0.55)
        CallHaptics.attachmentSent()
    }

    static func voiceNoteSent() {
        playOneShot(named: "voicenote_sent", volume: 0.6)
        CallHaptics.voiceNoteSent()
    }

    static func typingPing() { playOneShot(named: "typing_ping", volume: 0.3) }

    static func inboundNotification() {
        playOneShot(named: selectedNotificationTone.rawValue, volume: 0.6)
        CallHaptics.inboundMessage()
    }

    static func delivered() {
        playOneShot(named: "notif_delivered", volume: 0.4)
        CallHaptics.delivered()
    }

    static func read() {
        playOneShot(named: "notif_read", volume: 0.35)
        CallHaptics.read()
    }

    static func previewNotification(_ tone: NotificationTone) {
        playOneShot(named: tone.rawValue, volume: 0.6)
    }

    static func previewRingtone(_ tone: Ringtone) {
        stopLoop()
        playOneShot(named: tone.rawValue, volume: 0.65)
    }
}
