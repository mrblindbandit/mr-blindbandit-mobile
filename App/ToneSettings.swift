import SwiftUI
import UserNotifications

/// Ringtone / text tone chooser. Tapping a row previews it and marks it selected without closing;
/// Done saves, Cancel reverts. Any preview stops when the sheet closes.
struct TonePickerSheet<Tone: Identifiable & Hashable>: View {
    let title: String
    let tones: [Tone]
    let name: (Tone) -> String
    let preview: (Tone) -> Void
    let save: (Tone) -> Void
    @State var selection: Tone
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(tones) { tone in
                Button {
                    selection = tone
                    preview(tone)
                } label: {
                    HStack {
                        Text(name(tone)).foregroundStyle(.primary)
                        Spacer()
                        if tone == selection {
                            Image(systemName: "checkmark").foregroundStyle(Brand.goldDeep).accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(tone == selection ? [.isSelected] : [])
                .accessibilityHint("Plays a preview")
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(selection); dismiss() }.bold()
                }
            }
        }
        .onDisappear { CallSounds.stopPreview() }
    }
}

/// Settings → "Send test notification".
enum TestNotification {
    enum Outcome { case sentByServer, localFallback(String), failed(String) }

    @MainActor
    static func send(auth: ClerkAuthService) async -> Outcome {
        if let token = try? await auth.sessionToken(), !token.isEmpty {
            var request = URLRequest(url: URL(string: "https://mrblindbandit.net/api/push/test")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("https://mrblindbandit.net", forHTTPHeaderField: "Origin")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{\"platform\":\"ios\"}".utf8)
            request.timeoutInterval = 15
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) {
                return .sentByServer
            }
        }
        return await local(note: "Server test notifications aren't available yet, so this one was sent from your iPhone.")
    }

    private static func local(note: String) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            return .failed("Notifications are off. Turn them on to receive a test notification.")
        }
        let content = UNMutableNotificationContent()
        content.title = "Blind Bandit"
        content.body = "Test notification: alerts are working on this iPhone."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "bb-test-\(UUID().uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        do { try await center.add(request); return .localFallback(note) }
        catch { return .failed("Couldn't send a test notification.") }
    }
}
