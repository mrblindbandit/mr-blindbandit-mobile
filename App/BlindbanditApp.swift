import SwiftUI
import WebKit
import LocalAuthentication
import UIKit

@MainActor final class DeviceLock: ObservableObject {
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
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your private Blindbandit app") { success, _ in
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

@MainActor final class AppPreferences: ObservableObject {
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

@main struct BlindbanditApp: App {
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
                    Tabs()
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
                    Label("Blindbandit — private", systemImage: "lock.fill").font(.headline)
                }

                if showingLaunchCover && phase == .active {
                    LaunchCover(reduceMotion: preferences.reduceAppMotion)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(850))
                withAnimation(preferences.reduceAppMotion ? nil : .easeOut(duration: 0.25)) {
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
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                PulsingBrandMark(size: 112, reduceMotion: reduceMotion)
                Text("MR. BLINDBANDIT").font(.title.bold())
                Text("Music · Creator Tools · Blindbandit Records")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
    }
}

struct LockedView: View {
    @ObservedObject var lock: DeviceLock
    var body: some View {
        VStack(spacing: 24) {
            BrandMark(size: 88)
            Text(lock.configured ? "Blindbandit is locked" : "Protect your private app")
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            Text("Use Face ID, Touch ID, or your device passcode. Sign in to your website account once to connect your label dashboard.")
                .multilineTextAlignment(.center)
            Button(lock.configured ? "Unlock app" : "Set up secure unlock") { lock.unlock() }
                .buttonStyle(.borderedProminent)
                .disabled(lock.busy)
            if lock.busy { ProgressView("Waiting for device authentication") }
            if !lock.message.isEmpty { Text(lock.message).foregroundStyle(.secondary) }
        }
        .padding(28)
    }
}

struct RoutedURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct Tabs: View {
    @State private var routedURL: RoutedURL?
    var body: some View {
        TabView {
            NavigationStack { Home() }.tabItem { Label("Home", systemImage: "house") }
            NavigationStack { Website(path: "/account", title: "Profile") }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            NavigationStack { Website(path: "/portal/", title: "Label dashboard") }
                .tabItem { Label("Label", systemImage: "building.2") }
            NavigationStack { Settings() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushDeepLinkReceived)) { note in
            guard let url = note.object as? URL else { return }
            if Browser.isFirstPartyURL(url) { routedURL = RoutedURL(url: url) }
            else { UIApplication.shared.open(url) }
        }
        .sheet(item: $routedURL) { routed in
            NavigationStack {
                Website(url: routed.url, title: "Notification")
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { routedURL = nil } } }
            }
        }
    }
}

struct Home: View {
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var privacy: PrivacyPermissions
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    BrandMark(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mr. Blindbandit").font(.title2).bold().accessibilityAddTraits(.isHeader)
                        Text("Blindbandit Records · Native companion").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Your website") {
                NavigationLink("Public home") { Website(path: "/", title: "Website") }
                NavigationLink("Media tools") { Website(path: "/media-tools/", title: "Media tools") }
                NavigationLink("Community") { Website(path: "/community/", title: "Community") }
                NavigationLink("Sign in") { Website(path: "/sign-in?redirect_url=%2Fportal%2F", title: "Sign in") }
            }
            Section("Create and upload") {
                NavigationLink("Open Media Suite") { Website(path: "/media-tools/", title: "Media Suite") }
                Label("Native file and photo upload picker", systemImage: "square.and.arrow.up")
                Label("Camera: \(privacy.text(for: privacy.camera))", systemImage: "camera")
                Label("Microphone: \(privacy.text(for: privacy.microphone))", systemImage: "mic")
            }
            Section("Label shortcuts") {
                NavigationLink("Label dashboard") { Website(path: "/portal/", title: "Label dashboard") }
                NavigationLink("Payment overview") { Website(path: "/portal/payments/", title: "Payments") }
            }
            Section("App status") {
                Label("Push notifications: \(push.statusText)", systemImage: "bell.badge")
                NavigationLink("Permissions and advanced settings") { Settings() }
            }
            Section("Share") { ShareLink("Share public website", item: URL(string: "https://mrblindbandit.net/")!) }
        }
        .navigationTitle("Home")
    }
}

