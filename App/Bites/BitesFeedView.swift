import SwiftUI
import TipKit
import UIKit

/// Root Bites tab: native Bandit Feed (newsfeed posts + BanditBites). Never Facebook/Meta branded.
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
    @Published var composerDraft = ""
    private var didLoadOnce = false

    func bootstrap() async {
        if !didLoadOnce {
            let cached = BitesAPI.cachedNewsfeed()
            if !cached.isEmpty {
                items = cached
                didLoadOnce = true
            }
            composerDraft = UserDefaults.standard.string(forKey: SettingsKey.bitesComposerDraft) ?? ""
        }
        await reload(forceSpinner: items.isEmpty)
    }

    func reload(forceSpinner: Bool = false) async {
        if forceSpinner { loading = true }
        defer { loading = false; refreshing = false }
        do {
            let feed = try await BitesAPI.newsfeed(useCache: false)
            let videos = (try? await BitesAPI.videoBites()) ?? []
            var seen = Set<String>()
            var merged: [BiteItem] = []
            for i in videos + feed {
                if seen.insert(i.id).inserted { merged.append(i) }
            }
            let muted = Set(BitesLocalPrefs.mutedAuthors)
            let hidden = Set(BitesLocalPrefs.hiddenPostIDs)
            items = merged.filter { !hidden.contains($0.id) && !muted.contains($0.author.handle.lowercased()) }
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
        if !was { AppHaptics.success() } else { AppHaptics.light() }
        do {
            if was { try await BitesAPI.unlike(postID: item.id) }
            else { try await BitesAPI.like(postID: item.id) }
            UIAccessibility.post(notification: .announcement, argument: was ? "Unliked" : "Liked")
        } catch {
            items[idx].liked_by_me = was
            items[idx].likes = max(0, items[idx].likes + (was ? 1 : -1))
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }

    func setReaction(_ item: BiteItem, reaction: String) async {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let prev = items[idx].my_reaction
        items[idx].my_reaction = reaction
        if !items[idx].liked_by_me {
            items[idx].liked_by_me = true
            items[idx].likes += 1
        }
        AppHaptics.medium()
        do {
            try await BitesAPI.react(postID: item.id, reaction: reaction)
            UIAccessibility.post(notification: .announcement, argument: "Reacted \(reaction)")
        } catch {
            items[idx].my_reaction = prev
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }

    func insertOptimistic(_ item: BiteItem) {
        items.insert(item, at: 0)
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
        BitesLocalPrefs.hidePost(id)
    }

    func muteAuthor(_ handle: String) {
        BitesLocalPrefs.muteAuthor(handle)
        items.removeAll { $0.author.handle.lowercased() == handle.lowercased() }
    }

    func saveDraft(_ text: String) {
        composerDraft = text
        UserDefaults.standard.set(text, forKey: SettingsKey.bitesComposerDraft)
    }

    func clearDraft() {
        composerDraft = ""
        UserDefaults.standard.removeObject(forKey: SettingsKey.bitesComposerDraft)
    }
}

struct BitesFeedView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var model = BitesFeedModel()
    @State private var showComposer = false
    @AppStorage(SettingsKey.bitesSwipeToLike) private var swipeToLike = true
    @AppStorage(SettingsKey.bitesShowLikeHints) private var showLikeHints = true

    var body: some View {
        Group {
            if model.loading && model.items.isEmpty {
                BitesSkeletonLoader()
                    .accessibilityLabel("Loading Bandit Feed")
            } else if !model.error.isEmpty && model.items.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t load Bandit Feed", systemImage: "wifi.exclamationmark")
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
                    Section {
                        Button { showComposer = true } label: {
                            HStack(spacing: 12) {
                                ProfileAvatar(
                                    urlString: communications.myAvatarURL,
                                    displayName: communications.myDisplayName.isEmpty ? "You" : communications.myDisplayName,
                                    size: 40,
                                    verified: communications.myVerified,
                                    decorative: true
                                )
                                Text(model.composerDraft.isEmpty ? "What’s on your mind?" : model.composerDraft)
                                    .foregroundStyle(model.composerDraft.isEmpty ? .secondary : .primary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "square.and.pencil")
                                    .foregroundStyle(Brand.goldDeep)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.composerDraft.isEmpty ? "Compose a new Bite" : "Continue Bite draft")
                        .accessibilityHint("Opens the Bite composer")
                    }

                    if model.offlineHint {
                        Text("Showing cached Bites. Pull to refresh when you’re back online.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Showing cached Bites")
                    }

                    if showLikeHints {
                        Text("Swipe up to like a Bite, swipe down to unlike. VoiceOver: use the Actions rotor.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Swipe up to like, swipe down to unlike. VoiceOver users use the Actions rotor.")
                    }

                    ForEach(model.items) { item in
                        BiteRow(
                            item: item,
                            swipeToLikeEnabled: swipeToLike,
                            onLike: { Task { await model.toggleLike(item) } },
                            onReact: { reaction in Task { await model.setReaction(item, reaction: reaction) } },
                            onDeleted: { model.remove(item.id) },
                            onMuteAuthor: { model.muteAuthor(item.author.handle) },
                            onHide: { model.remove(item.id) }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Bandit Feed")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showComposer = true } label: {
                    Label("New Bite", systemImage: "plus.circle.fill")
                }
                .accessibilityHint("Compose a new Bite")
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    BiteBookmarksView()
                } label: {
                    Label("Saved Bites", systemImage: "bookmark")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if UserDefaults.standard.object(forKey: SettingsKey.tipKitEnabled) as? Bool ?? true {
                TipView(SwipeToLikeTip())
                    .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showComposer) {
            NavigationStack {
                BiteComposerView(
                    initialText: model.composerDraft,
                    onDraftChange: { model.saveDraft($0) }
                ) { published in
                    if let published {
                        model.insertOptimistic(published)
                    }
                    model.clearDraft()
                    Task { await model.reload() }
                }
            }
        }
        .task { await model.bootstrap() }
        .refreshable { await model.reload() }
    }
}

// MARK: - Swipe-to-like (UISwipeGestureRecognizer + haptic)

struct BiteSwipeLikeOverlay: UIViewRepresentable {
    var enabled: Bool
    var onSwipeUp: () -> Void
    var onSwipeDown: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        view.isUserInteractionEnabled = enabled
        view.isAccessibilityElement = false
        let up = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.up))
        up.direction = .up
        let down = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.down))
        down.direction = .down
        view.addGestureRecognizer(up)
        view.addGestureRecognizer(down)
        context.coordinator.upRecognizer = up
        context.coordinator.downRecognizer = down
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isUserInteractionEnabled = enabled
        context.coordinator.onSwipeUp = onSwipeUp
        context.coordinator.onSwipeDown = onSwipeDown
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSwipeUp: onSwipeUp, onSwipeDown: onSwipeDown) }

    final class Coordinator: NSObject {
        var onSwipeUp: () -> Void
        var onSwipeDown: () -> Void
        weak var upRecognizer: UISwipeGestureRecognizer?
        weak var downRecognizer: UISwipeGestureRecognizer?
        init(onSwipeUp: @escaping () -> Void, onSwipeDown: @escaping () -> Void) {
            self.onSwipeUp = onSwipeUp
            self.onSwipeDown = onSwipeDown
        }
        @objc func up() { onSwipeUp() }
        @objc func down() { onSwipeDown() }
    }
}

