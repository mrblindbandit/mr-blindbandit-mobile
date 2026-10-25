import SwiftUI

// MARK: - Follow / Unfollow (optimistic)

struct FollowButton: View {
    let handle: String
    @Binding var isFollowing: Bool
    var onChange: ((Bool) -> Void)? = nil
    @State private var busy = false

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isFollowing ? Color.secondary.opacity(0.2) : Brand.gold)
                .foregroundStyle(isFollowing ? Color.primary : Color.black)
                .clipShape(Capsule())
        }
        .disabled(busy || handle.isEmpty)
        .accessibilityLabel(isFollowing ? "Unfollow \(handle)" : "Follow \(handle)")
        .accessibilityHint(isFollowing ? "Stops following this profile" : "Follows this profile")
    }

    private func toggle() async {
        let previous = isFollowing
        isFollowing = !previous
        onChange?(!previous)
        busy = true
        defer { busy = false }
        do {
            if previous { try await BitesAPI.unfollow(handle: handle) }
            else { try await BitesAPI.follow(handle: handle) }
            UIAccessibility.post(notification: .announcement, argument: previous ? "Unfollowed" : "Following")
        } catch {
            isFollowing = previous
            onChange?(previous)
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }
}

// MARK: - Native profile (not WKWebView)

struct NativeProfileView: View {
    let handle: String
    var isMe: Bool = false

    @EnvironmentObject private var communications: ProductionCommunicationsService
    @EnvironmentObject private var router: TabRouter
    @State private var profile: SocialProfileFull?
    @State private var posts: [BiteItem] = []
    @State private var loading = false
    @State private var error = ""
    @State private var isFollowing = false

