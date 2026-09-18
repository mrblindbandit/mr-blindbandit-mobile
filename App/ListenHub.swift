import SwiftUI

struct ListenService: Identifiable {
    let id = UUID()
    let name: String
    let systemImage: String
    let deepLink: URL?
    let webPath: String?
    let subtitle: String
}

/// Music services — deep links + first-party streaming pages. Graceful degrade if apps missing.
struct ListenHubView: View {
    private let services: [ListenService] = [
        ListenService(name: "Spotify", systemImage: "music.note.list", deepLink: URL(string: "https://open.spotify.com/search/Mr%20Blind%20Bandit"), webPath: "/music/", subtitle: "Open Spotify or browse on the site"),
        ListenService(name: "Apple Music", systemImage: "applelogo", deepLink: URL(string: "https://music.apple.com/search?term=Mr%20Blind%20Bandit"), webPath: "/music/", subtitle: "Open Apple Music"),
        ListenService(name: "Amazon Music", systemImage: "headphones", deepLink: URL(string: "https://music.amazon.com/search/Mr%20Blind%20Bandit"), webPath: "/music/", subtitle: "Amazon Music search"),
        ListenService(name: "Audiomack", systemImage: "waveform", deepLink: URL(string: "https://audiomack.com/search?q=Mr%20Blind%20Bandit"), webPath: "/music/", subtitle: "Audiomack search"),
        ListenService(name: "YouTube Music", systemImage: "play.rectangle.fill", deepLink: URL(string: "https://music.youtube.com/search?q=Mr%20Blind%20Bandit"), webPath: "/music/", subtitle: "YouTube Music search"),
        ListenService(name: "SoundCloud", systemImage: "cloud.fill", deepLink: URL(string: "https://soundcloud.com/search?q=Mr%20Blind%20Bandit"), webPath: "/music/", subtitle: "SoundCloud search"),
        ListenService(name: "Tidal", systemImage: "water.waves", deepLink: URL(string: "https://listen.tidal.com/search?q=Mr%20Blind%20Bandit"), webPath: "/music/", subtitle: "Tidal search"),
        ListenService(name: "Blindbandit catalog", systemImage: "opticaldisc", deepLink: nil, webPath: "/music/", subtitle: "Official releases on mrblindbandit.net")
    ]

    @State private var favorites: [String] = UserDefaults.standard.stringArray(forKey: "listenFavorites") ?? []
    @State private var openFailedMessage = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    BlindbanditLogoImage(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Listen").font(.headline)
                        Text("Stream Blindbandit Records across major services.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section("Official site") {
                NavigationLink { Website(path: "/music/", title: "Music") } label: {
                    Label("Music on mrblindbandit.net", systemImage: "globe")
                }
                NavigationLink { Website(path: "/", title: "Latest") } label: {
                    Label("Latest drops", systemImage: "sparkles")
                }
            }

            Section("Services") {
                ForEach(services) { service in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(service.name, systemImage: service.systemImage)
                                .font(.headline)
                                .labelStyle(.titleAndIcon)
                            Spacer()
                            Button {
                                toggleFavorite(service.name)
                            } label: {
                                Image(systemName: favorites.contains(service.name) ? "star.fill" : "star")
                                    .foregroundStyle(.yellow)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel(favorites.contains(service.name) ? "Remove \(service.name) from favorites" : "Favorite \(service.name)")
                        }
                        Text(service.subtitle).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if let deepLink = service.deepLink {
                                Button("Open service") {
                                    AppHaptics.medium()
                                    UIApplication.shared.open(deepLink, options: [:]) { ok in
                                        if !ok {
                                            Task { @MainActor in
                                                openFailedMessage = "Could not open \(service.name). Use Browse site instead."
                                                AppHaptics.warning()
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .accessibilityHint("Opens \(service.name) in its app or browser.")
                            }
                            if let path = service.webPath {
                                NavigationLink("Browse site") { Website(path: path, title: service.name) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.yellow)
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !openFailedMessage.isEmpty {
                Section("Status") {
                    Text(openFailedMessage).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }

            Section("Pinned services") {
                if favorites.isEmpty {
                    Text("Star a service to pin it on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(favorites, id: \.self) { name in
                        Label(name, systemImage: "star.fill").foregroundStyle(.yellow)
                    }
                    Button("Clear pins", role: .destructive) {
                        favorites = []
                        UserDefaults.standard.set(favorites, forKey: "listenFavorites")
                        AppHaptics.warning()
                    }
                }
            }
        }
        .navigationTitle("Listen")
        .onAppear { AppHaptics.soft() }
    }

    private func toggleFavorite(_ name: String) {
        if let idx = favorites.firstIndex(of: name) { favorites.remove(at: idx) }
        else { favorites.append(name) }
        UserDefaults.standard.set(favorites, forKey: "listenFavorites")
        AppHaptics.selection()
    }
}
