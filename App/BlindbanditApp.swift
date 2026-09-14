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

    func lock() { unlocked = false }

    func unlock() {
        guard !busy else { return }
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Set up Face ID, Touch ID, or a device passcode in iPhone Settings, then try again."
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
                } else {
                    self.message = "Unlock was cancelled or unsuccessful. You can try again."
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
    @Environment(\.scenePhase) private var phase
    @State private var showingLaunchCover = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if lock.unlocked {
                    MainTabs()
                        .environmentObject(lock)
                        .environmentObject(push)
                        .environmentObject(privacy)
                        .environmentObject(preferences)
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
                try? await Task.sleep(for: .milliseconds(900))
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
                Text("Music · Creator Tools · Blindbandit Records")
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
    @State private var routedURL: RoutedURL?

    var body: some View {
        TabView {
            NavigationStack { ProfessionalHome() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { CreatorHubView() }
                .tabItem { Label("Create", systemImage: "wand.and.stars") }

            NavigationStack { NativeAudioConverterView() }
                .tabItem { Label("Audio", systemImage: "waveform") }

            NavigationStack { NativeArtTrackGeneratorView() }
                .tabItem { Label("Art Track", systemImage: "play.rectangle.fill") }

            NavigationStack { Settings() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.yellow)
        .onReceive(NotificationCenter.default.publisher(for: .pushDeepLinkReceived)) { note in
            guard let url = note.object as? URL else { return }
            if Browser.isFirstPartyURL(url) { routedURL = RoutedURL(url: url) }
            else { UIApplication.shared.open(url) }
        }
        .sheet(item: $routedURL) { routed in
            NavigationStack {
                Website(url: routed.url, title: "Notification")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { routedURL = nil }
                        }
                    }
            }
        }
    }
}
