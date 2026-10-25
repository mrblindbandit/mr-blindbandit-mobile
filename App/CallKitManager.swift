import AVFoundation
import CallKit
import Intents
import LiveKit
import PushKit
import UIKit

/// Native phone-style calling: CallKit for the system call UI (lock screen, Recents, hold, mute,
/// Bluetooth/CarPlay), PushKit VoIP pushes to ring when the app is closed, and INStartCallIntent so
/// calling back from Recents or Siri reaches the right person.
@MainActor
final class CallKitManager: NSObject {
    static let shared = CallKitManager()
    static let voipTokenKey = "voipPushToken"
    /// CallKit isn't allowed for apps distributed in mainland China; there we fall back to in-app ringing.
    let isAvailable: Bool = (Locale.current.region?.identifier ?? "") != "CN"

    private var provider: CXProvider?

    /// Re-applies the selected ringtone to CallKit after the user changes it.
    func refreshRingtone() {
        guard let provider else { return }
        let config = provider.configuration
        config.ringtoneSound = CallSounds.callKitRingtoneFile
        provider.configuration = config
        UserDefaults(suiteName: "group.net.mrblindbandit.app")?.set(config.ringtoneSound, forKey: "ringtoneFile")
    }
    private let controller = CXCallController()
    private var registry: PKPushRegistry?
    private weak var service: ProductionCommunicationsService?
    private var uuids: [String: UUID] = [:]
    private var outgoing: Set<String> = []
    private var answered: Set<String> = []
    private var pendingAnswer: String?
    private var pendingIncoming: [String: BlindbanditIncomingCall] = [:]
    /// Calls CallKit has accepted (reportNewIncomingCall / CXStartCallAction finished). Ending a call
    /// before this point makes iOS drop it from Recents, so ends are queued until it's registered.
    private var registered: Set<UUID> = []
    private var pendingEnds: [UUID: CXCallEndedReason] = [:]
    private var connected: Set<String> = []
    private var pendingCallBack: (value: String, name: String, video: Bool)?

