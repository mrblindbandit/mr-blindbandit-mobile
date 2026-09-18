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
    @StateObject private var testProfile = TestProfileStore()
    @StateObject private var communications = LiveKitCommunicationManager()
    @Environment(\.scenePhase) private var phase
    @State private var showingLaunchCover = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !testProfile.isConfigured {
                    TestProfileOnboardingView()
                        .environmentObject(testProfile)
                        .environmentObject(communications)
                } else if lock.unlocked {
                    MainTabs()
                        .environmentObject(lock)
                        .environmentObject(push)
                        .environmentObject(privacy)
                        .environmentObject(preferences)
                        .environmentObject(testProfile)
                        .environmentObject(communications)
                        .accessibilityHidden(phase != .active)
                } else {
                    LockedView(lock: lock)
                }

                if phase != .active {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    VStack(spacing: 12) {
                        BrandMark(size: 56)
                        Text("Mr. Blind Bandit")
                            .font(.headline)
                        Label(communications.currentCall == nil ? "App locked" : "Call in progress",
                              systemImage: communications.currentCall == nil ? "lock.fill" : "phone.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(communications.currentCall == nil ? "Mr. Blind Bandit. App locked." : "Mr. Blind Bandit. Call in progress.")
                }

                if showingLaunchCover && phase == .active {
                    LaunchCover(reduceMotion: preferences.reduceAppMotion)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .environmentObject(testProfile)
            .environmentObject(communications)
            .task {
                communications.attach(profile: testProfile)
                if testProfile.isConfigured { communications.startInbox() }

                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(preferences.reduceAppMotion ? nil : .easeOut(duration: 0.3)) {
                    showingLaunchCover = false
                }
            }
            .onChange(of: phase) { _, value in
                if value == .background, communications.currentCall == nil { lock.lock() }
                if value == .active {
                    privacy.refresh()
                    Task { await push.refresh() }
                    if testProfile.isConfigured && communications.inboxStatus != "Ready for calls & messages" {
                        communications.restartInbox()
                    }
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
                Text("Calls · Messages · Music · Creator Tools")
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
                Text(lock.configured ? "Protected with your iPhone security" : "Secure your private communications and creator workspace")
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
    enum Tab: Hashable { case phone, messages, home, create, more }

    @EnvironmentObject private var communications: LiveKitCommunicationManager
    @State private var routedURL: RoutedURL?
    @State private var selection: Tab = .phone

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { CallingHomeView() }
                .tabItem { Label("Phone", systemImage: "phone.fill") }
                .tag(Tab.phone)

            NavigationStack { MessagesHomeView() }
                .tabItem { Label("Messages", systemImage: "message.fill") }
                .tag(Tab.messages)

            NavigationStack { ProfessionalHome() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            NavigationStack { CreatorHubView() }
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
                .tag(Tab.create)

            NavigationStack { MoreHubView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(Tab.more)
        }
        .tint(.yellow)
        .onChange(of: selection) { _, _ in AppHaptics.selection() }
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
        .fullScreenCover(item: $communications.currentCall) { call in
            CallScreen(callID: call.id)
                .environmentObject(communications)
        }
    }
}
