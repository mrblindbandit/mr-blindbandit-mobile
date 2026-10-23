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
    private let controller = CXCallController()
    private var registry: PKPushRegistry?
    private weak var service: ProductionCommunicationsService?
    private var uuids: [String: UUID] = [:]
    private var outgoing: Set<String> = []
    private var answered: Set<String> = []
    private var pendingAnswer: String?
    private var pendingIncoming: [String: BlindbanditIncomingCall] = [:]

    /// Called from AppDelegate.didFinishLaunching so VoIP pushes delivered at cold launch are handled.
    func setUp() {
        guard provider == nil else { return }
        if isAvailable {
            let config = CXProviderConfiguration()
            config.supportsVideo = true
            config.maximumCallGroups = 2
            config.maximumCallsPerCallGroup = 1
            config.supportedHandleTypes = [.generic]
            config.includesCallsInRecents = true
            if let icon = UIImage(named: "CallKitIcon") { config.iconTemplateImageData = icon.pngData() }
            if Bundle.main.url(forResource: "ringtone_ambient_dawn", withExtension: "mp3") != nil {
                config.ringtoneSound = "ringtone_ambient_dawn.mp3"
            }
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
    }

    func hasCall(_ callID: String) -> Bool { uuids[callID] != nil }

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
            guard error == nil else { return }
            Task { @MainActor in
                let update = CXCallUpdate()
                update.remoteHandle = cxHandle
                update.localizedCallerName = identity.name
                update.supportsHolding = true
                update.hasVideo = video
                self?.provider?.reportCall(with: id, updated: update)
                self?.provider?.reportOutgoingCall(with: id, startedConnectingAt: Date())
            }
        }
    }

    func reportOutgoingConnected(callID: String) {
        guard let id = uuids[callID], outgoing.contains(callID) else { return }
        provider?.reportOutgoingCall(with: id, connectedAt: Date())
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
        CallKitManager.donate(handle: identity.handle, name: identity.name, video: call.isVideo)
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportNewIncomingCall(with: id, update: update) { [weak self] error in
            if error != nil { Task { @MainActor in self?.uuids[call.id] = nil } }
            completion?()
        }
    }

    func reportEnded(callID: String, reason: CXCallEndedReason?) {
        guard let id = uuids.removeValue(forKey: callID) else { return }
        outgoing.remove(callID)
        answered.remove(callID)
        if let reason { provider?.reportCall(with: id, endedAt: Date(), reason: reason) }
        else { provider?.reportCall(with: id, endedAt: Date(), reason: .remoteEnded) }
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
        Task {
            guard let service else { return }
            if let groupID = CallKitManager.groupID(forHandle: value) {
                await service.startGroupCall(groupID: groupID, groupName: CallKitManager.groupName(forHandle: value) ?? person.displayName, video: video)
            } else {
                await service.startCall(recipient: value, video: video)
            }
        }
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
    static func donate(handle: String, name: String, video: Bool) {
        let person = INPerson(personHandle: INPersonHandle(value: handle, type: .unknown), nameComponents: nil,
                              displayName: name, image: nil, contactIdentifier: nil, customIdentifier: handle)
        let intent = INStartCallIntent(callRecordFilter: nil, callRecordToCallBack: nil, audioRoute: .unknown,
                                       destinationType: .normal, contacts: [person],
                                       callCapability: video ? .videoCall : .audioCall)
        INInteraction(intent: intent, response: nil).donate(completion: nil)
    }

    // MARK: VoIP payload

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
        let call = BlindbanditIncomingCall(
            id: id, kind: str("kind") ?? "voice", from_handle: handle,
            from_name: str("from_name") ?? (handle.isEmpty ? "Someone" : "@\(handle)"),
            group_id: str("group_id"), group_name: str("group_name"),
            created_at: Date().timeIntervalSince1970 * 1000
        )
        return (type, call)
    }
}

extension CallKitManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated {
            for id in uuids.keys { service?.finishCall(notifyServer: true, announcement: "Call ended.") ; _ = id }
            uuids = [:]
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated {
            guard let callID = callID(for: action.callUUID) else { action.fail(); return }
            answered.insert(callID)
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
            let wasConnected = answered.contains(callID) || outgoing.contains(callID)
            uuids[callID] = nil
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
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
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
            if parsed.type == "call_end" {
                if uuids[call.id] != nil {
                    service?.remoteEnded(callID: call.id)
                    reportEnded(callID: call.id, reason: .answeredElsewhere)
                    completion()
                } else {
                    reportIncoming(call) { [weak self] in
                        Task { @MainActor in self?.reportEnded(callID: call.id, reason: .remoteEnded) }
                        completion()
                    }
                }
                return
            }
            reportIncoming(call, completion: completion)
            if let service { service.receiveIncoming(call) } else { pendingIncoming[call.id] = call }
        }
    }
}
