import SwiftUI

struct ReportTarget: Identifiable {
    let type: String
    let id: String
    let title: String
}

struct ReportSheet: View {
    let target: ReportTarget
    let submit: (ReportReason, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .harassment
    @State private var details = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Why are you reporting \(target.title)?")
                }
                Section("Details (optional)") {
                    TextField("What happened?", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Text("Reports go to the Blindbandit moderation team for review. If someone is in immediate danger, contact local emergency services.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sending = true
                        Task {
                            let ok = await submit(reason, details)
                            sending = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(sending)
                }
            }
        }
    }
}
