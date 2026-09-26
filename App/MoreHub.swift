import SwiftUI

/// More: account, Blindbandit Records pages, settings and sharing.
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

            Section("Your account") {
                NavigationLink { Settings() } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                NavigationLink { Website(url: AppConfig.accountURL, title: "Profile & account") } label: {
                    Label("Profile & account", systemImage: "person.crop.circle")
                }
            }

            Section("Blindbandit Records") {
                NavigationLink { Website(path: "/music/", title: "Music") } label: { Label("Music", systemImage: "music.note") }
                NavigationLink { Website(path: "/store/", title: "Store") } label: { Label("Store", systemImage: "bag") }
                NavigationLink { Website(path: "/community/", title: "Community") } label: { Label("Community", systemImage: "person.3") }
                NavigationLink { Website(path: "/portal/", title: "Label portal") } label: { Label("Label portal for signed artists", systemImage: "building.2") }
                NavigationLink { Website(path: "/about/", title: "About") } label: { Label("About Mr. Blindbandit", systemImage: "info.circle") }
            }

            Section("Help") {
                NavigationLink { Website(url: AppConfig.supportURL, title: "Support") } label: { Label("Help & support", systemImage: "questionmark.circle") }
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
