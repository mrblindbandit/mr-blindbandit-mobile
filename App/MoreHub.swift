import SwiftUI

/// More: account, Blindbandit Records pages, settings and sharing — fully native hubs (Safari only for explicit external opens).
struct MoreHubView: View {
    @EnvironmentObject private var auth: ClerkAuthService
    @EnvironmentObject private var communications: ProductionCommunicationsService

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    BlindbanditLogoImage(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        if case .signedIn(let name, let email) = auth.state {
                            Text(name).font(.headline)
                            Text(communications.myHandle.isEmpty ? email : "@\(communications.myHandle)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("Not signed in").font(.headline)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section("Create") {
                NavigationLink { CreatorHubView() } label: { Label("Creator tools", systemImage: "wand.and.stars") }
            }

            Section("Read and listen") {
                NavigationLink { ChronicleView() } label: { Label("The Blindbandit Chronicle", systemImage: "newspaper") }
                NavigationLink { ListenHubView() } label: { Label("Listen to Blindbandit Records", systemImage: "headphones") }
            }

            Section("Discover") {
                NavigationLink { PeopleSearchView() } label: { Label("Search people", systemImage: "person.crop.circle.badge.magnifyingglass") }
                NavigationLink { NotificationsInboxView() } label: { Label("Notifications", systemImage: "bell") }
                NavigationLink { BiteBookmarksView() } label: { Label("Saved Bites", systemImage: "bookmark") }
            }

            Section("Your account") {
                NavigationLink { MessagesSettingsView() } label: {
                    Label("Messages & calls", systemImage: "bubble.left.and.bubble.right")
                }
                NavigationLink { Settings() } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                NavigationLink { ProfileView() } label: {
                    Label("Profile & account", systemImage: "person.crop.circle")
                }
            }

            Section("Blindbandit Records") {
                NavigationLink { NativeMusicHubView() } label: { Label("Music", systemImage: "music.note") }
                NavigationLink { NativeLabelHubView() } label: { Label("Blindbandit Records", systemImage: "opticaldisc") }
                NavigationLink { NativeCommunityHubView() } label: { Label("Community", systemImage: "person.3") }
                NavigationLink { NativeAboutHubView() } label: { Label("About Mr. Blindbandit", systemImage: "info.circle") }
            }

            Section("Help") {
                NavigationLink { NativeSupportHubView() } label: { Label("Help & support", systemImage: "questionmark.circle") }
                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                    Label("Email \(AppConfig.supportEmail)", systemImage: "envelope")
                }
            }

            Section {
                ShareLink(item: AppConfig.webBaseURL) {
                    Label("Share mrblindbandit.net", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("More")
    }
}
