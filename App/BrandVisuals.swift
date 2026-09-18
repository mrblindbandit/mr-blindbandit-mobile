import SwiftUI

/// Gold Blindbandit Records brand visuals — spinning logo loaders, progress overlays, marks.
struct BlindbanditLogoImage: View {
    var size: CGFloat = 96

    var body: some View {
        Group {
            if let uiImage = UIImage(named: "BlindbanditRecordsGold")
                ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "BlindbanditRecordsGold", ofType: "jpeg") ?? "") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                // Fallback vector mark when asset is missing from the bundle
                ZStack {
                    Circle().fill(.black)
                    Circle().stroke(Color.yellow.opacity(0.9), lineWidth: max(2, size * 0.04))
                    Image(systemName: "opticaldisc")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.yellow)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct SpinningBrandLogo: View {
    var size: CGFloat = 88
    var reduceMotion: Bool = false
    @State private var rotating = false

    var body: some View {
        BlindbanditLogoImage(size: size)
            .rotationEffect(.degrees(reduceMotion ? 0 : (rotating ? 360 : 0)))
            .animation(reduceMotion ? nil : .linear(duration: 2.4).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
            .accessibilityLabel("Blindbandit Records logo")
    }
}

struct PulsingBrandMark: View {
    var size: CGFloat = 96
    var reduceMotion: Bool = false
    @State private var pulse = false

    var body: some View {
        BlindbanditLogoImage(size: size)
            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.06 : 0.94))
            .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.82))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct WaveformLoader: View {
    var reduceMotion: Bool = false
    private let bars: [CGFloat] = [14, 28, 40, 22, 46, 30, 18]
    @State private var animate = false

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, maxHeight in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.yellow)
                    .frame(width: 4, height: reduceMotion ? maxHeight : (animate ? maxHeight : 8))
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.45 + Double(index) * 0.04)
                            .repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .frame(height: 52)
        .onAppear { animate = true }
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct BrandProgressOverlay: View {
    var title: String = "Loading"
    var progress: Double? = nil
    var reduceMotion: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                SpinningBrandLogo(size: 96, reduceMotion: reduceMotion)
                WaveformLoader(reduceMotion: reduceMotion)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(.yellow)
                        .frame(width: 180)
                    Text("\(Int(progress * 100)) percent")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .accessibilityLabel("\(Int(progress * 100)) percent complete")
                }
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.yellow.opacity(0.35), lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.map { "\(title), \(Int($0 * 100)) percent" } ?? title)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct GoldProgressBar: View {
    var value: Double
    var label: String = "Progress"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: min(max(value, 0), 1))
                .tint(.yellow)
                .accessibilityLabel(label)
                .accessibilityValue("\(Int(value * 100)) percent")
            HStack {
                BlindbanditLogoImage(size: 18)
                Text("\(Int(value * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