/// Transparent overlay that hosts UISwipeGestureRecognizers. Swipes are discrete and
/// coexist with List pan scrolling; a quick flick up/down likes/unlikes without blocking scroll.
private final class PassthroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { true }
}

struct BiteRow: View {
    let item: BiteItem
    var swipeToLikeEnabled: Bool = true
    var onLike: () -> Void
    var onReact: (String) -> Void = { _ in }
    var onDeleted: () -> Void
    var onMuteAuthor: () -> Void = {}
    var onHide: () -> Void = {}
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var showReport = false
    @State private var reportNote = ""
    @State private var showComments = false
    @State private var showReactions = false
    @State private var openProfile = false
    @State private var likeFlash = false

    var body: some View {
        cardContent
            .padding(.vertical, 6)
            .background(likeFlashBackground)
            .overlay { swipeLikeOverlay }
            .modifier(BiteRowChrome(
                item: item,
                swipeToLikeEnabled: swipeToLikeEnabled,
                onLike: onLike,
                onMuteAuthor: onMuteAuthor,
                onHide: onHide,
                onDeleted: onDeleted,
                showComments: $showComments,
                showReactions: $showReactions,
                showReport: $showReport,
                reportNote: $reportNote,
                openProfile: $openProfile,
                onReact: onReact
            ))
    }

