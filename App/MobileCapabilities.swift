import os
import SwiftUI
import UIKit
import UserNotifications
import AVFoundation

extension Notification.Name {
    static let apnsDeviceTokenUpdated = Notification.Name("apnsDeviceTokenUpdated")
    static let apnsRegistrationFailed = Notification.Name("apnsRegistrationFailed")
    static let pushDeepLinkReceived = Notification.Name("pushDeepLinkReceived")
    static let chronicleArticleDeepLink = Notification.Name("chronicleArticleDeepLink")
    static let blindbanditCallDeepLinkReceived = Notification.Name("blindbanditCallDeepLinkReceived")
    static let blindbanditMessageDeepLinkReceived = Notification.Name("blindbanditMessageDeepLinkReceived")
}

private let pushLog = Logger(subsystem: "net.mrblindbandit.app", category: "push")

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // PushKit must be registered at launch so a VoIP push that woke the app is delivered.
        CallKitManager.shared.setUp()
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
        let userInfo = notification.request.content.userInfo
        let category = (userInfo["category"] as? String) ?? (userInfo["type"] as? String) ?? ""
        let link = (userInfo["deep_link"] as? String) ?? ""
        let isCall = category.contains("call") || link.hasPrefix("/mobile/calls")
        let isGroup = category.contains("group") || (userInfo["group_id"] as? String) != nil || link.contains("/groups")
        let isMention = category.contains("mention") || (userInfo["mention"] as? Bool) == true
        let defaults = UserDefaults.standard
        var allowed: Bool
        if isCall {
            allowed = defaults.object(forKey: SettingsKey.notifyCalls) as? Bool ?? true
        } else if isMention {
            allowed = defaults.object(forKey: SettingsKey.notifyMentions) as? Bool ?? true
        } else if isGroup {
            allowed = defaults.object(forKey: SettingsKey.notifyGroups) as? Bool ?? true
        } else {
            allowed = defaults.object(forKey: SettingsKey.notifyMessages) as? Bool ?? true
        }
        if allowed, QuietHoursSchedule.isQuietNow() { allowed = false }
        var opts: UNNotificationPresentationOptions = allowed ? [.banner, .badge, .list] : []
        if allowed {
            let soundOn = defaults.object(forKey: SettingsKey.notificationSound) as? Bool ?? true
            if soundOn { opts.insert(.sound) }
        }
        completionHandler(opts)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let route = PushRoute.parse(userInfo)
        pushLog.notice("Notification tapped. keys=\(PushRoute.keySummary(userInfo), privacy: .public) routed=\(route != nil, privacy: .public)")
        if let route {
            // Works for warm and cold launch: PendingRouter holds it until signed in and unlocked.
            Task { @MainActor in PendingRouter.shared.pending = route }
        }
        completionHandler()
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
        case .notDetermined: return "Not asked yet"
        case .denied: return "Off in iOS Settings"
        case .authorized: return "On"
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

/// Camera and microphone status. Permissions are only requested in context, when the person
/// starts a call or a recording, never at launch (App Store Review Guideline 5.1.1).
@MainActor
final class PrivacyPermissions: ObservableObject {
    @Published private(set) var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)

    func refresh() {
        camera = AVCaptureDevice.authorizationStatus(for: .video)
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestCamera() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        refresh()
        return granted
    }

    func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
        return granted
    }

    func text(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not asked yet"
        case .restricted: return "Restricted"
        case .denied: return "Off"
        case .authorized: return "On"
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


/// Local quiet-hours window (minutes from midnight). Spans midnight when end < start.
enum QuietHoursSchedule {
    static func isQuietNow(date: Date = Date()) -> Bool {
        let d = UserDefaults.standard
        guard d.object(forKey: SettingsKey.quietHoursEnabled) as? Bool ?? false else { return false }
        let start = d.object(forKey: SettingsKey.quietHoursStart) as? Int ?? 22 * 60
        let end = d.object(forKey: SettingsKey.quietHoursEnd) as? Int ?? 7 * 60
        let cal = Calendar.current
        let mins = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        if start == end { return true }
        if start < end { return mins >= start && mins < end }
        return mins >= start || mins < end
    }
}
