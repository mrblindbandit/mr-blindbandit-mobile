import SwiftUI
import UIKit
import UserNotifications
import AVFoundation
import Photos

extension Notification.Name {
    static let apnsDeviceTokenUpdated = Notification.Name("apnsDeviceTokenUpdated")
    static let apnsRegistrationFailed = Notification.Name("apnsRegistrationFailed")
    static let pushDeepLinkReceived = Notification.Name("pushDeepLinkReceived")
    static let blindbanditCallDeepLinkReceived = Notification.Name("blindbanditCallDeepLinkReceived")
    static let blindbanditMessageDeepLinkReceived = Notification.Name("blindbanditMessageDeepLinkReceived")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "apnsDeviceToken")
        UserDefaults.standard.removeObject(forKey: "apnsRegistrationError")
        NotificationCenter.default.post(name: .apnsDeviceTokenUpdated, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let message = error.localizedDescription
        UserDefaults.standard.set(message, forKey: "apnsRegistrationError")
        NotificationCenter.default.post(name: .apnsRegistrationFailed, object: message)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let rawURL = userInfo["url"] as? String,
           let url = URL(string: rawURL),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            routePushURL(url)
        } else if let rawLink = userInfo["deep_link"] as? String,
                  let url = URL(string: rawLink, relativeTo: URL(string: "https://mrblindbandit.net")) {
            routePushURL(url)
        }
        completionHandler()
    }

    private func routePushURL(_ url: URL) {
        if url.path.hasPrefix("/mobile/calls"),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
           let callID = components.queryItems?.first(where: { $0.name == "id" })?.value,
           !callID.isEmpty {
            NotificationCenter.default.post(name: .blindbanditCallDeepLinkReceived, object: callID)
            return
        }
        if url.path.hasPrefix("/mobile/messages") {
            NotificationCenter.default.post(name: .blindbanditMessageDeepLinkReceived, object: url)
            return
        }
        NotificationCenter.default.post(name: .pushDeepLinkReceived, object: url)
    }
}

@MainActor
final class PushNotifications: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String = UserDefaults.standard.string(forKey: "apnsDeviceToken") ?? ""
    @Published private(set) var registrationError: String = UserDefaults.standard.string(forKey: "apnsRegistrationError") ?? ""
    @Published private(set) var busy = false

    private var tokenObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?

    init() {
        tokenObserver = NotificationCenter.default.addObserver(
            forName: .apnsDeviceTokenUpdated,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let token = note.object as? String else { return }
            Task { @MainActor in
                self?.deviceToken = token
                self?.registrationError = ""
            }
        }

        errorObserver = NotificationCenter.default.addObserver(
            forName: .apnsRegistrationFailed,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let message = note.object as? String else { return }
            Task { @MainActor in self?.registrationError = message }
        }

        Task { await refresh() }
    }

    deinit {
        if let tokenObserver { NotificationCenter.default.removeObserver(tokenObserver) }
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
    }

    var statusText: String {
        switch authorizationStatus {
        case .notDetermined: return "Not requested"
        case .denied: return "Disabled"
        case .authorized: return deviceToken.isEmpty ? "Allowed — registering with Apple" : "Ready"
        case .provisional: return "Provisional"
        case .ephemeral: return "Temporary"
        @unknown default: return "Unknown"
        }
    }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        deviceToken = UserDefaults.standard.string(forKey: "apnsDeviceToken") ?? deviceToken
        registrationError = UserDefaults.standard.string(forKey: "apnsRegistrationError") ?? ""

        if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func requestAuthorization() {
        Task { await requestAuthorizationAsync() }
    }

    func requestAuthorizationAsync() async {
        guard !busy else { return }
        let current = await UNUserNotificationCenter.current().notificationSettings()
        if current.authorizationStatus != .notDetermined {
            await refresh()
            return
        }
        busy = true
        registrationError = ""
        defer { busy = false }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refresh()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            registrationError = error.localizedDescription
        }
    }
}

@MainActor
final class PrivacyPermissions: ObservableObject {
    @Published private(set) var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var photoLibrary = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private let firstLaunchKey = "initialPermissionsRequested.v1"

    func refresh() {
        camera = AVCaptureDevice.authorizationStatus(for: .video)
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        photoLibrary = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func requestPhotoLibrary() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Runs once per installation. Apple permission sheets are requested sequentially so
    /// VoiceOver users and sighted users never get overlapping system dialogs.
    func requestInitialPermissionsIfNeeded(push: PushNotifications) async {
        guard !UserDefaults.standard.bool(forKey: firstLaunchKey) else {
            refresh()
            await push.refresh()
            return
        }
        UserDefaults.standard.set(true, forKey: firstLaunchKey)

        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in continuation.resume(returning: granted) }
            }
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in continuation.resume(returning: granted) }
            }
        }
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        await push.requestAuthorizationAsync()
        refresh()
    }

    func text(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Disabled"
        case .authorized: return "Allowed"
        @unknown default: return "Unknown"
        }
    }

    func text(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Disabled"
        case .authorized: return "Allowed"
        case .limited: return "Limited"
        @unknown default: return "Unknown"
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(.black)
            Circle()
                .stroke(.yellow.opacity(0.85), lineWidth: max(2, size * 0.035))
                .padding(size * 0.08)
            Image(systemName: "waveform")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.yellow)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
