import Foundation
import CallKit
import AVFoundation

final class CallKitController: NSObject, CXProviderDelegate {
    var onAnswer: ((UUID) -> Void)?
    var onEnd: ((UUID) -> Void)?
    var onMute: ((UUID, Bool) -> Void)?

    private let provider: CXProvider
    private let callController = CXCallController()

    override init() {
        let configuration = CXProviderConfiguration(localizedName: "Mr. Blind Bandit")
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.phoneNumber, .generic]
        // Apple does not expose the user's ringtone library to third-party apps.
        // nil intentionally uses the iOS system default ringtone.
        configuration.ringtoneSound = nil

        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncoming(uuid: UUID, remoteName: String, phoneNumber: String, video: Bool) {
        let update = CXCallUpdate()
        update.hasVideo = video
        update.localizedCallerName = remoteName
        update.remoteHandle = CXHandle(type: phoneNumber.isEmpty ? .generic : .phoneNumber,
                                       value: phoneNumber.isEmpty ? remoteName : phoneNumber)
        update.supportsDTMF = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if error != nil {
                // The in-app call screen remains available even if CallKit cannot present.
                return
            }
        }
    }

    func startOutgoing(uuid: UUID, remoteName: String, phoneNumber: String, video: Bool) {
        let handle = CXHandle(type: phoneNumber.isEmpty ? .generic : .phoneNumber,
                              value: phoneNumber.isEmpty ? remoteName : phoneNumber)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = video
        let transaction = CXTransaction(action: action)

        callController.request(transaction) { [weak self] error in
            guard error == nil else { return }
            self?.provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
        }
    }

    func reportConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    func requestAnswer(uuid: UUID) {
        let transaction = CXTransaction(action: CXAnswerCallAction(call: uuid))
        callController.request(transaction) { _ in }
    }

    func requestEnd(uuid: UUID) {
        let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
        callController.request(transaction) { _ in }
    }

    func reportEnded(uuid: UUID, reason: CXCallEndedReason) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    }

    func providerDidReset(_ provider: CXProvider) {
        // CallKit has reset its state. The communication manager owns room teardown.
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        onAnswer?(action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        onEnd?(action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        onMute?(action.callUUID, action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // LiveKit manages AVAudioSession for this development build. A production PushKit
        // integration can take over audio-engine timing here if needed.
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    }
}
