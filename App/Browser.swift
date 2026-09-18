import SwiftUI
import WebKit
import UIKit

@MainActor
final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
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

    convenience init(path: String) {
        self.init(url: URL(string: "https://mrblindbandit.net" + path)!)
    }

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
        let savedZoom = UserDefaults.standard.double(forKey: "pageZoom")
        web.pageZoom = min(max(savedZoom == 0 ? 1.0 : savedZoom, 0.75), 2.0)
        configurePullToRefresh()
        progressObservation = web.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor in self?.progress = webView.estimatedProgress }
        }
        web.load(URLRequest(url: initialURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    deinit { progressObservation?.invalidate() }

    func applyPreferences(_ preferences: AppPreferences) {
        web.pageZoom = preferences.pageZoom
        if preferences.pullToRefresh { configurePullToRefresh() }
        else { web.scrollView.refreshControl = nil }
    }

    private func configurePullToRefresh() {
        guard UserDefaults.standard.object(forKey: "pullToRefresh") as? Bool ?? true else { return }
        guard web.scrollView.refreshControl == nil else { return }
        let control = UIRefreshControl()
        control.accessibilityLabel = "Refresh website"
        control.addTarget(self, action: #selector(refreshFromPull), for: .valueChanged)
        web.scrollView.refreshControl = control
    }

    @objc private func refreshFromPull() {
        AppHaptics.medium()
        reload()
    }

    func reload() {
        error = nil
        if web.url == nil { web.load(URLRequest(url: initialURL)) }
        else { web.reload() }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true
        progress = 0
        error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        progress = 1
        back = webView.canGoBack
        forward = webView.canGoForward
        webView.scrollView.refreshControl?.endRefreshing()
        AppHaptics.soft()
        if UserDefaults.standard.object(forKey: "announcePageLoads") as? Bool ?? true {
            UIAccessibility.post(notification: .announcement, argument: "Page loaded")
        }
    }

    private func failed(_ failure: Error) {
        guard (failure as NSError).code != NSURLErrorCancelled else { return }
        loading = false
        web.scrollView.refreshControl?.endRefreshing()
        error = "This page could not load. Check your connection and try again."
        AppHaptics.error()
        UIAccessibility.post(notification: .announcement, argument: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        error = "The page stopped responding. Reload to continue. Unsaved changes may be lost."
        AppHaptics.error()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false || Self.isFirstPartyURL(url) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if ["https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
            AppHaptics.light()
            UIApplication.shared.open(url)
        } else {
            loading = false
            error = "Open this page in Safari to use this link."
            AppHaptics.warning()
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        if Self.isFirstPartyURL(url) { webView.load(action.request) }
        else if url.scheme?.lowercased() == "https" {
            AppHaptics.light()
            UIApplication.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let allowed = Self.firstPartyHosts.contains(origin.host.lowercased())
        AppHaptics.selection()
        decisionHandler(allowed ? .grant : .deny)
    }

    private func show(_ alert: UIAlertController, fallback: () -> Void) {
        guard var presenter = web.window?.rootViewController, UIApplication.shared.applicationState == .active else {
            fallback()
            return
        }
        while let shown = presenter.presentedViewController { presenter = shown }
        AppHaptics.warning()
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "Website message", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            Task { @MainActor in AppHaptics.light() }
            completionHandler()
        })
        show(alert, fallback: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "Confirm website action", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            Task { @MainActor in AppHaptics.light() }
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "Confirm", style: .default) { _ in
            Task { @MainActor in AppHaptics.medium() }
            completionHandler(true)
        })
        show(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "Website input", message: prompt, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = defaultText
            field.accessibilityLabel = prompt
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            Task { @MainActor in AppHaptics.light() }
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
            Task { @MainActor in AppHaptics.medium() }
            completionHandler(alert.textFields?.first?.text)
        })
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
                        Button("Retry loading") {
                            AppHaptics.medium()
                            browser.reload()
                        }
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
        .onAppear {
            browser.applyPreferences(preferences)
            AppHaptics.soft()
        }
        .onChange(of: preferences.pageZoom) { _, _ in browser.applyPreferences(preferences) }
        .onChange(of: preferences.pullToRefresh) { _, _ in browser.applyPreferences(preferences) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    AppHaptics.light()
                    browser.web.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(!browser.back)

                Button {
                    AppHaptics.light()
                    browser.web.goForward()
                } label: {
                    Label("Forward", systemImage: "chevron.right")
                }
                .disabled(!browser.forward)

                Spacer()

                Button {
                    AppHaptics.medium()
                    browser.reload()
                } label: {
                    Label("Reload page", systemImage: "arrow.clockwise")
                }

                ShareLink(item: browser.web.url ?? browser.initialURL) {
                    Label("Share page", systemImage: "square.and.arrow.up")
                }
                .simultaneousGesture(TapGesture().onEnded { AppHaptics.light() })

                Button {
                    AppHaptics.light()
                    UIApplication.shared.open(browser.web.url ?? browser.initialURL)
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
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
