import SwiftUI

struct ProfessionalHome: View {
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var router: TabRouter

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                BrandHeroPanel()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Create")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    LazyVGrid(columns: columns, spacing: 14) {
                        NavigationLink { NativeCreatorToolkitView() } label: {
                            DashboardCard(icon: "square.grid.3x3.fill", title: "Creator Toolkit", subtitle: "20 music tools that work offline")
                        }
                        .buttonStyle(.plain)

                        NavigationLink { NativeAudioConverterView() } label: {
                            DashboardCard(icon: "waveform", title: "Audio Converter", subtitle: "Local master and distribution exports")
                        }
                        .buttonStyle(.plain)

                        NavigationLink { NativeArtTrackGeneratorView() } label: {
                            DashboardCard(icon: "play.rectangle.fill", title: "Art Tracks", subtitle: "Local MP4 rendering")
                        }
                        .buttonStyle(.plain)

                        NavigationLink { NativeAudioTrimmerView() } label: {
                            DashboardCard(icon: "scissors", title: "Audio Trimmer", subtitle: "Cut audio locally")
                        }
                        .buttonStyle(.plain)

                        NavigationLink { NativePeakNormalizerView() } label: {
                            DashboardCard(icon: "waveform.path", title: "Peak Normalizer", subtitle: "Set local peak level")
                        }
                        .buttonStyle(.plain)

                        NavigationLink { NativeArtworkResizerView() } label: {
                            DashboardCard(icon: "crop", title: "Artwork Resizer", subtitle: "Cover and social presets")
                        }
                        .buttonStyle(.plain)

                        NavigationLink { NativeImageConverterView() } label: {
                            DashboardCard(icon: "photo.on.rectangle.angled", title: "Image Converter", subtitle: "PNG and JPEG exports")
                        }
                        .buttonStyle(.plain)

                        NavigationLink { NativeAudioInspectorView() } label: {
                            DashboardCard(icon: "waveform.badge.magnifyingglass", title: "Audio Inspector", subtitle: "Read technical file details")
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Connect")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    Button { router.selection = .connect } label: {
                        WideDashboardCard(icon: "phone.and.waveform.fill", title: "Calls & messages", subtitle: "Voice calls, video calls and messages with Blindbandit members")
                    }
                    .buttonStyle(.plain)

                    if push.authorizationStatus == .notDetermined {
                        Button { push.requestAuthorization() } label: {
                            WideDashboardCard(icon: "bell.badge.fill", title: "Turn on call and message alerts", subtitle: "Get notified when someone calls or messages you")
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink { MusicianStudioView() } label: {
                        WideDashboardCard(icon: "metronome.fill", title: "Musician Studio", subtitle: "Metronome, setlists, lyrics, release checklist, and more")
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Blindbandit Records")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    Button { router.selection = .listen } label: {
                        WideDashboardCard(icon: "headphones", title: "Listen", subtitle: "Mr. Blindbandit on Spotify, Apple Music and more")
                    }
                    .buttonStyle(.plain)

                    NavigationLink { Website(path: "/music/", title: "Music") } label: {
                        WideDashboardCard(icon: "opticaldisc", title: "Releases", subtitle: "Albums and singles from Blindbandit Records")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BrandHeroPanel: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [.black, Color(white: 0.12), Color(white: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 250)
            Circle().fill(.yellow.opacity(0.14)).frame(width: 220, height: 220).offset(x: 190, y: -75).accessibilityHidden(true)
            Image(systemName: "waveform.path.ecg.rectangle.fill").font(.system(size: 86, weight: .bold)).foregroundStyle(.yellow.opacity(0.20)).offset(x: 210, y: -95).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                BrandMark(size: 72)
                Text("MR. BLINDBANDIT").font(.system(.title, design: .rounded, weight: .heavy)).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
                Text("Music · Creator tools · Calls · Blindbandit Records").font(.headline).foregroundStyle(.white.opacity(0.9))
                Text("mrblindbandit.net").font(.subheadline.monospaced()).foregroundStyle(.yellow)
            }
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mr. Blindbandit. Music, creator tools, calls and Blindbandit Records.")
    }
}

struct DashboardCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.yellow)
                .frame(width: 48, height: 48)
                .background(.black, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.quaternary))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct WideDashboardCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.yellow)
                .frame(width: 58, height: 58)
                .background(.black, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct StatusPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(.quaternary, in: Capsule())
    }
}

struct CreatorHubView: View {
    var body: some View {
        List {
            Section("Toolkit") {
                NavigationLink { NativeCreatorToolkitView() } label: { Label("Creator toolkit (20 tools)", systemImage: "square.grid.3x3.fill") }
            }

            Section("Audio") {
                NavigationLink { NativeAudioConverterView() } label: { Label("Audio Converter", systemImage: "waveform") }
                NavigationLink { NativeAudioTrimmerView() } label: { Label("Audio Trimmer", systemImage: "scissors") }
                NavigationLink { NativePeakNormalizerView() } label: { Label("Peak Normalizer", systemImage: "waveform.path") }
                NavigationLink { NativeAudioInspectorView() } label: { Label("Audio Inspector", systemImage: "waveform.badge.magnifyingglass") }
            }

            Section("Artwork and video") {
                NavigationLink { NativeArtTrackGeneratorView() } label: { Label("Art Track Generator", systemImage: "play.rectangle") }
                NavigationLink { NativeArtworkResizerView() } label: { Label("Artwork Resizer", systemImage: "crop") }
                NavigationLink { NativeImageConverterView() } label: { Label("Image Converter", systemImage: "photo.on.rectangle.angled") }
            }

            Section("On mrblindbandit.net") {
                NavigationLink { Website(path: "/media-tools/", title: "Media tools") } label: { Label("Online media tools", systemImage: "globe") }
            }

            Section("Musician Studio") {
                NavigationLink { MusicianStudioView() } label: { Label("Musician Studio", systemImage: "metronome.fill") }
                NavigationLink { MetronomeView() } label: { Label("Metronome", systemImage: "metronome.fill") }
                NavigationLink { SetlistNotesView() } label: { Label("Setlist Notes", systemImage: "list.bullet.rectangle") }
                NavigationLink { LyricScratchpadView() } label: { Label("Lyric Scratchpad", systemImage: "pencil.and.list.clipboard") }
                NavigationLink { ReleaseChecklistView() } label: { Label("Release Checklist", systemImage: "checklist") }
            }

        }
        .navigationTitle("Create")
    }
}