struct Settings: View {
    @EnvironmentObject private var lock: DeviceLock
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var preferences: AppPreferences
    @State private var confirm = false
    @State private var clearing = false

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section("Notifications") {
                LabeledContent("Push notifications", value: push.statusText)
                if push.authorizationStatus == .notDetermined {
                    Button("Enable push notifications") { push.requestAuthorization() }.disabled(push.busy)
                } else if push.authorizationStatus == .denied {
                    Button("Open notification settings") { openSystemSettings() }
                } else {
                    Button("Refresh notification registration") { Task { await push.refresh() } }
                }
                if push.busy { ProgressView("Requesting notification permission") }
                if !push.registrationError.isEmpty {
                    Text("Apple push registration: \(push.registrationError)").foregroundStyle(.secondary)
                }
                Text("Remote delivery requires an Apple-signed build and the server-side APNs sender/device registration endpoint.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Camera, microphone, and files") {
                LabeledContent("Camera", value: privacy.text(for: privacy.camera))
                if privacy.camera == .notDetermined { Button("Allow camera access") { privacy.requestCamera() } }
                LabeledContent("Microphone", value: privacy.text(for: privacy.microphone))
                if privacy.microphone == .notDetermined { Button("Allow microphone access") { privacy.requestMicrophone() } }
                if privacy.camera == .denied || privacy.microphone == .denied {
                    Button("Open app permission settings") { openSystemSettings() }
                }
                Text("First-party pages can request camera and microphone capture. Upload controls use native iOS file and photo pickers.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Browser") {
                VStack(alignment: .leading) {
                    Text("Page zoom: \(Int(preferences.pageZoom * 100)) percent")
                    Slider(value: $preferences.pageZoom, in: 0.75...2.0, step: 0.05)
                        .accessibilityLabel("Website page zoom")
                        .accessibilityValue("\(Int(preferences.pageZoom * 100)) percent")
                }
                Toggle("Pull to refresh", isOn: $preferences.pullToRefresh)
                Button("Clear website cache") { clearCache() }.disabled(clearing)
            }

            Section("Accessibility") {
                Toggle("Announce completed page loads", isOn: $preferences.announcePageLoads)
                Toggle("Reduce app motion", isOn: $preferences.reduceAppMotion)
                Text("Native controls support VoiceOver, Dynamic Type, button shapes, increased contrast, Reduce Motion, and system appearance. Web content keeps the website's semantic accessibility tree.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Open iOS accessibility settings") {
                    UIApplication.shared.open(URL(string: "App-Prefs:ACCESSIBILITY") ?? URL(string: UIApplication.openSettingsURLString)!)
                }
            }

            Section("Security and privacy") {
                Label("Device authentication required", systemImage: "lock.shield")
                Button("Lock app now") { lock.lock() }
                Button("Clear website sessions on this device", role: .destructive) { confirm = true }.disabled(clearing)
                Button("Open app settings") { openSystemSettings() }
            }

            Section("Account") {
                NavigationLink("Account and security settings") { Website(path: "/account", title: "Account") }
                Text("Website sessions stay in the app's WebKit data store until they expire, are revoked, or you clear them. No reusable backend secret is bundled in the client.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Blindbandit", value: versionText)
                LabeledContent("Platform", value: "iOS 17+")
                LabeledContent("Web engine", value: "Apple WebKit")
                Text("Native navigation, branded loading state, APNs framework, media permissions, uploads, secure device lock, and accessibility-first controls.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear this device's website sessions?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Clear sessions", role: .destructive) { clearSessions() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This clears cookies and website storage in this app. Other devices are unaffected.") }
    }

    private func clearCache() {
        clearing = true
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) {
            Task { @MainActor in clearing = false }
        }
    }

    private func clearSessions() {
        clearing = true
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in clearing = false; lock.lock() }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

@MainActor final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let firstPartyHosts: Set<String> = [
        "mrblindbandit.net", "www.mrblindbandit.net", "portal.mrblindbandit.net",
        "api.mrblindbandit.net", "clerk.mrblindbandit.net", "accounts.mrblindbandit.net"
    ]

    static func isFirstPartyURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return firstPartyHosts.contains(host)
    }

    let web: WKWebView
    let initialURL: URL
    @Published var loading = false
    @Published var progress: Double = 0
    @Published var error: String?
    @Published var back = false
    @Published var forward = false
    private var progressObservation: NSKeyValueObservation?

    convenience init(path: String) { self.init(url: URL(string: "https://mrblindbandit.net" + path)!) }

    init(url: URL) {
        initialURL = url
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.mediaTypesRequiringUserActionForPlayback = []
        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.allowsLinkPreview = false
        web.scrollView.keyboardDismissMode = .interactive
        web.pageZoom = min(max(UserDefaults.standard.double(forKey: "pageZoom") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "pageZoom"), 0.75), 2.0)
        configurePullToRefresh()
        progressObservation = web.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor in self?.progress = webView.estimatedProgress }
        }
        web.load(URLRequest(url: initialURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    deinit { progressObservation?.invalidate() }

    func applyPreferences(_ preferences: AppPreferences) {
        web.pageZoom = preferences.pageZoom
        if preferences.pullToRefresh { configurePullToRefresh() } else { web.scrollView.refreshControl = nil }
    }

    private func configurePullToRefresh() {
        guard UserDefaults.standard.object(forKey: "pullToRefresh") as? Bool ?? true else { return }
        if web.scrollView.refreshControl == nil {
            let control = UIRefreshControl()
            control.accessibilityLabel = "Refresh website"
            control.addTarget(self, action: #selector(refreshFromPull), for: .valueChanged)
            web.scrollView.refreshControl = control
        }
    }

    @objc private func refreshFromPull() { reload() }

    func reload() {
        error = nil
        if web.url == nil { web.load(URLRequest(url: initialURL)) } else { web.reload() }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; progress = 0; error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; progress = 1
        back = webView.canGoBack; forward = webView.canGoForward
        webView.scrollView.refreshControl?.endRefreshing()
        if UserDefaults.standard.object(forKey: "announcePageLoads") as? Bool ?? true {
            UIAccessibility.post(notification: .announcement, argument: "Page loaded")
        }
    }

    func failed(_ failure: Error) {
        guard (failure as NSError).code != NSURLErrorCancelled else { return }
        loading = false; web.scrollView.refreshControl?.endRefreshing()
        error = "This page could not load. Check your connection and try again."
        UIAccessibility.post(notification: .announcement, argument: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        error = "The page stopped responding. Reload to continue. Unsaved changes may be lost."
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false || Self.isFirstPartyURL(url) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if ["https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
        else { loading = false; error = "Open this page in Safari to use this link." }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        if Self.isFirstPartyURL(url) { webView.load(action.request) }
        else if url.scheme?.lowercased() == "https" { UIApplication.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(Self.firstPartyHosts.contains(origin.host.lowercased()) ? .grant : .deny)
    }

    private func show(_ alert: UIAlertController, fallback: () -> Void) {
        guard var presenter = web.window?.rootViewController, UIApplication.shared.applicationState == .active else { fallback(); return }
        while let shown = presenter.presentedViewController { presenter = shown }
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "Website message", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        show(alert, fallback: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "Confirm website action", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Confirm", style: .default) { _ in completionHandler(true) })
        show(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "Website input", message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText; $0.accessibilityLabel = prompt }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        show(alert) { completionHandler(nil) }
    }
}

struct WebSurface: UIViewRepresentable {
    let browser: Browser
    func makeUIView(context: Context) -> WKWebView { browser.web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct Website: View {
    @StateObject private var browser: Browser
    @EnvironmentObject private var preferences: AppPreferences
    let title: String

    init(path: String, title: String) {
        self.title = title
        _browser = StateObject(wrappedValue: Browser(path: path))
    }

    init(url: URL, title: String) {
        self.title = title
        _browser = StateObject(wrappedValue: Browser(url: url))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if browser.loading {
                    ProgressView(value: browser.progress)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Page loading progress")
                        .accessibilityValue("\(Int(browser.progress * 100)) percent")
                }
                if let message = browser.error {
                    VStack(spacing: 12) {
                        Text(message)
                        Button("Retry loading") { browser.reload() }
                    }
                    .padding()
                    .accessibilityElement(children: .combine)
                }
                WebSurface(browser: browser)
            }

            if browser.loading {
                BrandedLoadingOverlay(title: title, reduceMotion: preferences.reduceAppMotion)
                    .transition(.opacity)
            }
        }
        .onAppear { browser.applyPreferences(preferences) }
        .onChange(of: preferences.pageZoom) { _, _ in browser.applyPreferences(preferences) }
        .onChange(of: preferences.pullToRefresh) { _, _ in browser.applyPreferences(preferences) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { browser.web.goBack() } label: { Label("Back", systemImage: "chevron.left") }.disabled(!browser.back)
                Button { browser.web.goForward() } label: { Label("Forward", systemImage: "chevron.right") }.disabled(!browser.forward)
                Spacer()
                Button { browser.reload() } label: { Label("Reload page", systemImage: "arrow.clockwise") }
                ShareLink(item: browser.web.url ?? browser.initialURL) { Label("Share page", systemImage: "square.and.arrow.up") }
                Button { UIApplication.shared.open(browser.web.url ?? browser.initialURL) } label: { Label("Open in Safari", systemImage: "safari") }
            }
        }
    }
}

struct BrandedLoadingOverlay: View {
    let title: String
    let reduceMotion: Bool
    var body: some View {
        VStack(spacing: 14) {
            PulsingBrandMark(size: 82, reduceMotion: reduceMotion)
            WaveformLoader(reduceMotion: reduceMotion)
            Text("Loading \(title)").font(.headline)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(title)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct PulsingBrandMark: View {
    let size: CGFloat
    let reduceMotion: Bool
    @State private var pulse = false
    var body: some View {
        BrandMark(size: size)
            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.08 : 0.94))
            .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.78))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityHidden(true)
    }
}

struct WaveformLoader: View {
    let reduceMotion: Bool
    @State private var animate = false
    private let heights: [CGFloat] = [12, 24, 36, 20, 42, 28, 16]
    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(.primary)
                    .frame(width: 4, height: reduceMotion ? height : (animate ? height : max(8, height * 0.45)))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.5 + Double(index) * 0.04).repeatForever(autoreverses: true).delay(Double(index) * 0.06), value: animate)
            }
        }
        .frame(height: 48)
        .onAppear { animate = true }
        .accessibilityHidden(true)
    }
}