    private var resolvedHandle: String {
        let h = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespaces))
        if isMe || h.isEmpty { return communications.myHandle }
        return h
    }

    var body: some View {
        List {
            if let profile {
                Section {
                    profileHeader(profile)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                Section {
                    NavigationLink {
                        FollowListView(handle: profile.handle, mode: .followers)
                    } label: {
                        LabeledContent("Followers", value: "\(profile.followers)")
                    }
                    .accessibilityLabel("Followers, \(profile.followers)")

                    NavigationLink {
                        FollowListView(handle: profile.handle, mode: .following)
                    } label: {
                        LabeledContent("Following", value: "\(profile.following)")
                    }
                    .accessibilityLabel("Following, \(profile.following)")

                    LabeledContent("Bites", value: "\(max(profile.bites, profile.posts))")
                        .accessibilityLabel("Bites, \(max(profile.bites, profile.posts))")
                }

                if !isOwnProfile(profile) {
                    Section {
                        HStack(spacing: 12) {
                            FollowButton(handle: profile.handle, isFollowing: $isFollowing) { following in
                                guard var p = self.profile else { return }
                                p.is_following = following
                                p.followers = max(0, p.followers + (following ? 1 : -1))
                                self.profile = p
                            }
                            Button {
                                router.pendingThread = TabRouter.ThreadTarget(id: nil, handle: profile.handle)
                                router.selection = .messages
                            } label: {
                                Label("Message", systemImage: "message.fill")
                            }
                            .buttonStyle(.bordered)
                            Button {
                                Task {
                                    await communications.startCall(recipient: profile.handle, video: false)
                                }
                            } label: {
                                Label("Call", systemImage: "phone.fill")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Start a voice call with @\(profile.handle)")
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Section("Your account") {
                        NavigationLink("Edit display name") { DisplayNameEditor() }
                        NavigationLink("Edit profile picture") { ProfilePictureEditor() }
                        NavigationLink("Edit username") { UsernameEditor().navigationTitle("Username") }
                        NavigationLink("Settings") { Settings() }
                        if AdminGate.isAdmin(handle: communications.myHandle, profileID: communications.myProfileID) {
                            NavigationLink {
                                AdminPanelView()
                            } label: {
                                Label("Admin", systemImage: "shield.checkered")
                            }
                            .accessibilityHint("Owner tools: verify people, moderate Bites, review reports")
                        }
                    }
                }

                Section("Bites") {
                    if posts.isEmpty && !loading {
                        Text("No Bites yet.").foregroundStyle(.secondary)
                    }
                    ForEach(posts) { item in
                        BiteRow(item: item, onLike: {
                            Task {
                                if let idx = posts.firstIndex(where: { $0.id == item.id }) {
                                    let was = posts[idx].liked_by_me
                                    posts[idx].liked_by_me.toggle()
                                    posts[idx].likes = max(0, posts[idx].likes + (was ? -1 : 1))
                                    do {
                                        if was { try await BitesAPI.unlike(postID: item.id) }
                                        else { try await BitesAPI.like(postID: item.id) }
                                    } catch {
                                        posts[idx].liked_by_me = was
                                        posts[idx].likes = max(0, posts[idx].likes + (was ? 1 : -1))
                                    }
                                }
                            }
                        }, onDeleted: {
                            posts.removeAll { $0.id == item.id }
                        })
                    }
                }
            } else if loading {
                Section { HStack { ProgressView(); Text("Loading profile") } }
            } else if !error.isEmpty {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await load(force: true) } }
                }
            }
        }
        .navigationTitle(profile.map { "@\($0.handle)" } ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: resolvedHandle) { await load(force: false) }
        .refreshable { await load(force: true) }
    }

    @ViewBuilder
    private func profileHeader(_ p: SocialProfileFull) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ProfileAvatar(
                    urlString: absoluteAvatar(p.avatar_url),
                    displayName: p.display_name,
                    size: 72,
                    verified: p.verified,
                    decorative: true
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(p.display_name).font(.title2.weight(.bold))
                        if p.verified { VerifiedBadge() }
                    }
                    Text("@\(p.handle)").foregroundStyle(.secondary)
                    if p.is_artist {
                        Text("Artist").font(.caption).foregroundStyle(Brand.gold)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(p.accessibilitySummary)

            if let bio = p.bio, !bio.isEmpty {
                Text(bio).font(.body)
            }
            if let loc = p.location, !loc.isEmpty {
                Label(loc, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
            }
            if let web = p.website, !web.isEmpty, let url = URL(string: web) {
                Link(destination: url) {
                    Label(web, systemImage: "link")
                }
                .font(.subheadline)
            }
        }
    }

    private func isOwnProfile(_ p: SocialProfileFull) -> Bool {
        isMe || p.handle.lowercased() == communications.myHandle.lowercased()
            || p.id == communications.myProfileID
    }

    private func absoluteAvatar(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("https://") { return raw }
        return BlindbanditAPI.resolveURL(raw)?.absoluteString
    }

    private func load(force: Bool) async {
        let h = resolvedHandle
        guard !h.isEmpty else {
            error = "Set a Blindbandit username to open your profile."
            return
        }
        if !force, let cached = BitesAPI.cachedProfile(handle: h) {
            profile = cached
            isFollowing = cached.is_following
        } else {
            loading = profile == nil
        }
        defer { loading = false }
        do {
            let full = try await BitesAPI.profileFull(handle: h)
            profile = full
            isFollowing = full.is_following
            posts = (try? await BitesAPI.profilePosts(handle: h)) ?? []
            error = ""
        } catch {
            if profile == nil { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Followers / Following lists

struct FollowListView: View {
    enum Mode { case followers, following }
    let handle: String
    let mode: Mode
    @State private var people: [BiteAuthor] = []
    @State private var loading = true
    @State private var error = ""

    var body: some View {
        List {
            if loading && people.isEmpty {
                ProgressView(mode == .followers ? "Loading followers" : "Loading following")
            } else if !error.isEmpty && people.isEmpty {
                Text(error).foregroundStyle(.secondary)
                Button("Retry") { Task { await load() } }
            } else if people.isEmpty {
                Text(mode == .followers ? "No followers yet." : "Not following anyone yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(people) { p in
                NavigationLink {
                    NativeProfileView(handle: p.handle)
                } label: {
                    HStack(spacing: 12) {
                        ProfileAvatar(urlString: p.avatar_url, displayName: p.display_name, size: 40, verified: p.verified, decorative: true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(p.display_name).font(.headline)
                                if p.verified { VerifiedBadge() }
                            }
                            Text("@\(p.handle)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityLabel(p.verified ? "\(p.display_name), Verified, @\(p.handle)" : "\(p.display_name), @\(p.handle)")
            }
        }
        .navigationTitle(mode == .followers ? "Followers" : "Following")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            people = mode == .followers
                ? try await BitesAPI.followers(handle: handle)
                : try await BitesAPI.following(handle: handle)
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Profile tab root: my native profile + settings entry.
struct ProfileTabView: View {
    var body: some View {
        NavigationStack {
            NativeProfileView(handle: "", isMe: true)
                .navigationTitle("Profile")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}
