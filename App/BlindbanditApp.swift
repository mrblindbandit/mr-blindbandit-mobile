import SwiftUI
import WebKit
import LocalAuthentication

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

@main struct BlindbanditApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var lock = DeviceLock()
    @StateObject private var push = PushNotifications()
    @StateObject private var privacy = PrivacyPermissions()
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
                        .accessibilityHidden(phase != .active)
                } else {
                    LockedView(lock: lock)
                }

                if phase != .active {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    Label("Blindbandit — private", systemImage: "lock.fill").font(.headline)
                }

                if showingLaunchCover && phase == .active {
                    LaunchCover()
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.easeOut(duration: 0.2)) { showingLaunchCover = false }
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
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                BrandMark(size: 104)
                Text("MR. BLINDBANDIT")
                    .font(.title.bold())
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
            NavigationStack { Home() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { Website(path: "/account", title: "Profile") }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            NavigationStack { Website(path: "/portal/", title: "Label dashboard") }
                .tabItem { Label("Label", systemImage: "building.2") }
            NavigationStack { Settings() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushDeepLinkReceived)) { note in
            guard let url = note.object as? URL else { return }
            if Browser.isFirstPartyURL(url) {
                routedURL = RoutedURL(url: url)
            } else {
                UIApplication.shared.open(url)
            }
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
                        Text("Blindbandit Records · Native companion")
                            .foregroundStyle(.secondary)
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
                Label("File uploads use the native iOS file and photo pickers", systemImage: "square.and.arrow.up")
                Label("Camera: \(privacy.text(for: privacy.camera))", systemImage: "camera")
                Label("Microphone: \(privacy.text(for: privacy.microphone))", systemImage: "mic")
            }

            Section("Label shortcuts") {
                NavigationLink("Label dashboard") { Website(path: "/portal/", title: "Label dashboard") }
                NavigationLink("Payment overview") { Website(path: "/portal/payments/", title: "Payments") }
            }

            Section("App status") {
                Label("Push notifications: \(push.statusText)", systemImage: "bell.badge")
                NavigationLink("Permissions and notifications") { Settings() }
            }

            Section("Share") {
                ShareLink("Share public website", item: URL(string: "https://mrblindbandit.net/")!)
            }
        }
        .navigationTitle("Home")
    }
}

struct Settings: View {
    @EnvironmentObject private var lock: DeviceLock
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var privacy: PrivacyPermissions
    @State private var confirm = false
    @State private var clearing = false

