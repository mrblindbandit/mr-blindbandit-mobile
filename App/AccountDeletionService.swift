import Foundation
import ClerkKit

@MainActor
enum AccountDeletionService {
    static func deleteBlindbanditData() async throws {
        guard let token = try await Clerk.shared.auth.getToken(), !token.isEmpty else {
            throw AuthServiceError.noActiveSession
        }
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("v1/mobile-native/account-data"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "confirmation": "DELETE MY BLINDBANDIT DATA"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommunicationsError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message: String
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? [String: Any],
               let serverMessage = error["message"] as? String {
                message = serverMessage
            } else {
                message = "Blindbandit data deletion returned HTTP \(http.statusCode)."
            }
            throw CommunicationsError.server(message)
        }
    }
}