    /// Called from AppDelegate.didFinishLaunching so VoIP pushes delivered at cold launch are handled.
    func setUp() {
        guard provider == nil else { return }
        Task { await EndedCalls.flushPending() }
        if isAvailable {
            let config = CXProviderConfiguration()
            config.supportsVideo = true
            config.maximumCallGroups = 2
            config.maximumCallsPerCallGroup = 1
            config.supportedHandleTypes = [.generic]
            config.includesCallsInRecents = true
            if let icon = UIImage(named: "CallKitIcon") { config.iconTemplateImageData = icon.pngData() }
            // 2.0.6: the selected ringtone (default Mr. BlindBandit) instead of a hard-coded tone.
            config.ringtoneSound = CallSounds.callKitRingtoneFile
            UserDefaults(suiteName: "group.net.mrblindbandit.app")?.set(config.ringtoneSound, forKey: "ringtoneFile")
            let provider = CXProvider(configuration: config)
            provider.setDelegate(self, queue: nil)
            self.provider = provider
            // LiveKit must only run audio inside CallKit's activation window.
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
            try? AudioManager.shared.setEngineAvailability(.none)
        }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    func attach(_ service: ProductionCommunicationsService) {
        self.service = service
        for call in pendingIncoming.values { service.receiveIncoming(call) }
        pendingIncoming = [:]
        if let id = pendingAnswer {
            pendingAnswer = nil
            Task { await service.performJoin(id: id) }
        }
        if let back = pendingCallBack {
            pendingCallBack = nil
            callBack(value: back.value, name: back.name, video: back.video)
        }
    }

    func hasCall(_ callID: String) -> Bool { uuids[callID] != nil }

    /// 2.0.6: the outgoing UI is shown under a local ID before the server call exists; move all state to the real ID.
    func rebind(from old: String, to new: String) {
        guard let id = uuids.removeValue(forKey: old) else { return }
        uuids[new] = id
        if outgoing.remove(old) != nil { outgoing.insert(new) }
        if connected.remove(old) != nil { connected.insert(new) }
        if answered.remove(old) != nil { answered.insert(new) }
    }

    private func uuid(for callID: String) -> UUID {
        if let existing = uuids[callID] { return existing }
        let new = UUID()
        uuids[callID] = new
        return new
    }

    private func callID(for uuid: UUID) -> String? { uuids.first(where: { $0.value == uuid })?.key }

    // MARK: Outgoing

    func startOutgoing(callID: String, handle: String, displayName: String, video: Bool, groupID: String? = nil, memberCount: Int? = nil) {
        guard isAvailable else { return }
        let id = uuid(for: callID)
        outgoing.insert(callID)
        let identity = CallKitManager.identity(handle: groupID == nil ? handle : "", name: displayName, groupID: groupID, groupName: groupID == nil ? nil : displayName, memberCount: memberCount)
        let cxHandle = CXHandle(type: .generic, value: identity.handle)
        let action = CXStartCallAction(call: id, handle: cxHandle)
        action.isVideo = video
        action.contactIdentifier = identity.name
        CallKitManager.donate(handle: identity.handle, name: identity.name, video: video)
        controller.request(CXTransaction(action: action)) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil else { self.uuids[callID] = nil; self.outgoing.remove(callID); return }
                self.registered.insert(id)
                let update = CXCallUpdate()
                update.remoteHandle = cxHandle
                update.localizedCallerName = identity.name
                update.supportsHolding = true
                update.hasVideo = video
                update.supportsGrouping = false
                update.supportsUngrouping = false
                update.supportsDTMF = false
                self.provider?.reportCall(with: id, updated: update)
                self.provider?.reportOutgoingCall(with: id, startedConnectingAt: Date())
                self.flushPendingEnd(id)
            }
        }
    }

    func reportOutgoingConnected(callID: String) {
        guard let id = uuids[callID], outgoing.contains(callID), !connected.contains(callID) else { return }
        connected.insert(callID)
        provider?.reportOutgoingCall(with: id, connectedAt: Date())
        if ExtraFeatures220.liveActivitiesForCalls {
            let handle = BanditSharedStore.defaults.string(forKey: "live.lastOutgoingHandle") ?? callID
            AppleNativeBootstrap.onCallConnected(callID: callID, handle: handle, displayName: handle, startedAt: Date(), muted: false, onSpeaker: false)
        }
    }

    // MARK: Incoming

    func reportIncoming(_ call: BlindbanditIncomingCall, completion: (() -> Void)? = nil) {
        guard isAvailable, let provider else {
            // In-app ringing instead of the system UI.
            if UIApplication.shared.applicationState == .active { CallSounds.playRingtone() }
            completion?()
            return
        }
        if uuids[call.id] != nil { completion?(); return }
        let id = uuid(for: call.id)
        let update = CXCallUpdate()
        let identity = CallKitManager.identity(handle: call.from_handle, name: call.from_name, groupID: call.group_id, groupName: call.group_name)
        update.remoteHandle = CXHandle(type: .generic, value: identity.handle)
        update.localizedCallerName = identity.name
        update.hasVideo = call.isVideo
        update.supportsHolding = true
        CallKitManager.donate(handle: identity.handle, name: identity.name, video: call.isVideo, incoming: true, avatarURL: call.from_avatar_url)
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportNewIncomingCall(with: id, update: update) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil { self.uuids[call.id] = nil; self.pendingEnds[id] = nil }
                else {
                    self.registered.insert(id); self.flushPendingEnd(id)
                    if ExtraFeatures220.liveActivitiesForCalls {
                        AppleNativeBootstrap.onCallRinging(callID: call.id, handle: identity.handle, displayName: identity.name)
                    }
                    LiveCommunicationBridge.prepareIncomingPresentation(handle: identity.handle, displayName: identity.name)
                }
            }
            completion?()
        }
    }

    /// Tells CallKit the call is over so iOS writes it to Recents. With no explicit reason:
    /// a connected call is "remote ended", a never-answered one is "unanswered" (a missed call).
    func reportEnded(callID: String, reason: CXCallEndedReason?) {
        guard let id = uuids.removeValue(forKey: callID) else { return }
        let wasConnected = answered.contains(callID) || connected.contains(callID)
        outgoing.remove(callID)
        answered.remove(callID)
        connected.remove(callID)
        let final = reason ?? CallKitManager.endReason(wasConnected: wasConnected)
        if registered.contains(id) {
            registered.remove(id)
            provider?.reportCall(with: id, endedAt: Date(), reason: final)
        } else {
            pendingEnds[id] = final
        }
        AppleNativeBootstrap.onCallEnded()
    }

    nonisolated static func endReason(wasConnected: Bool) -> CXCallEndedReason {
        wasConnected ? .remoteEnded : .unanswered
    }

    private func flushPendingEnd(_ id: UUID) {
        guard let reason = pendingEnds.removeValue(forKey: id) else { return }
        registered.remove(id)
        provider?.reportCall(with: id, endedAt: Date(), reason: reason)
    }

    func reportVideo(callID: String, video: Bool) {
        guard let id = uuids[callID] else { return }
        let update = CXCallUpdate()
        update.hasVideo = video
        provider?.reportCall(with: id, updated: update)
    }

    // MARK: Requests from in-app buttons (completion(false) means "do it yourself")

    func requestAnswer(callID: String, completion: @escaping (Bool) -> Void) {
        guard let id = uuids[callID] else { completion(false); return }
        controller.request(CXTransaction(action: CXAnswerCallAction(call: id))) { error in
            Task { @MainActor in completion(error == nil) }
        }
    }

    func requestEnd(callID: String, completion: @escaping (Bool) -> Void) {
        guard let id = uuids[callID] else { completion(false); return }
        controller.request(CXTransaction(action: CXEndCallAction(call: id))) { error in
            Task { @MainActor in completion(error == nil) }
        }
    }

    func requestMute(callID: String, muted: Bool) {
        guard let id = uuids[callID] else { return }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: id, muted: muted))) { _ in }
    }

    // MARK: Recents / Siri

    /// Tapping a Blindbandit call in the Phone app's Recents (or "Call @handle with Blindbandit").
    func handle(userActivity: NSUserActivity) {
        guard let intent = userActivity.interaction?.intent as? INStartCallIntent,
              let person = intent.contacts?.first else { return }
        let value = person.personHandle?.value ?? person.displayName
        guard !value.isEmpty else { return }
        let video = intent.callCapability == .videoCall
        guard service != nil else { pendingCallBack = (value, person.displayName, video); return }
        callBack(value: value, name: person.displayName, video: video)
    }

    private func callBack(value: String, name: String, video: Bool) {
        Task {
            guard let service else { return }
            if let groupID = CallKitManager.groupID(forHandle: value) {
                await service.startGroupCall(groupID: groupID, groupName: CallKitManager.groupName(forHandle: value) ?? name, video: video)
            } else {
                await service.startCall(recipient: CallKitManager.recentsHandle(value), video: video)
            }
        }
    }

    /// Recents stores "@handle"; map it (or a bare handle) back to the username to call.
    nonisolated static func recentsHandle(_ value: String) -> String {
        BlindbanditHandle.normalize(value.hasPrefix("@") ? String(value.dropFirst()) : value)
    }

    // MARK: Caller identity (never a UUID or call id on any system surface)

    private static let groupMapKey = "callkit.groupHandles"

    /// What CallKit, Recents, the lock screen and car displays show. 1:1: "@handle" + display name.
    /// Group: a readable handle like "Family (3 people)" mapped privately to the group id for call-back.
    static func identity(handle: String, name: String, groupID: String?, groupName: String?, memberCount: Int? = nil) -> (handle: String, name: String) {
        if let groupID {
            let base = (groupName?.isEmpty == false ? groupName! : "Group call")
            let label = memberCount.map { "\(base) (\($0) people)" } ?? base
            var map = UserDefaults.standard.dictionary(forKey: groupMapKey) as? [String: String] ?? [:]
            map[label] = groupID
            UserDefaults.standard.set(map, forKey: groupMapKey)
            return (label, label)
        }
        let clean = BlindbanditHandle.normalize(handle)
        let at = clean.isEmpty ? "" : "@\(clean)"
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let display = !trimmed.isEmpty && trimmed != "Someone" ? trimmed : (at.isEmpty ? "Blind Bandit call" : at)
        return (at.isEmpty ? display : at, display)
    }

    static func groupID(forHandle value: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: groupMapKey) as? [String: String])?[value]
    }

    static func groupName(forHandle value: String) -> String? {
        groupID(forHandle: value) == nil ? nil : value.replacingOccurrences(of: #" \(\d+ people\)$"#, with: "", options: .regularExpression)
    }

    /// Donates the call so Recents and Siri suggestions can call back by name.
    static func donate(handle: String, name: String, video: Bool, incoming: Bool = false, avatarURL: String? = nil) {
        Task {
            let image = await ProfilePhotoPrep.intentImage(from: avatarURL)
            await MainActor.run {
                let person = INPerson(personHandle: INPersonHandle(value: handle, type: .unknown, label: nil), nameComponents: nil,
                                      displayName: name, image: image, contactIdentifier: nil, customIdentifier: handle)
                let intent = INStartCallIntent(callRecordFilter: nil, callRecordToCallBack: nil, audioRoute: .unknown,
                                               destinationType: .normal, contacts: [person],
                                               callCapability: video ? .videoCall : .audioCall)
                let interaction = INInteraction(intent: intent, response: nil)
                interaction.direction = incoming ? .incoming : .outgoing
                interaction.donate(completion: nil)
            }
        }
    }

    // MARK: VoIP payload

    static let myIDKey = "calls.myProfileID", myHandleKey = "calls.myHandle"

    /// True unless the push names a callee that isn't the signed-in account.
    nonisolated static func isAddressedToMe(_ payload: [AnyHashable: Any]) -> Bool {
        let root = (payload["data"] as? [AnyHashable: Any]) ?? payload
        let d = UserDefaults.standard
        let myID = d.string(forKey: myIDKey) ?? "", myHandle = (d.string(forKey: myHandleKey) ?? "").lowercased()
        let ids = ["user_id", "callee_id", "to_user_id", "recipient_id"].compactMap { root[$0] as? String }.filter { !$0.isEmpty }
        let handles = ["callee_handle", "to_handle"].compactMap { root[$0] as? String }.map { $0.lowercased().replacingOccurrences(of: "@", with: "") }.filter { !$0.isEmpty }
        if let from = root["from_handle"] as? String, !myHandle.isEmpty, from.lowercased() == myHandle,
           (root["type"] as? String ?? "call") == "call", (root["group_id"] as? String) == nil { return false } // my own outgoing call
        if !ids.isEmpty, !myID.isEmpty, !ids.contains(myID) { return false }
        if !handles.isEmpty, !myHandle.isEmpty, !handles.contains(myHandle) { return false }
        return true
    }

    /// True when the push looks like the server's "answered on another device" echo (not a real hang-up).
    nonisolated static func isAnsweredElsewhereEcho(_ payload: [AnyHashable: Any]) -> Bool {
        let root = (payload["data"] as? [AnyHashable: Any]) ?? payload
        var parts: [String] = []
        for key in ["reason", "message", "body", "title", "alert"] {
            if let s = root[key] as? String { parts.append(s) }
        }
        if let aps = root["aps"] as? [AnyHashable: Any] {
            if let s = aps["alert"] as? String { parts.append(s) }
            if let alert = aps["alert"] as? [AnyHashable: Any] {
                if let s = alert["body"] as? String { parts.append(s) }
                if let s = alert["title"] as? String { parts.append(s) }
            }
        }
        let blobs = parts.joined(separator: " ").lowercased()
        return blobs.contains("another device") || blobs.contains("answered elsewhere") || blobs.contains("answered on another")
    }

    /// Parses `{type:'call'|'call_end', call_id, kind, from_handle, from_name, group_id?, group_name?}`.
    nonisolated static func parseVoIP(_ payload: [AnyHashable: Any]) -> (type: String, call: BlindbanditIncomingCall?) {
        let root = (payload["data"] as? [AnyHashable: Any]) ?? payload
        func str(_ k: String) -> String? {
            if let s = root[k] as? String, !s.isEmpty { return s }
            if let n = root[k] as? NSNumber { return n.stringValue }
            return nil
        }
        let type = str("type") ?? "call"
        guard let id = str("call_id") ?? str("id") else { return (type, nil) }
        let handle = str("from_handle") ?? ""
        let createdMs: Double = {
            if let s = str("created_at"), let d = Double(s) { return d }
            if let n = root["created_at"] as? NSNumber { return n.doubleValue }
            return Date().timeIntervalSince1970 * 1000
        }()
        let call = BlindbanditIncomingCall(
            id: id, kind: str("kind") ?? "voice", from_handle: handle,
            from_name: str("from_name") ?? (handle.isEmpty ? "Someone" : "@\(handle)"),
            group_id: str("group_id"), group_name: str("group_name"),
            created_at: createdMs,
            from_avatar_url: str("from_avatar_url") ?? str("avatar_url")
        )
        return (type, call)
    }
}

