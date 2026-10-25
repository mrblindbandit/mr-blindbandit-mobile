import SwiftUI
import WatchKit

@main
struct BlindbanditWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

struct WatchRootView: View {
    @State private var unread = 0
    @State private var replyText = ""
    @State private var status = "Ready"

    var body: some View {
        NavigationStack {
            List {
                Section("Inbox") {
                    Label("\(unread) unread", systemImage: "message.fill")
                    Button("Refresh") { refresh() }
                }
                Section("Quick reply") {
                    TextField("Reply…", text: $replyText)
                    Button("Send quick reply") {
                        status = replyText.isEmpty ? "Type a reply first" : "Queued reply to phone"
                        replyText = ""
                    }
                }
                Section("Calls") {
                    Button {
                        status = "Ring / start call intent sent"
                        WKInterfaceDevice.current().play(.notification)
                    } label: {
                        Label("Ring / start call", systemImage: "phone.fill")
                    }
                }
                Section("Status") {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bandit")
            .onAppear(perform: refresh)
        }
    }

    private func refresh() {
        unread = UserDefaults(suiteName: "group.net.mrblindbandit.app")?.integer(forKey: "widget.unreadDMCount") ?? 0
        status = "Synced \(Date().formatted(date: .omitted, time: .shortened))"
    }
}
