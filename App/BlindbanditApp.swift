import SwiftUI
import LocalAuthentication
import UIKit

@MainActor
final class DeviceLock: ObservableObject {
    @Published var unlocked = false
    @Published var busy = false
    @Published var message = ""
    @Published var configured = UserDefaults.standard.bool(forKey: "lockConfigured")
    private var context: LAContext?

    func lock() {
        guard isRequired else { return }
        unlocked = false
    }

    /// The lock is a user setting (on by default). When the device has no passcode at all there is
    /// nothing to verify against, so the app opens rather than trapping the person on this screen.
    var isRequired: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.requireDeviceUnlock) as? Bool ?? true
    }

    func unlock() {
        guard !busy else { return }
        guard isRequired else {
            unlocked = true
            return
        }
        AppHaptics.medium()
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let code = error.map({ LAError.Code(rawValue: $0.code) }), code == .passcodeNotSet {
                unlocked = true
                return
            }
            message = "Face ID, Touch ID, or your passcode is not available right now. Check iPhone Settings, then try again."
            AppHaptics.error()
            return
        }
        busy = true
        context = ctx
        message = ""
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Mr. Blindbandit") { success, _ in
            Task { @MainActor in
                self.busy = false
                self.context = nil
                self.unlocked = success
                if success {
                    self.configured = true
                    UserDefaults.standard.set(true, forKey: "lockConfigured")
                    AppHaptics.success()
                } else {
                    self.message = "Unlock was cancelled or unsuccessful. You can try again."
                    AppHaptics.warning()
                }
            }
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var pageZoom: Double { didSet { UserDefaults.standard.set(pageZoom, forKey: "pageZoom") } }
    @Published var reduceAppMotion: Bool { didSet { UserDefaults.standard.set(reduceAppMotion, forKey: "reduceAppMotion") } }
    @Published var announcePageLoads: Bool { didSet { UserDefaults.standard.set(announcePageLoads, forKey: "announcePageLoads") } }
    @Published var pullToRefresh: Bool { didSet { UserDefaults.standard.set(pullToRefresh, forKey: "pullToRefresh") } }

    init() {
        let savedZoom = UserDefaults.standard.double(forKey: "pageZoom")
        pageZoom = savedZoom == 0 ? 1.0 : min(max(savedZoom, 0.75), 2.0)
        reduceAppMotion = UserDefaults.standard.object(forKey: "reduceAppMotion") as? Bool ?? false
        announcePageLoads = UserDefaults.standard.object(forKey: "announcePageLoads") as? Bool ?? true
        pullToRefresh = UserDefaults.standard.object(forKey: "pullToRefresh") as? Bool ?? true
    }
}

@MainActor
final class TabRouter: ObservableObject {
    enum Tab: Hashable { case home, create, connect, listen, more }
    @Published var selection: Tab = .home
}

@main
struct BlindbanditApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var lock = DeviceLock()
    @StateObject private var push = PushNotifications()
    @StateObject private var privacy = PrivacyPermissions()
    @StateObject private var preferences = AppPreferences()
    @StateObject private var auth = ClerkAuthService()
    @StateObject private var communications = ProductionCommunicationsService()
    @StateObject private var router = TabRouter()
    @Environment(\.scenePhase) private var phase
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(SettingsKey.highContrast) private var highContrast = false
    @AppStorage(SettingsKey.keepScreenAwake) private var keepScreenAwake = false
    @State private var showingLaunchCover = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch auth.state {
                case .unknown:
                    ZStack {
                        Color.black.ignoresSafeArea()
                        SpinningBrandLogo(size: 112, reduceMotion: preferences.reduceAppMotion)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Starting Mr. Blindbandit")
                case .signedOut:
                    AuthGatewayView(auth: auth)
                        .environmentObject(preferences)
                case .signedIn:
                    if lock.unlocked || !lock.isRequired {
                        MainTabs()
                            .accessibilityHidden(phase != .active && lock.isRequired)
                    } else {
                        LockedView(lock: lock)
                    }
                }

                if phase != .active, lock.isRequired, case .signedIn = auth.state {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    VStack(spacing: 12) {
                        BlindbanditLogoImage(size: 56)
                        Text("Mr. Blindbandit")
                            .font(.headline)
                        Label("App locked", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Mr. Blindbandit. App locked.")
                }

                if showingLaunchCover && phase == .active {
                    LaunchCover(reduceMotion: preferences.reduceAppMotion)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .environmentObject(lock)
            .environmentObject(push)
            .environmentObject(privacy)
            .environmentObject(preferences)
            .environmentObject(auth)
            .environmentObject(communications)
            .environmentObject(router)
            .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
            .tint(highContrast ? Color.primary : Brand.gold)
            .task {
                auth.configure()
                UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(preferences.reduceAppMotion ? nil : .easeOut(duration: 0.3)) {
                    showingLaunchCover = false
                }
            }
            .onChange(of: phase) { _, value in
                if value == .background { lock.lock() }
                if value == .active {
                    privacy.refresh()
                    Task { await push.refresh() }
                }
            }
            .onChange(of: auth.state) { _, state in
                if case .signedOut = state { communications.reset() }
            }
        }
    }
}

struct LaunchCover: View {
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                PulsingBrandMark(size: 124, reduceMotion: reduceMotion)
                Text("MR. BLINDBANDIT")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                WaveformLoader(reduceMotion: reduceMotion)
                    .foregroundStyle(.yellow)
                Text("Music · Creator Tools · Calls · Blindbandit Records")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(32)
        }
    }
}

