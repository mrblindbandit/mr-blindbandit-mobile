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
            case .mrBlindBandit: return "Mr. BlindBandit (Default)"
            case .mrBlindBanditClassic: return "Mr. BlindBandit Classic"
            case .mrBlindBanditAlt: return "Mr. BlindBandit Alt"
            case .mrBlindBanditNight: return "Mr. BlindBandit Night"
            case .mrBlindBanditPulse: return "Mr. BlindBandit Pulse"
            case .default: return "Original"
            case .gold: return "Gold"
            case .pulse: return "Pulse"
            case .chime: return "Chime"
            case .ambientAurora: return "Ambient · Aurora"
            case .ambientBloom: return "Ambient · Bloom"
            case .ambientGlass: return "Ambient · Glass"
            case .ambientNight: return "Ambient · Night"
            case .ambientRain: return "Ambient · Rain"
            case .ambientSpace: return "Ambient · Space"
            case .ambientDawn: return "Ambient · Dawn"
            case .ambientLagoon: return "Ambient · Lagoon"
            case .ambientEmber: return "Ambient · Ember"
            case .ambientHorizon: return "Ambient · Horizon"
            case .ambientVelvet: return "Ambient · Velvet"
            case .ambientCrown: return "Ambient · Crown"
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
            case .ambientSoft: return "Ambient · Soft"
            case .ambientGlow: return "Ambient · Glow"
            case .ambientDrop: return "Ambient · Drop"
            case .ambientPetal: return "Ambient · Petal"
            case .ambientWind: return "Ambient · Wind"
            case .ambientHalo: return "Ambient · Halo"
            case .ambientRipple: return "Ambient · Ripple"
            case .ambientSpark: return "Ambient · Spark"
            case .ambientMoss: return "Ambient · Moss"
            case .ambientLantern: return "Ambient · Lantern"
            case .ambientTide: return "Ambient · Tide"
            case .ambientBell: return "Ambient · Bell"
            case .ambientMist: return "Ambient · Mist"
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

    private static func prepareSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
    }

    private static func url(named name: String) -> URL? {
        if ambientUITheme, !name.hasPrefix("ringtone"), !name.hasPrefix("notif_ambient"), !name.hasPrefix("ambient_"),
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
        prepareSession()
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
        prepareSession()
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

    static func startRingback() { playLoop(named: "ringback_outgoing", volume: 0.42) }
    static func stopRingback() { stopLoop() }

    static func playRingtone(preview: Bool = false) {
        if preview {
            stopLoop()
            playOneShot(named: selectedRingtone.rawValue, volume: 0.65)
        } else {
            playLoop(named: selectedRingtone.rawValue, volume: 0.5)
        }
    }

    static func callInitiated() {
        startRingback()
        playOneShot(named: "call_initiated", volume: 0.55)
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