    var body: some View {
        Form {
            Section("Notifications") {
                LabeledContent("Push notifications", value: push.statusText)

                if push.authorizationStatus == .notDetermined {
                    Button("Enable push notifications") { push.requestAuthorization() }
                        .disabled(push.busy)
                } else if push.authorizationStatus == .denied {
                    Button("Open notification settings") { openSystemSettings() }
                } else {
                    Button("Refresh notification registration") {
                        Task { await push.refresh() }
                    }
                }

                if push.busy { ProgressView("Requesting notification permission") }
                if !push.registrationError.isEmpty {
                    Text("Apple push registration: \(push.registrationError)")
                        .foregroundStyle(.secondary)
                }

                Text("The app is wired for Apple Push Notification service. A production-signed build and your server-side push sender are required for remote delivery.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Camera, microphone, and files") {
                LabeledContent("Camera", value: privacy.text(for: privacy.camera))
                if privacy.camera == .notDetermined {
                    Button("Allow camera access") { privacy.requestCamera() }
                }

                LabeledContent("Microphone", value: privacy.text(for: privacy.microphone))
                if privacy.microphone == .notDetermined {
                    Button("Allow microphone access") { privacy.requestMicrophone() }
                }

                if privacy.camera == .denied || privacy.microphone == .denied {
                    Button("Open app permission settings") { openSystemSettings() }
                }

                Text("Website upload controls inside the app use iOS file and photo pickers. Camera and microphone capture are allowed only for approved Mr. Blindbandit first-party pages and still require iOS permission.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Security") {
                Label("Device authentication required", systemImage: "lock.shield")
                Text("Your app locks when it enters the background. Website permissions are checked separately by the server.")
                Button("Lock app now") { lock.lock() }
                Button("Clear website sessions on this device", role: .destructive) { confirm = true }
                    .disabled(clearing)
            }

            Section("Accessibility") {
                Text("Native controls support VoiceOver and Dynamic Type. Appearance follows your device settings. Website accessibility depends on each page.")
                Button("Open app settings") { openSystemSettings() }
            }

            Section("Account") {
                NavigationLink("Account and security settings") { Website(path: "/account", title: "Account") }
                Text("Your Clerk session is retained by iOS WebKit until it expires, is revoked, or is cleared. No reusable server secrets are bundled in the app.")
            }

            Section("About") {
                Text("Blindbandit native companion 1.1")
                Text("Native navigation, push-notification framework, camera and microphone permissions, first-party media capture, file uploads, and connected website screens.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear this device's website sessions?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Clear sessions", role: .destructive) {
                clearing = true
                WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                    Task { @MainActor in
                        clearing = false
                        lock.lock()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears cookies and website storage in this app. Other devices are unaffected.")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

@MainActor final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let firstPartyHosts: Set<String> = [
        "mrblindbandit.net",
        "www.mrblindbandit.net",
        "portal.mrblindbandit.net",
        "api.mrblindbandit.net",
        "clerk.mrblindbandit.net",
        "accounts.mrblindbandit.net"
    ]

    static func isFirstPartyURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return firstPartyHosts.contains(host)
    }

    let web: WKWebView
    let initialURL: URL
    @Published var loading = false
    @Published var error: String?
    @Published var back = false
    @Published var forward = false

    convenience init(path: String) {
        self.init(url: URL(string: "https://mrblindbandit.net" + path)!)
    }

    init(url: URL) {
        initialURL = url
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []

        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.allowsLinkPreview = false
        web.scrollView.keyboardDismissMode = .interactive
        web.load(URLRequest(url: initialURL))
    }

    func reload() {
        error = nil
        if web.url == nil {
            web.load(URLRequest(url: initialURL))
        } else {
            web.reload()
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true
        error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        back = webView.canGoBack
        forward = webView.canGoForward
    }

    func failed(_ failure: Error) {
        guard (failure as NSError).code != NSURLErrorCancelled else { return }
        loading = false
        error = "This page could not load. Check your connection and try again."
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        error = "The page stopped responding. Reload to continue. Unsaved changes may be lost."
    }

    func firstParty(_ url: URL) -> Bool { Self.isFirstPartyURL(url) }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }

        if action.targetFrame?.isMainFrame == false || firstParty(url) {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)
        if ["https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
            UIApplication.shared.open(url)
        } else {
            loading = false
            error = "Open this page in Safari to use this link."
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        if firstParty(url) {
            webView.load(action.request)
        } else if url.scheme?.lowercased() == "https" {
            UIApplication.shared.open(url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let host = origin.host.lowercased()
        decisionHandler(Self.firstPartyHosts.contains(host) ? .grant : .deny)
    }

    private func show(_ alert: UIAlertController, fallback: () -> Void) {
        guard var presenter = web.window?.rootViewController,
              UIApplication.shared.applicationState == .active else {
            fallback()
            return
        }
        while let shown = presenter.presentedViewController { presenter = shown }
        presenter.present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: "Website message", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        show(alert, fallback: completionHandler)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: "Confirm website action", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Confirm", style: .default) { _ in completionHandler(true) })
        show(alert) { completionHandler(false) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: "Website input", message: prompt, preferredStyle: .alert)
        alert.addTextField {
            $0.text = defaultText
            $0.accessibilityLabel = prompt
        }
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
        VStack(spacing: 0) {
            if browser.loading { ProgressView("Loading page").padding(8) }
            if let message = browser.error {
                VStack {
                    Text(message)
                    Button("Retry loading") { browser.reload() }
                }
                .padding()
            }
            WebSurface(browser: browser)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { browser.web.goBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(!browser.back)

                Button { browser.web.goForward() } label: {
                    Label("Forward", systemImage: "chevron.right")
                }
                .disabled(!browser.forward)

                Spacer()

                Button { browser.reload() } label: {
                    Label("Reload page", systemImage: "arrow.clockwise")
                }

                Button { UIApplication.shared.open(browser.web.url ?? browser.initialURL) } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
            }
        }
    }
}
