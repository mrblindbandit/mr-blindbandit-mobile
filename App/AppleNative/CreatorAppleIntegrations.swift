import SwiftUI

/// Journal / Image Playground entry points for creator tools — only where useful.
enum CreatorAppleIntegrations {
    static var imagePlaygroundAvailable: Bool {
        if #available(iOS 18.2, *) { return true }
        return false
    }

    static var journalAvailable: Bool {
        // Journal app deep link; no public compose API — surface as export/open only.
        true
    }
}

struct CreatorAppleToolsStrip: View {
    var biteText: String
    @State private var showPlaygroundInfo = false

    var body: some View {
        HStack(spacing: 12) {
            if CreatorAppleIntegrations.imagePlaygroundAvailable {
                Button {
                    showPlaygroundInfo = true
                } label: {
                    Label("Image Playground", systemImage: "paintbrush.pointed")
                }
                .accessibilityHint("Generate a creative image idea for this Bite on supported devices")
            }
            if CreatorAppleIntegrations.journalAvailable, !biteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ShareLink(item: biteText) {
                    Label("Save to Journal", systemImage: "book")
                }
                .accessibilityHint("Share this draft into Journal or another writing app")
            }
        }
        .font(.subheadline)
        .alert("Image Playground", isPresented: $showPlaygroundInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("On devices with Apple Intelligence Image Playground, use the system sheet from Photos or supported compose surfaces. Blind Bandit keeps this as an intentional creator entry — not a forced overlay.")
        }
    }
}
