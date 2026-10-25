import SwiftUI

/// Fully native informational hubs that replace WKWebView shells for core More/Listen/Profile links.
/// External Safari Links are used only when the user explicitly wants the public website.

struct NativeMusicHubView: View {
    var body: some View {
        List {
            Section {
                Text("Blindbandit Records releases, singles, and playlists — native on your iPhone. Open the public site only when you want the full web catalog.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Listen") {
                NavigationLink { ListenHubView() } label: {
                    Label("Listen hub", systemImage: "headphones")
                }
                if let url = URL(string: "https://music.apple.com/search?term=Mr%20Blindbandit") {
                    Link(destination: url) {
                        Label("Search Apple Music", systemImage: "music.note")
                    }
                }
            }
            Section("Open on the web") {
                Link(destination: AppConfig.webBaseURL.appendingPathComponent("music/")) {
                    Label("Open music on mrblindbandit.net", systemImage: "safari")
                }
            }
        }
        .navigationTitle("Music")
    }
}

struct NativeLabelHubView: View {
    var body: some View {
        List {
            Section {
                Text("Blindbandit Records is the label home for Mr. BlindBandit and signed artists. Use Creator tools in-app; open the label page in Safari for the public roster.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("In the app") {
                NavigationLink { CreatorHubView() } label: {
                    Label("Creator tools", systemImage: "wand.and.stars")
                }
                NavigationLink { ChronicleView() } label: {
                    Label("The Blindbandit Chronicle", systemImage: "newspaper")
                }
            }
            Section("On the web") {
                Link(destination: AppConfig.webBaseURL.appendingPathComponent("label/")) {
                    Label("Blindbandit Records site", systemImage: "safari")
                }
                Link(destination: AppConfig.webBaseURL.appendingPathComponent("portal/")) {
                    Label("Label portal for signed artists", systemImage: "building.2")
                }
            }
        }
        .navigationTitle("Blindbandit Records")
    }
}

struct NativeCommunityHubView: View {
    var body: some View {
        List {
            Section {
                Text("Meet people, follow profiles, and join the conversation — all native. The community website is optional.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Discover") {
                NavigationLink { PeopleSearchView() } label: {
                    Label("Search people", systemImage: "person.crop.circle.badge.magnifyingglass")
                }
                NavigationLink { NotificationsInboxView() } label: {
                    Label("Notifications", systemImage: "bell")
                }
                NavigationLink { BitesFeedView() } label: {
                    Label("Bandit Feed", systemImage: "flame")
                }
            }
            Section("On the web") {
                Link(destination: AppConfig.webBaseURL.appendingPathComponent("community/")) {
                    Label("Community on the website", systemImage: "safari")
                }
            }
        }
        .navigationTitle("Community")
    }
}

struct NativeAboutHubView: View {
    var body: some View {
        List {
            Section {
                BlindbanditLogoImage(size: 72)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text("Mr. BlindBandit")
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity)
                Text("Blind-first messaging, calls, Bandit Feed, Bites, and AI — built so VoiceOver users get a Facebook-class feel without Meta trademarks.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Section("Version") {
                LabeledContent("App", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
            Section("Links") {
                Link(destination: AppConfig.webBaseURL.appendingPathComponent("about/")) {
                    Label("About on the website", systemImage: "safari")
                }
                Link(destination: AppConfig.supportURL) {
                    Label("Help & support", systemImage: "questionmark.circle")
                }
                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                    Label("Email \(AppConfig.supportEmail)", systemImage: "envelope")
                }
            }
        }
        .navigationTitle("About")
    }
}

struct NativeSupportHubView: View {
    var body: some View {
        List {
            Section {
                Text("Get help without leaving the app. Email support or open the public help page in Safari.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Contact") {
                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                    Label("Email \(AppConfig.supportEmail)", systemImage: "envelope")
                }
                Link(destination: AppConfig.supportURL) {
                    Label("Open help in Safari", systemImage: "safari")
                }
            }
            Section("In-app") {
                NavigationLink { Settings() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                NavigationLink { AccessibilitySettingsDeepLink() } label: {
                    Label("Accessibility", systemImage: "accessibility")
                }
            }
        }
        .navigationTitle("Help & support")
    }
}

/// Thin wrapper so More/Settings can deep-link into expanded a11y without depending on private types.
struct AccessibilitySettingsDeepLink: View {
    var body: some View {
        BlindExtrasSettingsView()
    }
}

struct NativeMediaToolsHubView: View {
    var body: some View {
        List {
            Section {
                Text("Creator and media tools live in the app. Online media tools open in Safari when you need the website.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            NavigationLink { CreatorHubView() } label: {
                Label("Creator tools", systemImage: "wand.and.stars")
            }
            Link(destination: AppConfig.webBaseURL.appendingPathComponent("media-tools/")) {
                Label("Online media tools (Safari)", systemImage: "safari")
            }
        }
        .navigationTitle("Media tools")
    }
}
