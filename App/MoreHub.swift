import SwiftUI

/// More — profile, account, web shortcuts, notifications, privacy, share, sign out.
struct MoreHubView: View {
    @EnvironmentObject private var auth: ClerkAuthService
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var lock: DeviceLock

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    BlindbanditLogoImage(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        if case .signedIn(let name, let email) = auth.state {
                            Text(name).font(.headline)
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Guest").font(.headline)
                            Text("Sign in required").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accountA11yLabel)
            }

            Section("Profile & account") {
                NavigationLink { Website(path: "/account", title: "Account") } label: {
                    Label("Manage account", systemImage: "person.crop.circle")
                }
                NavigationLink { Website(path: "/portal/", title: "Label portal") } label: {
                    Label("Blindbandit Records portal", systemImage: "building.2")
                }
                Button("Sign out", role: .destructive) {
                    AppHaptics.warning()
                    Task { await auth.signOut() }
                }
                .accessibilityHint("Signs out of Clerk and returns to the welcome screen.")
                NavigationLink { Settings() } label: {
                    Label("Delete account & privacy…", systemImage: "trash")
                }
                .accessibilityHint("Opens Settings where you can request account deletion.")
            }

            Section("Legal") {
                Link("Privacy Policy", destination: URL(string: "https://mrblindbandit.net/privacy/")!)
                Link("Terms of Use", destination: URL(string: "https://mrblindbandit.net/terms/")!)
            }

            Section("Website") {
                NavigationLink { Website(path: "/", title: "Home") } label: { Label("Website home", systemImage: "globe") }
                NavigationLink { Website(path: "/music/", title: "Music") } label: { Label("Music", systemImage: "music.note") }
                NavigationLink { Website(path: "/store/", title: "Store") } label: { Label("Store", systemImage: "bag") }
                NavigationLink { Website(path: "/about/", title: "About") } label: { Label("About", systemImage: "info.circle") }
                NavigationLink { Website(path: "/support/", title: "Support") } label: { Label("Support", systemImage: "questionmark.circle") }
                NavigationLink { Website(path: "/community/", title: "Community") } label: { Label("Community", systemImage: "person.3") }
                NavigationLink { Website(path: "/portal/payments/", title: "Payments") } label: { Label("Payments", systemImage: "dollarsign.circle") }
            }

            Section("Notifications & privacy") {
                LabeledContent("Push", value: push.statusText)
                LabeledContent("Camera", value: privacy.text(for: privacy.camera))
                LabeledContent("Microphone", value: privacy.text(for: privacy.microphone))
                Button("Lock app now") {
                    AppHaptics.rigid()
                    lock.lock()
                }
            }

            Section("Share") {
                ShareLink(item: URL(string: "https://mrblindbandit.net/")!) {
                    Label("Share mrblindbandit.net", systemImage: "square.and.arrow.up")
                }
            }

            Section("App") {
                NavigationLink { Settings() } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                LabeledContent("Version", value: "\(AppConfig.marketingVersion)")
            }
        }
        .navigationTitle("More")
        .onAppear { AppHaptics.soft() }
    }

    private var accountA11yLabel: String {
        if case .signedIn(let name, let email) = auth.state {
            return "Signed in as \(name), \(email)"
        }
        return "Not signed in"
    }
}

/// First-party web hub with many shortcuts (also used from tabs).
struct WebHubView: View {
    private let links: [(String, String, String)] = [
        ("Home", "/", "house.fill"),
        ("Music", "/music/", "music.note"),
        ("Store", "/store/", "bag.fill"),
        ("Account", "/account", "person.crop.circle"),
        ("Portal", "/portal/", "building.2.fill"),
        ("Payments", "/portal/payments/", "dollarsign.circle.fill"),
        ("Community", "/community/", "person.3.fill"),
        ("Media tools", "/media-tools/", "wrench.and.screwdriver.fill"),
        ("About", "/about/", "info.circle.fill"),
        ("Support", "/support/", "questionmark.circle.fill")
    ]

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    BlindbanditLogoImage(size: 48)
                    VStack(alignment: .leading) {
                        Text("mrblindbandit.net").font(.headline)
                        Text("Trusted first-party pages only.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Browse") {
                ForEach(links, id: \.1) { title, path, icon in
                    NavigationLink { Website(path: path, title: title) } label: {
                        Label(title, systemImage: icon)
                    }
                    .accessibilityHint("Opens \(title) on mrblindbandit.net inside the app.")
                }
            }
        }
        .navigationTitle("Web")
        .onAppear { AppHaptics.soft() }
    }
}
