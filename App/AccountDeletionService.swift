import Foundation

@MainActor
enum AccountDeletionService {
    /// Asks the Blindbandit API to erase the social profile, messages, call history and device
    /// tokens linked to this account (`POST /v1/privacy/delete`). The Clerk user is deleted
    /// afterwards by `ClerkAuthService.requestAccountDeletion()`.
    static func deleteBlindbanditData() async throws {
        try await BlindbanditAPI.requestAccountDataDeletion()
    }
}
