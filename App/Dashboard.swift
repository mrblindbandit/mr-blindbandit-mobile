import SwiftUI

struct ProfessionalHome: View {
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var privacy: PrivacyPermissions

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                BrandHeroPanel()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Create")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: columns, spacing: 14) {
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

                        NavigationLink { CreatorHubView() } label: {
                            DashboardCard(icon: "wand.and.stars", title: "All Creator Tools", subtitle: "Open the full native toolbox")
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Blindbandit Records")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    NavigationLink { Website(path: "/portal/", title: "Label Dashboard") } label: {
                        WideDashboardCard(icon: "building.2.crop.circle.fill", title: "Label Dashboard", subtitle: "Artists, earnings, contracts, messages, and internal tools")
                    }
                    .buttonStyle(.plain)

                    NavigationLink { Website(path: "/portal/payments/", title: "Payments") } label: {
                        WideDashboardCard(icon: "dollarsign.circle.fill", title: "Payments", subtitle: "Review payment and earnings information")
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("System Status").font(.headline)
                    HStack {
                        StatusPill(icon: "bell.badge.fill", text: push.statusText)
                        Spacer()
                        StatusPill(icon: "camera.fill", text: privacy.text(for: privacy.camera))
                    }
                    HStack {
                        StatusPill(icon: "mic.fill", text: privacy.text(for: privacy.microphone))
                        Spacer()
                        StatusPill(icon: "lock.shield.fill", text: "Protected")
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))

                HStack {
                    NavigationLink("Account") { Website(path: "/account", title: "Account") }
                    Spacer()
                    ShareLink("Share Website", item: URL(string: "https://mrblindbandit.net/")!)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Mr. Blind Bandit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BrandHeroPanel: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 30)
                .fill(
                    LinearGradient(
                        colors: [.black, Color(white: 0.12), Color(white: 0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 250)

            Circle()
                .fill(.yellow.opacity(0.14))
                .frame(width: 220, height: 220)
                .offset(x: 190, y: -75)
                .accessibilityHidden(true)

            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: 86, weight: .bold))
                .foregroundStyle(.yellow.opacity(0.20))
                .offset(x: 210, y: -95)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                BrandMark(size: 72)
                Text("MR. BLIND BANDIT")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text("Music · Creator Tools · Blindbandit Records")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.86))
                Text("mrblindbandit.net")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.yellow)
            }
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mr. Blind Bandit. Music, creator tools, and Blindbandit Records.")
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
            Section("Native audio tools") {
                NavigationLink { NativeAudioConverterView() } label: { Label("Audio Converter", systemImage: "waveform") }
                NavigationLink { NativeAudioTrimmerView() } label: { Label("Audio Trimmer", systemImage: "scissors") }
                NavigationLink { NativePeakNormalizerView() } label: { Label("Peak Normalizer", systemImage: "waveform.path") }
                NavigationLink { NativeAudioInspectorView() } label: { Label("Audio Inspector", systemImage: "waveform.badge.magnifyingglass") }
            }

            Section("Native artwork and video tools") {
                NavigationLink { NativeArtTrackGeneratorView() } label: { Label("Art Track Generator", systemImage: "play.rectangle") }
                NavigationLink { NativeArtworkResizerView() } label: { Label("Artwork Resizer", systemImage: "crop") }
                NavigationLink { NativeImageConverterView() } label: { Label("Image Converter", systemImage: "photo.on.rectangle.angled") }
            }

            Section("Website tools") {
                NavigationLink { Website(path: "/media-tools/", title: "Media Suite") } label: { Label("Online Media Suite", systemImage: "globe") }
                NavigationLink { Website(path: "/support/", title: "Support") } label: { Label("Support", systemImage: "questionmark.circle") }
            }

            Section("Publishing") {
                NavigationLink { Website(path: "/", title: "Website") } label: { Label("Open mrblindbandit.net", systemImage: "globe") }
                NavigationLink { Website(path: "/community/", title: "Community") } label: { Label("Community", systemImage: "person.3") }
            }
        }
        .navigationTitle("Creator Studio")
    }
}