struct LockedView: View {
    @ObservedObject var lock: DeviceLock

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                BrandMark(size: 96)
                Text("Mr. Blindbandit")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Your account is protected")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Use Face ID, Touch ID, or your passcode to open the app. You can turn this off in Settings.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Unlock") { lock.unlock() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(lock.busy)
                if lock.busy { ProgressView("Waiting for iPhone authentication") }
                if !lock.message.isEmpty { Text(lock.message).foregroundStyle(.secondary) }
            }
            .padding(30)
        }
    }
}

struct RoutedURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct MainTabs: View {
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var routedURL: RoutedURL?

    var body: some View {
        TabView(selection: $router.selection) {
            NavigationStack { ProfessionalHome() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(TabRouter.Tab.home)

            NavigationStack { CreatorHubView() }
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
                .tag(TabRouter.Tab.create)

            NavigationStack { ConnectHubView() }
                .tabItem { Label("Connect", systemImage: "phone.and.waveform.fill") }
                .tag(TabRouter.Tab.connect)

            NavigationStack { ListenHubView() }
                .tabItem { Label("Listen", systemImage: "headphones") }
                .tag(TabRouter.Tab.listen)

            NavigationStack { MoreHubView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(TabRouter.Tab.more)
        }
        .onChange(of: router.selection) { _, _ in AppHaptics.selection() }
        .task {
            await communications.bootstrap()
            await registerPushTokenIfPossible(push.deviceToken)
        }
        .onReceive(NotificationCenter.default.publisher(for: .apnsDeviceTokenUpdated)) { note in
            guard let token = note.object as? String else { return }
            Task { await registerPushTokenIfPossible(token) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditCallDeepLinkReceived)) { _ in
            AppHaptics.doublePulse()
            router.selection = .connect
        }
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditMessageDeepLinkReceived)) { _ in
            AppHaptics.doublePulse()
            router.selection = .connect
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushDeepLinkReceived)) { note in
            guard let url = note.object as? URL else { return }
            AppHaptics.doublePulse()
            if Browser.isFirstPartyURL(url) { routedURL = RoutedURL(url: url) }
            else { UIApplication.shared.open(url) }
        }
        .sheet(item: $routedURL) { routed in
            NavigationStack {
                Website(url: routed.url, title: "Notification")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                AppHaptics.light()
                                routedURL = nil
                            }
                        }
                    }
            }
        }
    }

    /// Sends the APNs token to the Blindbandit API so calls and messages can reach this iPhone.
    private func registerPushTokenIfPossible(_ token: String) async {
        guard !token.isEmpty else { return }
        let key = "registeredPushToken"
        guard UserDefaults.standard.string(forKey: key) != token else { return }
        do {
            try await BlindbanditAPI.registerPushToken(token)
            UserDefaults.standard.set(token, forKey: key)
        } catch {
            // Registration is retried on the next launch or token change.
        }
    }
}
