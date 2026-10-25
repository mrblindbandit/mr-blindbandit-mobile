import SwiftUI
import UIKit

/// Writing Tools hooks for Bite compose + message composer (iOS 18.1+).
struct WritingToolsTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: (() -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        if #available(iOS 18.0, *) {
            tv.writingToolsBehavior = .complete
        }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: WritingToolsTextField
        init(_ parent: WritingToolsTextField) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
    }
}

extension View {
    @ViewBuilder
    func banditWritingToolsEnabled(_ enabled: Bool = true) -> some View {
        if #available(iOS 18.0, *), enabled {
            self.writingToolsBehavior(.complete)
        } else {
            self
        }
    }
}
