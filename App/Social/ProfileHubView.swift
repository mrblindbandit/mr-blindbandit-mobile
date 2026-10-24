import SwiftUI

/// Profile tab: native profile, settings, groups/records shortcuts, owner Admin.
struct ProfileHubView: View {
    @EnvironmentObject private var auth: ClerkAuthService
    @EnvironmentObject private var communications: ProductionCommunicationsService

    var body: some View {
        List {
            Section {
                NavigationLink {
                    NativeProfileView(handle: "", isMe: true)
                } label: {
                    HStack(spacing: 14) {
                        ProfileAvatar(
                            urlString: communications.myAvatarURL,
                            displayName: displayName,
                            size: 56,
                            verified: communications.myVerified,
                            decorative: true
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(displayName).font(.headline)
                                if communications.myVerified { VerifiedBadge() }
                            }
                            Text(communications.myHandle.isEmpty ? "Set username" : "@\(communications.myHandle)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityLabel(communications.myVerified
                    ? "\(displayName), Verified, \(communications.myHandle.isEmpty ? "no username" : "@\(communications.myHandle)")"
                    : "\(displayName), \(communications.myHandle.isEmpty ? "no username" : "@\(communications.myHandle)")")
                .accessibilityHint("Opens your native Blindbandit profile")
            }

            Section("Account") {
                NavigationLink { Settings() } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                NavigationLink { UsernameEditor().navigationTitle("Username") } label: {
                    Label("Username", systemImage: "at")
                }
                NavigationLink { MessagesSettingsView() } label: {
                    Label("Messages & calls", systemImage: "bubble.left.and.bubble.right")
                }
                if AdminGate.isAdmin(handle: communications.myHandle, profileID: communications.myProfileID) {
                    NavigationLink { AdminPanelView() } label: {
                        Label("Admin", systemImage: "shield.checkered")
                    }
                    .accessibilityHint("Verify people, moderate Bites, review reports")
                }
            }

            Section("Create") {
                NavigationLink { CreatorHubView() } label: {
                    Label("Creator tools", systemImage: "wand.and.stars")
                }
            }

            Section("Read and listen") {
                NavigationLink { ChronicleView() } label: {
                    Label("The Blindbandit Chronicle", systemImage: "newspaper")
                }
                NavigationLink { ListenHubView() } label: {
                    Label("Listen to Blindbandit Records", systemImage: "headphones")
                }
            }

            Section("Blindbandit Records") {
                NavigationLink { Website(path: "/music/", title: "Music") } label: {
                    Label("Music", systemImage: "music.note")
                }
                NavigationLink { Website(path: "/about/", title: "About") } label: {
                    Label("About Mr. Blindbandit", systemImage: "info.circle")
                }
            }

            Section("Help") {
                NavigationLink { Website(url: AppConfig.supportURL, title: "Support") } label: {
                    Label("Help & support", systemImage: "questionmark.circle")
                }
            }
        }
        .navigationTitle("Profile")
        .task {
            if !communications.myHandle.isEmpty {
                BitesAPI.prefetchProfile(handle: communications.myHandle)
            }
        }
    }

    private var displayName: String {
        if case .signedIn(let name, _) = auth.state, !name.isEmpty { return name }
        if !communications.myHandle.isEmpty { return communications.myHandle }
        return "Blindbandit member"
    }
}
