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
        if StoreScreenshotMode.isActive { return false }
        #if DEBUG
        // UI tests on CI simulators have no passcode or biometrics to unlock with.
        if ProcessInfo.processInfo.arguments.contains("-UITestSkipAppLock") { return false }
        #endif
        return UserDefaults.standard.object(forKey: SettingsKey.requireDeviceUnlock) as? Bool ?? true
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
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock \(AppConfig.appDisplayName)") { success, _ in
            Task { @MainActor in
                self.busy = false
                self.context = nil
                self.unlocked = success
                if success { AppPIN.decoyActive = false }
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
    enum Tab: Hashable { case home, messages, groups, calls, more }
    @Published var selection: Tab = TabRouter.initialTab
    /// Set when a notification asks for a DM thread; MessagesTabView opens it and clears it.
    @Published var pendingThread: ThreadTarget?
    /// Set when a notification asks for a group chat; GroupsTabView opens it and clears it.
    @Published var pendingGroupID: String?

    struct ThreadTarget: Equatable { let id: String?; let handle: String? }

    private static var initialTab: Tab {
        guard StoreScreenshotMode.isActive else { return .home }
        switch StoreScreenshotMode.screen {
        case "create": return .more
        case "connect", "messages": return .messages
        case "calls": return .calls
        case "listen": return .more
        case "chronicle": return .more
        case "groups": return .groups
        case "more", "settings", "accessibility": return .more
        default: return .home
        }
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
    @StateObject private var communications = ProductionCommunicationsService()
    @StateObject private var router = TabRouter()
    @Environment(\.scenePhase) private var phase
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(SettingsKey.highContrast) private var highContrast = false
    @AppStorage(SettingsKey.keepScreenAwake) private var keepScreenAwake = false
    @State private var showingLaunchCover = true
    @State private var backgroundedAt: Date?
    @AppStorage("permissionsOnboardingDone") private var permissionsOnboardingDone = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if ProcessInfo.processInfo.arguments.contains("-UITestMessageStatus") {
                    MessageStatusUITestView()
                } else {
                switch auth.state {
                case .unknown:
                    ZStack {
                        Color.black.ignoresSafeArea()
                        SpinningBrandLogo(size: 112, reduceMotion: preferences.reduceAppMotion)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Starting \(AppConfig.appDisplayName)")
                case .signedOut:
                    AuthGatewayView(auth: auth)
                        .environmentObject(preferences)
                case .signedIn:
                    if !permissionsOnboardingDone && !StoreScreenshotMode.isActive {
                        PermissionsOnboarding()
                    } else if lock.unlocked || !lock.isRequired {
                        MainTabs()
                            .accessibilityHidden(phase != .active && lock.isRequired)
                    } else {
                        LockedView(lock: lock)
                    }
                }
                }

                if phase != .active, lock.isRequired || AppSecurity.blurSwitcher, case .signedIn = auth.state {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    VStack(spacing: 12) {
                        BlindbanditLogoImage(size: 56)
                        Text(AppConfig.appDisplayName)
                            .font(.headline)
                        Label("Content hidden", systemImage: "eye.slash")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(AppConfig.appDisplayName). Content hidden while the app is in the background.")
                }

                if showingLaunchCover && phase == .active {
                    LaunchCover(reduceMotion: preferences.reduceAppMotion)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .onContinueUserActivity("INStartCallIntent") { activity in
                // Recents / Siri at cold launch: queued until the signed-in, unlocked screen attaches.
                CallKitManager.shared.handle(userActivity: activity)
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
            .task { await SharePlayCalls.listen(communications) }
            .task { communications.loadCachedConversations(); AIChatStore.shared.prewarm() }
            .task {
                auth.configure()
                UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(preferences.reduceAppMotion ? nil : .easeOut(duration: 0.3)) {
                    showingLaunchCover = false
                }
            }
            .onChange(of: phase) { _, value in
                // App lock is cold-launch only (1.8.0): returning from background or the
                // app switcher never re-prompts. `lock.unlocked` stays true for the process lifetime.
                if value == .background { backgroundedAt = Date() }
                if value == .active, let since = backgroundedAt {
                    backgroundedAt = nil
                    let t = AppSecurity.relockSeconds
                    if t >= 0, Date().timeIntervalSince(since) >= Double(t) { lock.lock() }
                }
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
                Text(AppConfig.appDisplayName)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Your account is protected")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Use Face ID, Touch ID, or your passcode to open the app. You can turn this off in Settings.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Unlock") { lock.unlock() }
                    .accessibilityLabel("Unlock \(AppConfig.appDisplayName)")
                    .accessibilityHint("Uses Face ID, Touch ID, or your passcode. Only asked when the app first starts.")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(lock.busy)
                if AppPIN.isSet {
                    PINEntryView { r in if r != .wrong { lock.unlocked = true } }
                }
                if lock.busy { ProgressView("Waiting for iPhone authentication") }
                if !lock.message.isEmpty {
                    Text(lock.message).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(30)
            .onChange(of: lock.message) { _, m in
                if !m.isEmpty { UIAccessibility.post(notification: .announcement, argument: m) }
            }
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
    @EnvironmentObject private var lock: DeviceLock
    @Environment(\.scenePhase) private var routePhase
    @State private var routedURL: RoutedURL?
    @State private var deepLinkedArticle: DeepLinkedArticle?

    var body: some View {
        TabView(selection: $router.selection) {
            NavigationStack {
                if let page = StoreScreenshotMode.webPage {
                    Website(path: page.path, title: page.title)
                } else {
                    ProfessionalHome()
                }
            }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(TabRouter.Tab.home)

            MessagesTabView()
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(communications.unreadCount)
                .tag(TabRouter.Tab.messages)

            CallsTabView()
                .tabItem { Label("Calls", systemImage: "phone.fill") }
                .tag(TabRouter.Tab.calls)

            GroupsTabView()
                .tabItem { Label("Groups", systemImage: "person.3.fill") }
                .tag(TabRouter.Tab.groups)

            NavigationStack {
                if StoreScreenshotMode.isActive && ["settings", "accessibility"].contains(StoreScreenshotMode.screen) {
                    Settings()
                } else {
                    MoreHubView()
                }
            }
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(TabRouter.Tab.more)
        }
        .onChange(of: router.selection) { _, _ in AppHaptics.selection() }
        .task {
            guard !StoreScreenshotMode.isActive else { return }
            await communications.bootstrap()
            await registerPushTokenIfPossible(push.deviceToken)
        }
        .onReceive(NotificationCenter.default.publisher(for: .apnsDeviceTokenUpdated)) { note in
            guard let token = note.object as? String else { return }
            Task { await registerPushTokenIfPossible(token) }
        }
        // Tapped notifications. PendingRouter keeps the route through cold launch, sign-in and
        // Face ID; this view only exists once the app is unlocked, so the thread opens right after.
        .onReceive(PendingRouter.shared.$pending.compactMap { $0 }) { _ in routePendingIfReady() }
        .onAppear { routePendingIfReady() }
        .onChange(of: routePhase) { _, _ in routePendingIfReady() }
        .onChange(of: lock.unlocked) { _, _ in routePendingIfReady() }
        .onAppear { CallKitManager.shared.attach(communications) }
        .onContinueUserActivity("INStartCallIntent") { activity in
            CallKitManager.shared.handle(userActivity: activity)
        }
        .fullScreenCover(isPresented: Binding(get: { communications.isInCall || communications.incomingCall != nil }, set: { _ in })) {
            CallContainerScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard !StoreScreenshotMode.isActive else { return }
            Task {
                await communications.refreshConversations()
                await communications.flushPendingMessages()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chronicleArticleDeepLink)) { note in
            guard let url = note.object as? URL else { return }
            deepLinkedArticle = DeepLinkedArticle(url: url)
        }
        .onOpenURL { url in
            if let route = PushRoute.parse(url: url), url.scheme == "mrblindbandit" || url.path.hasPrefix("/mobile/") || route.isArticle {
                open(route)
            }
        }
        .sheet(item: $deepLinkedArticle) { item in
            NavigationStack {
                ChronicleReader(story: ChronicleDeepLink.story(for: item.url))
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { deepLinkedArticle = nil } } }
            }
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

    /// Navigates to a tapped notification only once the app is active and unlocked, so the Face ID
    /// lock (which rebuilds the tabs) can't wipe it. Until then the route stays in PendingRouter.
    private func routePendingIfReady() {
        Task { @MainActor in
            // Let the tab view finish building (cold launch, just unlocked) before navigating.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard routePhase == .active, lock.unlocked || !lock.isRequired,
                  PendingRouter.shared.pending != nil,
                  let route = PendingRouter.shared.consume() else { return }
            open(route)
        }
    }

    private func open(_ route: PushRoute) {
        AppHaptics.doublePulse()
        switch route {
        case .conversation(let id, let handle):
            router.selection = .messages
            router.pendingThread = TabRouter.ThreadTarget(id: id, handle: handle)
        case .group(let id):
            router.selection = .groups
            router.pendingGroupID = id
        case .call(let id):
            router.selection = .calls
            Task { await communications.presentIncomingCall(id: id) }
        case .article(let url):
            deepLinkedArticle = DeepLinkedArticle(url: url)
        case .web(let url):
            if Browser.isFirstPartyURL(url) { routedURL = RoutedURL(url: url) } else { UIApplication.shared.open(url) }
        }
    }

    /// Sends the APNs token to the Blindbandit API so calls and messages can reach this iPhone.
    private func registerPushTokenIfPossible(_ token: String) async {
        let voip = UserDefaults.standard.string(forKey: CallKitManager.voipTokenKey) ?? ""
        guard !token.isEmpty || !voip.isEmpty else { return }
        let key = "registeredPushToken"
        let fingerprint = token + "|" + voip
        guard UserDefaults.standard.string(forKey: key) != fingerprint else { return }
        do {
            try await BlindbanditAPI.registerPushToken(token)
            UserDefaults.standard.set(fingerprint, forKey: key)
        } catch {
            // Registration is retried on the next launch or token change.
        }
    }
}
