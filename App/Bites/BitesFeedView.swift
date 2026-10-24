import SwiftUI

/// Root Bites tab: native social feed (newsfeed posts + BanditBites).
struct BitesTabView: View {
    var body: some View {
        NavigationStack {
            BitesFeedView()
        }
    }
}

@MainActor
final class BitesFeedModel: ObservableObject {
    @Published var items: [BiteItem] = []
    @Published var loading = false
    @Published var refreshing = false
    @Published var error = ""
    @Published var offlineHint = false
    private var didLoadOnce = false

    func bootstrap() async {
        if !didLoadOnce {
            let cached = BitesAPI.cachedNewsfeed()
            if !cached.isEmpty {
                items = cached
                didLoadOnce = true
            }
        }
        await reload(forceSpinner: items.isEmpty)
    }

    func reload(forceSpinner: Bool = false) async {
        if forceSpinner { loading = true }
        defer { loading = false; refreshing = false }
        do {
            let feed = try await BitesAPI.newsfeed(useCache: false)
            let videos = (try? await BitesAPI.videoBites()) ?? []
            // Videos first if any, then text posts; de-dupe by id
            var seen = Set<String>()
            var merged: [BiteItem] = []
            for i in videos + feed {
                if seen.insert(i.id).inserted { merged.append(i) }
            }
            items = merged
            error = ""
            offlineHint = false
            didLoadOnce = true
        } catch {
            if items.isEmpty {
                self.error = error.localizedDescription
            } else {
                offlineHint = true
            }
        }
    }

    func toggleLike(_ item: BiteItem) async {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let was = items[idx].liked_by_me
        items[idx].liked_by_me = !was
        items[idx].likes = max(0, items[idx].likes + (was ? -1 : 1))
        do {
            if was { try await BitesAPI.unlike(postID: item.id) }
            else { try await BitesAPI.like(postID: item.id) }
        } catch {
            items[idx].liked_by_me = was
            items[idx].likes = max(0, items[idx].likes + (was ? 1 : -1))
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }

    func insertOptimistic(_ item: BiteItem) {
        items.insert(item, at: 0)
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }
}

struct BitesFeedView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @StateObject private var model = BitesFeedModel()
    @State private var showComposer = false

    var body: some View {
        Group {
            if model.loading && model.items.isEmpty {
                ProgressView("Loading Bites")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading Bites")
            } else if !model.error.isEmpty && model.items.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t load Bites", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(model.error)
                } actions: {
                    Button("Retry") { Task { await model.reload(forceSpinner: true) } }
                }
            } else if model.items.isEmpty {
                ContentUnavailableView {
                    Label("No Bites yet", systemImage: "flame")
                } description: {
                    Text("Be the first to share a Bite. Text, photos, and short clips land here.")
                } actions: {
                    Button("New Bite") { showComposer = true }
                }
            } else {
                List {
                    if model.offlineHint {
                        Text("Showing cached Bites. Pull to refresh when you’re back online.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Showing cached Bites")
                    }
                    ForEach(model.items) { item in
                        BiteRow(item: item,
                                onLike: { Task { await model.toggleLike(item) } },
                                onDeleted: { model.remove(item.id) })
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Bites")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showComposer = true } label: {
                    Label("New Bite", systemImage: "plus.circle.fill")
                }
                .accessibilityHint("Compose a new Bite")
            }
        }
        .sheet(isPresented: $showComposer) {
            NavigationStack {
                BiteComposerView { published in
                    if let published {
                        model.insertOptimistic(published)
                    }
                    Task { await model.reload() }
                }
            }
        }
        .task { await model.bootstrap() }
        .refreshable { await model.reload() }
    }
}