    private var likeFlashBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(likeFlash ? Color.red.opacity(0.12) : Color.clear)
            .animation(.easeOut(duration: 0.25), value: likeFlash)
    }

    @ViewBuilder
    private var swipeLikeOverlay: some View {
        if swipeToLikeEnabled {
            BiteSwipeLikeOverlay(
                enabled: true,
                onSwipeUp: {
                    if !item.liked_by_me {
                        likeFlash = true
                        onLike()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { likeFlash = false }
                    } else {
                        AppHaptics.selection()
                        UIAccessibility.post(notification: .announcement, argument: "Already liked")
                    }
                },
                onSwipeDown: {
                    if item.liked_by_me {
                        onLike()
                    } else {
                        AppHaptics.light()
                        UIAccessibility.post(notification: .announcement, argument: "Not liked")
                    }
                }
            )
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            authorHeader
            if !item.displayText.isEmpty {
                Text(item.displayText)
                    .font(.body)
                    .textSelection(.enabled)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility4)
            }
            mediaHint
            actionBar
        }
    }

    private var authorHeader: some View {
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
                            Text(item.author.display_name)
                                .font(.headline)
                                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
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
            if BitesLocalPrefs.isBookmarked(item.id) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(Brand.goldDeep)
                    .accessibilityLabel("Saved")
            }
        }
    }

    @ViewBuilder
    private var mediaHint: some View {
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
    }

    private var actionBar: some View {
        HStack(spacing: 18) {
            Button(action: onLike) {
                Label("\(item.likes)", systemImage: item.liked_by_me ? "heart.fill" : "heart")
            }
            .accessibilityLabel(item.liked_by_me ? "Unlike, \(item.likes) likes" : "Like, \(item.likes) likes")
            .tint(item.liked_by_me ? .red : .primary)

            Button { showComments = true } label: {
                Label("\(item.comments)", systemImage: "bubble.right")
            }
            .accessibilityLabel("Comments, \(item.comments)")

            Button { showReactions = true } label: {
                Label(item.my_reaction.map { "Reacted \($0)" } ?? "React", systemImage: "face.smiling")
            }
            .accessibilityLabel(item.my_reaction.map { "Change reaction, currently \($0)" } ?? "Add reaction")

            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share Bite")

            Button {
                BitesLocalPrefs.toggleBookmark(item)
                AppHaptics.selection()
                UIAccessibility.post(notification: .announcement, argument: BitesLocalPrefs.isBookmarked(item.id) ? "Saved" : "Removed from saved")
            } label: {
                Image(systemName: BitesLocalPrefs.isBookmarked(item.id) ? "bookmark.fill" : "bookmark")
            }
            .accessibilityLabel(BitesLocalPrefs.isBookmarked(item.id) ? "Remove from saved Bites" : "Save Bite")
        }
        .buttonStyle(.borderless)
        .font(.subheadline)
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


/// Split out of `BiteRow` so the main `body` type-checks under Swift 6 / Xcode 26.
private struct BiteRowChrome: ViewModifier {
    let item: BiteItem
    var swipeToLikeEnabled: Bool
    var onLike: () -> Void
    var onMuteAuthor: () -> Void
    var onHide: () -> Void
    var onDeleted: () -> Void
    @Binding var showComments: Bool
    @Binding var showReactions: Bool
    @Binding var showReport: Bool
    @Binding var reportNote: String
    @Binding var openProfile: Bool
    var onReact: (String) -> Void
    @EnvironmentObject private var communications: ProductionCommunicationsService

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.accessibilitySummary)
            .accessibilityHint(swipeToLikeEnabled ? "Swipe up to like, swipe down to unlike" : "")
            .accessibilityAction(named: Text(item.liked_by_me ? "Unlike" : "Like")) { onLike() }
            .accessibilityAction(named: Text("Open profile")) { openProfile = true }
            .accessibilityAction(named: Text("Comment")) { showComments = true }
            .accessibilityAction(named: Text("Share")) {
                UIAccessibility.post(notification: .announcement, argument: "Use the Share button on this Bite")
            }
            .accessibilityAction(named: Text(BitesLocalPrefs.isBookmarked(item.id) ? "Unsave" : "Save")) {
                BitesLocalPrefs.toggleBookmark(item)
            }
            .accessibilityAction(named: Text("Hide Bite")) { onHide() }
            .accessibilityAction(named: Text("Mute @\(item.author.handle)")) { onMuteAuthor() }
            .contextMenu { contextMenuButtons }
            .sheet(isPresented: $showComments) {
                NavigationStack {
                    BiteDetailView(item: item, onDeleted: onDeleted)
                }
            }
            .confirmationDialog("React", isPresented: $showReactions, titleVisibility: .visible) {
                ForEach(["like", "love", "fire", "laugh", "wow", "sad"], id: \.self) { r in
                    Button(r.capitalized) { onReact(r) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .navigationDestination(isPresented: $openProfile) {
                NativeProfileView(handle: item.author.handle)
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

    @ViewBuilder
    private var contextMenuButtons: some View {
        Button { onLike() } label: {
            Label(item.liked_by_me ? "Unlike" : "Like", systemImage: item.liked_by_me ? "heart.slash" : "heart")
        }
        Button { showReactions = true } label: { Label("React", systemImage: "face.smiling") }
        Button { showComments = true } label: { Label("Comment", systemImage: "bubble.right") }
        Button {
            BitesLocalPrefs.toggleBookmark(item)
        } label: {
            Label(BitesLocalPrefs.isBookmarked(item.id) ? "Unsave" : "Save", systemImage: "bookmark")
        }
        Button { onHide() } label: { Label("Hide this Bite", systemImage: "eye.slash") }
        Button { onMuteAuthor() } label: { Label("Mute @\(item.author.handle)", systemImage: "speaker.slash") }
        Button { showReport = true } label: { Label("Report", systemImage: "flag") }
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
}

struct BiteComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var text: String
    @State private var posting = false
    @State private var error = ""
    var onDraftChange: (String) -> Void
    var onDone: (BiteItem?) -> Void
    private let limit = 4000

    init(initialText: String = "", onDraftChange: @escaping (String) -> Void = { _ in }, onDone: @escaping (BiteItem?) -> Void) {
        _text = State(initialValue: initialText)
        self.onDraftChange = onDraftChange
        self.onDone = onDone
    }

    var body: some View {
        Form {
            Section {
                TextField("What’s happening?", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .accessibilityLabel("Bite text")
                    .banditWritingToolsEnabled()
                    .onChange(of: text) { _, v in onDraftChange(v) }
            } footer: {
                Text("\(text.count) / \(limit)")
                    .accessibilityLabel("\(text.count) of \(limit) characters")
            }
            Section("Creator tools") {
                CreatorAppleToolsStrip(biteText: text)
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
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || posting || text.count > limit)
            }
        }
    }

    private func post() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        posting = true
        defer { posting = false }
        FeatureBehaviors220.beginBitePostLiveActivity(preview: body)
        let optimistic = BitesAPI.makeLocalPost(
            body: body,
            handle: communications.myHandle.isEmpty ? "me" : communications.myHandle,
            displayName: communications.myDisplayName.isEmpty
                ? (communications.myHandle.isEmpty ? "You" : communications.myHandle)
                : communications.myDisplayName,
            avatar: communications.myAvatarURL,
            verified: communications.myVerified
        )
        do {
            _ = try await BitesAPI.publishPost(body: body)
            AppHaptics.success()
            FeatureBehaviors220.finishBitePostLiveActivity(success: true)
            FeatureBehaviors220.onBiteAppeared(id: optimistic.id, author: optimistic.author.handle, body: body)
            onDone(optimistic)
            dismiss()
            UIAccessibility.post(notification: .announcement, argument: "Bite posted")
        } catch {
            self.error = error.localizedDescription
            FeatureBehaviors220.finishBitePostLiveActivity(success: false)
            AppHaptics.error()
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
                BiteRow(item: item, swipeToLikeEnabled: false, onLike: {}, onDeleted: onDeleted)
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
            AppHaptics.success()
            await load()
            UIAccessibility.post(notification: .announcement, argument: "Comment posted")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BiteBookmarksView: View {
    @State private var items: [BiteItem] = []

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("No saved Bites", systemImage: "bookmark", description: Text("Save Bites from the Bandit Feed to find them here."))
            } else {
                ForEach(items) { item in
                    BiteRow(item: item, swipeToLikeEnabled: false, onLike: {}, onDeleted: {
                        BitesLocalPrefs.toggleBookmark(item)
                        items = BitesLocalPrefs.bookmarks()
                    })
                }
            }
        }
        .navigationTitle("Saved Bites")
        .onAppear { items = BitesLocalPrefs.bookmarks() }
    }
}

struct BitesSkeletonLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 96)
                    .redacted(reason: .placeholder)
                    .shimmer(reduceMotion: reduceMotion)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    @ViewBuilder
    func shimmer(reduceMotion: Bool) -> some View {
        if reduceMotion {
            self
        } else {
            self.opacity(0.85)
        }
    }
}

// MARK: - Local feed prefs (bookmarks / mute / hide) — device-side until server ships

enum BitesLocalPrefs {
    private static let bookmarkKey = "bites.bookmarks.v1"
    private static let mutedKey = "bites.mutedAuthors.v1"
    private static let hiddenKey = "bites.hiddenPosts.v1"

    static var mutedAuthors: [String] {
        (UserDefaults.standard.stringArray(forKey: mutedKey) ?? []).map { $0.lowercased() }
    }

    static var hiddenPostIDs: [String] {
        UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []
    }

    static func muteAuthor(_ handle: String) {
        var s = Set(mutedAuthors)
        s.insert(handle.lowercased())
        UserDefaults.standard.set(Array(s), forKey: mutedKey)
    }

    static func hidePost(_ id: String) {
        var s = Set(hiddenPostIDs)
        s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: hiddenKey)
    }

    static func isBookmarked(_ id: String) -> Bool {
        bookmarks().contains { $0.id == id }
    }

    static func toggleBookmark(_ item: BiteItem) {
        var all = bookmarks()
        if let i = all.firstIndex(where: { $0.id == item.id }) {
            all.remove(at: i)
        } else {
            all.insert(item, at: 0)
        }
        if let data = try? JSONEncoder().encode(all.map { BookmarkDTO(from: $0) }) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    static func bookmarks() -> [BiteItem] {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey),
              let dtos = try? JSONDecoder().decode([BookmarkDTO].self, from: data) else { return [] }
        return dtos.map { $0.asItem() }
    }

    struct BookmarkDTO: Codable {
        var id: String
        var body: String
        var handle: String
        var display_name: String
        var avatar_url: String?
        var verified: Bool
        var likes: Int
        var comments: Int
        var created_at: Double
        var liked_by_me: Bool

        init(from item: BiteItem) {
            id = item.id; body = item.displayText; handle = item.author.handle
            display_name = item.author.display_name; avatar_url = item.author.avatar_url
            verified = item.author.verified; likes = item.likes; comments = item.comments
            created_at = item.created_at; liked_by_me = item.liked_by_me
        }

        func asItem() -> BiteItem {
            BiteItem(
                id: id, body: body, caption: nil, media: [], video_url: nil, poster_url: nil,
                created_at: created_at,
                author: BiteAuthor(handle: handle, display_name: display_name, avatar_url: avatar_url, verified: verified),
                likes: likes, comments: comments, liked_by_me: liked_by_me, my_reaction: nil, kind: .post
            )
        }
    }
}