extension CallKitManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated {
            if !uuids.isEmpty { service?.finishCall(notifyServer: true, announcement: "Call ended.") }
            uuids = [:]
            registered = []
            pendingEnds = [:]
            connected = []
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated {
            guard let callID = callID(for: action.callUUID) else { action.fail(); return }
            answered.insert(callID)
            connected.insert(callID)
            if let service {
                Task { await service.performJoin(id: callID) }
            } else {
                pendingAnswer = callID // joined once the app is unlocked and signed in
            }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated {
            guard let callID = callID(for: action.callUUID) else { action.fulfill(); return }
            EndedCalls.mark(callID)
            let wasConnected = answered.contains(callID) || outgoing.contains(callID)
            uuids[callID] = nil
            registered.remove(action.callUUID)
            connected.remove(callID)
            outgoing.remove(callID)
            answered.remove(callID)
            pendingIncoming[callID] = nil
            if let service {
                if wasConnected || service.activeCallID == callID {
                    service.finishCall(notifyServer: true, announcement: "Call ended.")
                } else {
                    service.performDecline(id: callID)
                }
            } else {
                Task { await BlindbanditAPI.declineCall(id: callID) }
            }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        MainActor.assumeIsolated {
            service?.setMic(enabled: !action.isMuted)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        MainActor.assumeIsolated {
            service?.setHold(action.isOnHold)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
        try? AudioManager.shared.setEngineAvailability(.default)
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        try? AudioManager.shared.setEngineAvailability(.none)
    }
}

extension CallKitManager: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: CallKitManager.voipTokenKey)
        NotificationCenter.default.post(name: .apnsDeviceTokenUpdated, object: UserDefaults.standard.string(forKey: "apnsDeviceToken") ?? "")
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        UserDefaults.standard.removeObject(forKey: CallKitManager.voipTokenKey)
    }

