import TipKit
import SwiftUI

struct SwipeToLikeTip: Tip {
    var title: Text { Text("Swipe to like") }
    var message: Text? { Text("Swipe right on a Bite to like it instantly.") }
    var image: Image? { Image(systemName: "hand.thumbsup.fill") }
}

struct MagicTapTip: Tip {
    var title: Text { Text("Magic Tap") }
    var message: Text? { Text("Two-finger double-tap can end or answer Blind Bandit calls when enabled in Settings.") }
    var image: Image? { Image(systemName: "hand.tap.fill") }
}

struct SearchTheWebTip: Tip {
    var title: Text { Text("Search the web") }
    var message: Text? { Text("Ask Blind Bandit AI to search the web when you need fresh answers.") }
    var image: Image? { Image(systemName: "globe") }
}

@MainActor
enum BanditTips {
    static func configure() {
        try? Tips.configure([
            .displayFrequency(.daily),
            .datastoreLocation(.applicationDefault),
        ])
    }
}

struct BanditTipBanner<T: Tip>: View {
    var tip: T
    var body: some View {
        TipView(tip)
            .tipBackground(.ultraThinMaterial)
    }
}
