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
        AppHaptics.soft()
        unlocked = false
    }

    func unlock() {
        guard !busy else { return }
        AppHaptics.medium()
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Set up Face ID, Touch ID, or a device passcode in iPhone Settings, then try again."
            AppHaptics.error()
            return
        }
        busy = true
        context = ctx
        message = ""
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Mr. Blind Bandit") { success, _ in
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

@main
struct BlindbanditApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var lock = DeviceLock()
    @StateObject private var push = PushNotifications()
    @StateObject private var privacy = PrivacyPermissions()
    @StateObject private var preferences = AppPreferences()
    @StateObject private var auth = ClerkAuthService()
    @Environment(\.scenePhase) private var phase
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
                    .accessibilityLabel("Starting Mr. Blind Bandit")
                case .signedOut:
                    AuthGatewayView(auth: auth)
                        .environmentObject(preferences)
                case .signedIn:
                    if lock.unlocked {
                        MainTabs()
                            .environmentObject(lock)
                            .environmentObject(push)
                            .environmentObject(privacy)
                            .environmentObject(preferences)
                            .environmentObject(auth)
                            .accessibilityHidden(phase != .active)
                    } else {
                        LockedView(lock: lock)
                    }
                }

                if phase != .active, case .signedIn = auth.state {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    VStack(spacing: 12) {
                        BlindbanditLogoImage(size: 56)
                        Text("Mr. Blind Bandit")
                            .font(.headline)
                        Label("App locked", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Mr. Blind Bandit. App locked.")
                }

                if showingLaunchCover && phase == .active {
                    LaunchCover(reduceMotion: preferences.reduceAppMotion)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .task {
                auth.configure()
                try? await Task.sleep(for: .milliseconds(450))
                await privacy.requestInitialPermissionsIfNeeded(push: push)
                try? await Task.sleep(for: .milliseconds(450))
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
                Text("MR. BLIND BANDIT")
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
                Text("Mr. Blind Bandit")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(lock.configured ? "Protected with your iPhone security" : "Secure your private creator workspace")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Use Face ID, Touch ID, or your device passcode to open the app.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(lock.configured ? "Unlock Mr. Blind Bandit" : "Set Up Secure Unlock") { lock.unlock() }
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
    enum Tab: Hashable { case home, create, connect, listen, more }

    @State private var routedURL: RoutedURL?
    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { ProfessionalHome() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
                .accessibilityLabel("Home tab")

            NavigationStack { CreatorHubView() }
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
                .tag(Tab.create)
                .accessibilityLabel("Create tab")

            NavigationStack { ConnectHubView() }
                .tabItem { Label("Connect", systemImage: "phone.and.waveform.fill") }
                .tag(Tab.connect)
                .accessibilityLabel("Connect tab for calls and chat")

            NavigationStack { ListenHubView() }
                .tabItem { Label("Listen", systemImage: "headphones") }
                .tag(Tab.listen)
                .accessibilityLabel("Listen tab for music services")

            NavigationStack { MoreHubView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(Tab.more)
                .accessibilityLabel("More tab for profile, web, and settings")
        }
        .tint(.yellow)
        .onChange(of: selection) { _, _ in AppHaptics.selection() }
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditCallDeepLinkReceived)) { _ in
            AppHaptics.doublePulse()
            selection = .connect
        }
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditMessageDeepLinkReceived)) { _ in
            AppHaptics.doublePulse()
            selection = .connect
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
}