    /// iOS requires every VoIP push to be reported to CallKit right away, or the app is terminated.
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let parsed = CallKitManager.parseVoIP(payload.dictionaryPayload)
        MainActor.assumeIsolated {
            guard let call = parsed.call else {
                // Malformed push: report and immediately end a stand-in call to satisfy the system rule.
                let id = UUID().uuidString
                reportIncoming(BlindbanditIncomingCall(id: id, kind: "voice", from_handle: "", from_name: "Blind Bandit call", group_id: nil, group_name: nil, created_at: 0)) { [weak self] in
                    Task { @MainActor in self?.reportEnded(callID: id, reason: .failed) }
                    completion()
                }
                return
            }
            // 2.0.5: only ring for invites addressed to the signed-in account.
            if !CallKitManager.isAddressedToMe(payload.dictionaryPayload) {
                let id = UUID().uuidString
                reportIncoming(BlindbanditIncomingCall(id: id, kind: "voice", from_handle: "", from_name: "Blind Bandit call", group_id: nil, group_name: nil, created_at: 0)) { [weak self] in
                    Task { @MainActor in self?.reportEnded(callID: id, reason: .failed) }
                    completion()
                }
                return
            }
            if parsed.type == "call_end" {
                // The server historically sent "answered on another device" to the answering install too.
                // Never tear down a call THIS device is joining / just joined / already answered when
                // the push is that echo (or within the post-join grace window).
                let echo = CallKitManager.isAnsweredElsewhereEcho(payload.dictionaryPayload)
                    || (service?.shouldIgnoreAnswerEcho(callID: call.id) == true)
                if echo && (answered.contains(call.id) || connected.contains(call.id)
                            || service?.joiningCallID == call.id || service?.activeCallID == call.id) {
                    CallTiming.log("ignored answered-elsewhere call_end for \(call.id)")
                    completion(); return
                }
                if service?.joiningCallID == call.id {
                    completion(); return
                }
                if uuids[call.id] != nil {
                    let reason = CallKitManager.endReason(wasConnected: answered.contains(call.id) || connected.contains(call.id))
                    service?.remoteEnded(callID: call.id)
                    // remoteEnded may have no-op'd on echo; only reportEnded if we are no longer in that call.
                    if service?.activeCallID != call.id && service?.joiningCallID != call.id {
                        reportEnded(callID: call.id, reason: reason)
                    }
                    completion()
                } else {
                    // Never saw the ring (app was killed): log it as a missed call so it's in Recents.
                    reportIncoming(call) { [weak self] in
                        Task { @MainActor in self?.reportEnded(callID: call.id, reason: .unanswered) }
                        completion()
                    }
                }
                return
            }
            // 2.0.6: never ring again for a call this user already ended, or one that's too old to still be ringing.
            if EndedCalls.shouldIgnore(id: call.id, createdAtMs: call.created_at) {
                CallTiming.log("VoIP push ignored for ended/stale call \(call.id)")
                let id = "ignored-" + call.id + "-" + UUID().uuidString
                reportIncoming(BlindbanditIncomingCall(id: id, kind: call.kind, from_handle: call.from_handle, from_name: call.from_name, group_id: call.group_id, group_name: call.group_name, created_at: call.created_at)) { [weak self] in
                    Task { @MainActor in self?.reportEnded(callID: id, reason: .remoteEnded) }
                    completion()
                }
                return
            }
            reportIncoming(call, completion: completion)
            if let service { service.receiveIncoming(call) } else { pendingIncoming[call.id] = call }
        }
    }
}
