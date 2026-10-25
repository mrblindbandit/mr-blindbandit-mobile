import AuthenticationServices
import Foundation
import UIKit
import os

private let log = Logger(subsystem: "net.mrblindbandit.app", category: "Passkeys")

/// Deeper Passkeys alongside Sign in with Apple (ASAuthorizationPlatformPublicKeyCredential*).
@MainActor
final class PasskeyAuthController: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = PasskeyAuthController()
    private var continuation: CheckedContinuation<ASAuthorization?, Error>?

    func register(userID: Data, userName: String, challenge: Data, rpId: String) async throws -> ASAuthorization? {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userID)
        return try await perform([request])
    }

    func assert(challenge: Data, rpId: String, allowedCredentials: [Data] = []) async throws -> ASAuthorization? {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        if !allowedCredentials.isEmpty {
            request.allowedCredentials = allowedCredentials.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
        }
        return try await perform([request])
    }

    private func perform(_ requests: [ASAuthorizationRequest]) async throws -> ASAuthorization? {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        log.notice("Passkey authorization completed type=\(String(describing: type(of: authorization.credential)), privacy: .public)")
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        log.error("Passkey error: \(error.localizedDescription, privacy: .public)")
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
