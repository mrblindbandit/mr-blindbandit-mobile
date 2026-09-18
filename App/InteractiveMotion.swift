import SwiftUI

/// Shared press / spring motion. Honors Reduce Motion + AppPreferences.reduceAppMotion.
enum InteractiveMotion {
    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
            || (UserDefaults.standard.object(forKey: "reduceAppMotion") as? Bool ?? false)
    }

    static var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72)
    }

    static var snappy: Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)
    }
}

struct PressableScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !InteractiveMotion.reduceMotion ? pressedScale : 1)
            .animation(InteractiveMotion.snappy, value: configuration.isPressed)
    }
}

struct CallPulseRings: View {
    var active: Bool
    var reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.yellow.opacity(0.35 - Double(i) * 0.1), lineWidth: 2)
                    .scaleEffect(pulse && active && !reduceMotion ? 1.15 + CGFloat(i) * 0.18 : 1)
                    .opacity(pulse && active && !reduceMotion ? 0.15 : 0.45)
            }
        }
        .onAppear {
            guard active, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct ShimmerOverlay: View {
    var reduceMotion: Bool
    @State private var phase: CGFloat = -1

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            LinearGradient(
                colors: [.clear, .white.opacity(0.18), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .rotationEffect(.degrees(12))
            .offset(x: phase * 180)
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