struct BiteRow: View {
    let item: BiteItem
    var onLike: () -> Void
    var onDeleted: () -> Void
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var showReport = false
    @State private var reportNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NavigationLink {
                    NativeProfileView(handle: item.author.handle)
                } label: {
                    HStack(spacing: 10) {
                        ProfileAvatar(
                            urlString: item.author.avatar_url,
                            displayName: item.author.display_name,
                            size: 40,
                            verified: item.author.verified,
                            decorative: true
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(item.author.display_name).font(.headline)
                                if item.author.verified { VerifiedBadge() }
                            }
                            Text("@\(item.author.handle) · \(relative(item.created_at))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.author.verified
                    ? "\(item.author.display_name), Verified, @\(item.author.handle)"
                    : "\(item.author.display_name), @\(item.author.handle)")
                Spacer(minLength: 0)
            }

            if !item.displayText.isEmpty {
                Text(item.displayText)
                    .font(.body)
                    .textSelection(.enabled)
            }

            if let video = item.video_url, !video.isEmpty {
                Label("Short video Bite", systemImage: "play.rectangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Short video Bite attached")
            } else if !item.media.isEmpty {
                Label("\(item.media.count) media", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                Button(action: onLike) {
                    Label("\(item.likes)", systemImage: item.liked_by_me ? "heart.fill" : "heart")
                }
                .accessibilityLabel(item.liked_by_me ? "Unlike, \(item.likes) likes" : "Like, \(item.likes) likes")
                .tint(item.liked_by_me ? .red : .primary)

                NavigationLink {
                    BiteDetailView(item: item, onDeleted: onDeleted)
                } label: {
                    Label("\(item.comments)", systemImage: "bubble.right")
                }
                .accessibilityLabel("Comments, \(item.comments)")

                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Share Bite")
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.accessibilitySummary)
        .contextMenu {
            Button { onLike() } label: {
                Label(item.liked_by_me ? "Unlike" : "Like", systemImage: item.liked_by_me ? "heart.slash" : "heart")
            }
            Button { showReport = true } label: {
                Label("Report", systemImage: "flag")
            }
            if item.author.handle.lowercased() == communications.myHandle.lowercased() {
                Button(role: .destructive) {
                    Task {
                        try? await BitesAPI.deletePost(id: item.id)
                        onDeleted()
                        UIAccessibility.post(notification: .announcement, argument: "Bite deleted")
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .alert("Report Bite", isPresented: $showReport) {
            TextField("What is wrong?", text: $reportNote)
            Button("Submit") {
                Task {
                    try? await BitesAPI.report(targetType: "post", targetID: item.id, reason: "user_report", details: reportNote)
                    UIAccessibility.post(notification: .announcement, argument: "Report sent")
                    reportNote = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reports go to Blindbandit moderators.")
        }
    }

    private var shareText: String {
        "\(item.author.display_name) (@\(item.author.handle)): \(item.displayText)"
    }

    private func relative(_ ms: Double) -> String {
        let seconds = ms > 1_000_000_000_000 ? ms / 1000 : ms
        guard seconds > 0 else { return "" }
        return Date(timeIntervalSince1970: seconds).formatted(.relative(presentation: .named))
    }
}

struct BiteComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var text = ""
    @State private var posting = false
    @State private var error = ""
    var onDone: (BiteItem?) -> Void

    var body: some View {
        Form {
            Section {
                TextField("What’s happening?", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .accessibilityLabel("Bite text")
            }
            if !error.isEmpty {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("New Bite")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(posting ? "Posting…" : "Post") { Task { await post() } }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || posting)
            }
        }
    }

    private func post() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        posting = true
        defer { posting = false }
        let optimistic = BitesAPI.makeLocalPost(
            body: body,
            handle: communications.myHandle.isEmpty ? "me" : communications.myHandle,
            displayName: communications.myHandle.isEmpty ? "You" : communications.myHandle,
            avatar: communications.myAvatarURL,
            verified: communications.myVerified
        )
        do {
            _ = try await BitesAPI.publishPost(body: body)
            onDone(optimistic)
            dismiss()
            UIAccessibility.post(notification: .announcement, argument: "Bite posted")
        } catch {
            self.error = error.localizedDescription
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }
}

struct BiteDetailView: View {
    let item: BiteItem
    var onDeleted: () -> Void
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var comments: [BiteComment] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var error = ""

    var body: some View {
        List {
            Section {
                BiteRow(item: item, onLike: {}, onDeleted: onDeleted)
            }
            Section("Comments") {
                if loading && comments.isEmpty {
                    ProgressView("Loading comments")
                } else if comments.isEmpty {
                    Text("No comments yet.").foregroundStyle(.secondary)
                }
                ForEach(comments) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(c.author.display_name).font(.subheadline.weight(.semibold))
                            if c.author.verified { VerifiedBadge() }
                            Text("@\(c.author.handle)").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(c.body)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                HStack {
                    TextField("Add a comment", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                    Button("Send") { Task { await send() } }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !error.isEmpty {
                Section { Text(error).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Bite")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            comments = try await BitesAPI.comments(postID: item.id)
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            try await BitesAPI.addComment(postID: item.id, body: body)
            draft = ""
            await load()
            UIAccessibility.post(notification: .announcement, argument: "Comment posted")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
