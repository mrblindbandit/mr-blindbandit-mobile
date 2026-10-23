import SwiftUI

// MARK: - Groups tab

struct GroupsTabView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @EnvironmentObject private var router: TabRouter
    @State private var groups: [BlindbanditGroup] = []
    @State private var loading = true
    @State private var error = ""
    @State private var path: [String] = []
    @State private var creating = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink { PeopleDirectoryView() } label: { Label("People", systemImage: "person.2") }
                        .accessibilityHint("Find people to message or call")
                }
                if !communications.missedGroupCalls.isEmpty {
                    Section("Missed group calls") {
                        ForEach(communications.missedGroupCalls) { call in
                            HStack {
                                Image(systemName: "phone.arrow.down.left").foregroundStyle(.red).accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(call.group_name ?? "Group call")
                                    Text("\(call.from_name) · \(Date(timeIntervalSince1970: call.created_at / 1000), style: .relative) ago")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let gid = call.group_id {
                                    Button("Call back") {
                                        Task { await communications.startGroupCall(groupID: gid, groupName: call.group_name ?? "Group", video: call.isVideo) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Missed \(call.isVideo ? "video" : "voice") call in \(call.group_name ?? "a group") from \(call.from_name)")
                        }
                    }
                }
                Section("Your groups") {
                    if loading && groups.isEmpty {
                        ProgressView("Loading groups").accessibilityLabel("Loading groups")
                    } else if !error.isEmpty {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try again") { Task { await load() } }
                    } else if groups.isEmpty {
                        Text("No groups yet. Tap New group to start one.").foregroundStyle(.secondary)
                    }
                    ForEach(groups) { group in
                        NavigationLink(value: group.id) { GroupRow(group: group) }
                            .accessibilityActions {
                                Button("Voice call") { call(group, video: false) }
                                Button("Video call") { call(group, video: true) }
                            }
                            .contextMenu {
                                Button { call(group, video: false) } label: { Label("Voice call", systemImage: "phone") }
                                Button { call(group, video: true) } label: { Label("Video call", systemImage: "video") }
                            }
                    }
                }
            }
            .navigationTitle("Groups")
            .navigationDestination(for: String.self) { id in GroupChatView(groupID: id, initial: groups.first { $0.id == id }) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus.bubble") }
                        .accessibilityLabel("New group")
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $creating) {
                CreateGroupSheet { group in
                    groups.insert(group, at: 0)
                    path = [group.id]
                }
            }
            .onAppear(perform: consumePending)
            .onChange(of: router.pendingGroupID) { _, _ in consumePending() }
        }
    }

    private func consumePending() {
        guard let id = router.pendingGroupID else { return }
        router.pendingGroupID = nil
        path = [id]
    }

    private func call(_ group: BlindbanditGroup, video: Bool) {
        Task { await communications.startGroupCall(groupID: group.id, groupName: group.name, video: video, memberCount: group.member_count) }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            groups = try await BlindbanditAPI.groups().sorted { ($0.last_message_at ?? $0.updated_at) > ($1.last_message_at ?? $1.updated_at) }
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct GroupAvatar: View {
    let name: String
    var size: CGFloat = 44
    var body: some View {
        let letters = String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
        ZStack {
            Circle().fill(Brand.gold.opacity(0.3))
            if letters.isEmpty { Image(systemName: "person.3.fill") } else { Text(letters).font(.headline) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct GroupRow: View {
    let group: BlindbanditGroup
    var body: some View {
        HStack(spacing: 12) {
            GroupAvatar(name: group.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline)
                Text(group.last_message_body ?? "\(group.member_count) members").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name), \(group.member_count) members\(group.isAdmin ? ", you're an admin" : "")\(group.last_message_body.map { ". Last message: \($0)" } ?? "")")
    }
}

// MARK: - Create

struct CreateGroupSheet: View {
    var onCreate: (BlindbanditGroup) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var picked: [BlindbanditPerson] = []
    @State private var saving = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Group name, like Family", text: $name) }
                Section("Members") {
                    PersonPicker(picked: $picked)
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("New group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Creating…" : "Create") { Task { await create() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty || picked.isEmpty)
                }
            }
        }
    }

    private func create() async {
        saving = true
        defer { saving = false }
        do {
            let group = try await BlindbanditAPI.createGroup(name: name.trimmingCharacters(in: .whitespaces), handles: picked.map(\.handle))
            UIAccessibility.post(notification: .announcement, argument: "Group \(group.name) created")
            onCreate(group)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            UIAccessibility.post(notification: .announcement, argument: self.error)
        }
    }
}

/// Search field plus chosen people, reused by create group and add members.
struct PersonPicker: View {
    @Binding var picked: [BlindbanditPerson]
    var exclude: Set<String> = []
    @State private var query = ""
    @State private var results: [BlindbanditPerson] = []

    var body: some View {
        ForEach(picked) { p in
            HStack {
                Text("\(p.display_name) (@\(p.handle))")
                Spacer()
                Button { picked.removeAll { $0.handle == p.handle } } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Remove \(p.display_name)")
            }
        }
        TextField("Search by name or @handle", text: $query)
            .textInputAutocapitalization(.never)
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard query.count >= 1 else { results = []; return }
                results = ((try? await BlindbanditAPI.directory(query: query, cursor: nil).people) ?? [])
                    .filter { !exclude.contains($0.handle) && !picked.contains($0) }
            }
        ForEach(results.prefix(8)) { p in
            Button { picked.append(p); query = ""; results = []
                UIAccessibility.post(notification: .announcement, argument: "Added \(p.display_name)")
            } label: { Label("\(p.display_name) (@\(p.handle))", systemImage: "plus.circle") }
            .accessibilityLabel("Add \(p.accessibilitySummary)")
        }
    }
}

// MARK: - Group chat

struct GroupChatView: View {
    let groupID: String
    let initial: BlindbanditGroup?
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var group: BlindbanditGroup?
    @State private var members: [BlindbanditGroupMember] = []
    @State private var messages: [BlindbanditGroupMessage] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var error = ""
    @State private var typing: [String] = []
    @State private var lastTypingSent = Date.distantPast
    @State private var showInfo = false
    @State private var showPoll = false
    @State private var aiNote: String?
    @StateObject private var recorder = VoiceRecorder()

    private var title: String { group?.name ?? initial?.name ?? "Group" }
    private var chatRef: ChatRef { .group(id: groupID) }
    private var recentLines: [String] { messages.suffix(30).map { "\($0.sender_name): \($0.body)" } }
    private func isVerified(_ handle: String) -> Bool { members.first { $0.handle.lowercased() == handle.lowercased() }?.verified == true }

    var body: some View {
        ChatLockGate(chatKey: chatRef.key) { groupBody }
    }

    private var groupBody: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    if loading && messages.isEmpty { ProgressView("Loading messages") }
                    if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
                    if !loading && messages.isEmpty && error.isEmpty { Text("No messages yet. Say hi.").foregroundStyle(.secondary) }
                    ForEach(messages) { m in
                        let mine = m.sender_handle.lowercased() == communications.myHandle.lowercased()
                        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                                if !mine { HStack(spacing: 3) { Text(m.sender_name).font(.caption.bold()); if isVerified(m.sender_handle) { VerifiedBadge() } } }
                                if let media = m.decrypted?.media, media.mime.hasPrefix("audio") {
                                    VoiceBubble(media: media, from: mine ? "You" : m.sender_name, msgID: m.id)
                                } else if let poll = m.decrypted?.poll {
                                    PollCard(poll: poll, msgID: m.id, chat: chatRef, handle: "", me: communications.myHandle)
                                } else {
                                Text(m.body).padding(10)
                                    .background(mine ? Brand.gold.opacity(0.35) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                                }
                            }
                            .accessibilityElement(children: m.decrypted?.poll != nil || m.decrypted?.media != nil ? .contain : .ignore)
                            .accessibilityLabel("\(mine ? "You" : m.sender_name)\(isVerified(m.sender_handle) && !mine ? ", Verified" : ""): \(m.body)")
                            .accessibilityActions {
                                Button("Copy") { UIPasteboard.general.string = m.body }
                                Button("Read aloud") { MessageReader.shared.speak(m.body) }
                            }
                            .contextMenu {
                                Button { UIPasteboard.general.string = m.body } label: { Label("Copy", systemImage: "doc.on.doc") }
                                Button { MessageReader.shared.speak(m.body) } label: { Label("Read aloud", systemImage: "speaker.wave.2") }
                            }
                            MessageStatusCaption(text: mine ? MessageStatus.groupCaption(for: m) : MessageStatus.stamp(m.created_at), mine: mine)
                        }
                        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
                        .listRowSeparator(.hidden)
                        .id(m.id)
                        .accessibilityElement(children: .contain)
                    }
                    if let first = typing.first {
                        TypingIndicatorBubble(name: typing.count > 1 ? "\(typing.count) people" : "@\(first)")
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .onChange(of: messages.count) { _, _ in if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            if let n = aiNote {
                HStack(alignment: .top) {
                    Text(n).font(.callout)
                    Spacer()
                    Button { aiNote = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Dismiss AI note")
                }.padding(.horizontal)
            }
            HStack {
                TextField("Message \(title)", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draft) { _, _ in pingTyping() }
                    .accessibilityActions {
                        Button(recorder.isRecording ? "Send voice message" : "Record voice message") {
                            Task { await recorder.toggleSend(handle: "", chat: chatRef, comms: communications); await refresh() }
                        }
                        Button("Create poll") { showPoll = true }
                        Button("Catch me up") { Task { await catchUp() } }
                        Button("Ask AI in this group") { draft = "@AI " + draft }
                        Button("Ask AI privately") { draft = "/ai " + draft }
                        Button("Insert emoji") { draft += "🙂" }
                        Button("Group settings") { showInfo = true }
                    }
                VoiceMicButton(handle: "", chat: chatRef, recorder: recorder)
                Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .accessibilityLabel("Send")
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { call(video: true) } label: { Image(systemName: "video") }
                    .accessibilityLabel("Video call \(title)")
                Button { call(video: false) } label: { Image(systemName: "phone") }
                    .accessibilityLabel("Voice call \(title)")
            }
            ToolbarItem(placement: .principal) {
                Button { showInfo = true } label: { Text(title).font(.headline).lineLimit(1) }
                    .accessibilityLabel("\(title), chat settings")
                    .accessibilityHint("Double tap to open chat info and settings")
            }
        }
        .sheet(isPresented: $showPoll) { PollComposerSheet(chat: chatRef, handle: "") }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                GroupInfoView(groupID: groupID, group: $group, members: $members)
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Menu("Folders, lock and more") {
                                FolderAssignMenu(chatKey: chatRef.key)
                                Button(ChatLock.isLocked(chatRef.key) ? "Unlock chat (remove Face ID)" : "Lock chat with Face ID") { ChatLock.set(chatRef.key, !ChatLock.isLocked(chatRef.key)) }
                                Button("Create poll") { showInfo = false; showPoll = true }
                                Button("Catch me up") { showInfo = false; Task { await catchUp() } }
                            }
                        }
                    }
            }
        }
        .task { await poll() }
    }

    private func call(video: Bool) {
        Task { await communications.startGroupCall(groupID: groupID, groupName: title, video: video, memberCount: group?.member_count ?? members.count) }
    }

    private func pingTyping() {
        guard Date().timeIntervalSince(lastTypingSent) > 4, !draft.isEmpty else { return }
        lastTypingSent = Date()
        Task { updateTyping(await BlindbanditAPI.sendGroupTyping(id: groupID)) }
    }

    private func catchUp() async {
        aiNote = "Summarizing…"
        aiNote = await OnDeviceAI.catchUp(chatName: title, lines: recentLines) ?? OnDeviceAI.unavailableReason
        UIAccessibility.post(notification: .announcement, argument: aiNote ?? "")
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        if let r = AIAssistant.parse(text) {
            guard AIAssistant.allowed(chatKey: chatRef.key) else { UIAccessibility.post(notification: .announcement, argument: "@AI is turned off in this chat"); return }
            aiNote = "AI is thinking…"
            let answer = await AIAssistant.answer(r, context: .init(chatName: title, lines: recentLines, lastPhoto: nil)) { p in aiNote = p }
            if r.isPrivate {
                aiNote = "Only you can see this: " + answer
                UIAccessibility.post(notification: .announcement, argument: "AI, only you can see this: \(answer)")
            } else {
                aiNote = nil
                let p = E2EEPayload(t: "ai", body: answer, ai_via: communications.myHandle)
                if (try? await E2EEService.shared.sendGroup(id: groupID, payload: p)) != true {
                    try? await BlindbanditAPI.sendGroupMessage(id: groupID, body: "🤖 AI (via @\(communications.myHandle)): " + answer)
                }
                UIAccessibility.post(notification: .announcement, argument: "AI via you: \(answer)")
                await refresh()
            }
            return
        }
        do {
            try await BlindbanditAPI.sendGroupMessage(id: groupID, body: text)
            UIAccessibility.post(notification: .announcement, argument: "Sent")
            await refresh()
        } catch {
            draft = text
            self.error = error.localizedDescription
            UIAccessibility.post(notification: .announcement, argument: "Not sent. \(self.error)")
        }
    }

    /// Shows the typing bubble and announces anyone who just started typing (never me).
    private func updateTyping(_ handles: [String]) {
        let me = communications.myHandle.lowercased()
        let others = handles.map(BlindbanditHandle.normalize).filter { !$0.isEmpty && $0.lowercased() != me }
        let started = others.filter { !typing.contains($0) }
        typing = others
        if !started.isEmpty {
            let who = started.count > 1 ? "\(started.count) people are" : "@\(started[0]) is"
            UIAccessibility.post(notification: .announcement, argument: "\(who) typing")
        }
    }

    private func refresh() async {
        do {
            let fresh = try await BlindbanditAPI.groupMessages(id: groupID)
            let mineLower = communications.myHandle.lowercased()
            if !messages.isEmpty, let newest = fresh.last, newest.id != messages.last?.id, newest.sender_handle.lowercased() != mineLower {
                UIAccessibility.post(notification: .announcement, argument: "\(newest.sender_name): \(newest.body)")
            }
            messages = fresh
            error = ""
            await BlindbanditAPI.markGroupRead(id: groupID)
            updateTyping(await BlindbanditAPI.groupTyping(id: groupID))
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func poll() async {
        if let detail = try? await BlindbanditAPI.groupDetail(id: groupID) {
            group = detail.group
            members = detail.members
        }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
    }
}

// MARK: - Group info and admin

struct GroupInfoView: View {
    let groupID: String
    @Binding var group: BlindbanditGroup?
    @Binding var members: [BlindbanditGroupMember]
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var adding: [BlindbanditPerson] = []
    @State private var message = ""
    @State private var confirmLeave = false
    @State private var confirmDelete = false

    private var isAdmin: Bool { group?.isAdmin ?? false }

    var body: some View {
        NavigationStack {
            Form {
                if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
                if isAdmin {
                    Section("Group name") {
                        TextField("Name", text: $newName)
                        Button("Save name") { run("Renamed") { try await BlindbanditAPI.renameGroup(id: groupID, name: newName); group?.name = newName } }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("\(members.count) members") {
                    ForEach(members) { m in
                        HStack {
                            VStack(alignment: .leading) {
                                HStack(spacing: 3) { Text(m.display_name); if m.verified { VerifiedBadge() } }
                                Text("@\(m.handle)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if m.isAdmin { Text(m.role.capitalized).font(.caption.bold()).foregroundStyle(Brand.goldDeep) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityActions { memberActions(m) }
                        .contextMenu { memberActions(m) }
                    }
                }
                if isAdmin {
                    Section("Add people") {
                        PersonPicker(picked: $adding, exclude: Set(members.map(\.handle)))
                        Button("Add \(adding.count)") {
                            run("Added") { try await BlindbanditAPI.addGroupMembers(id: groupID, handles: adding.map(\.handle)); adding = []; await reload() }
                        }
                        .disabled(adding.isEmpty)
                    }
                }
                Section {
                    Button("Leave group", role: .destructive) { confirmLeave = true }
                    if isAdmin { Button("Delete group for everyone", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(group?.name ?? "Group")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { newName = group?.name ?? "" }
            .confirmationDialog("Leave this group?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) { run("You left the group") { try await BlindbanditAPI.leaveGroup(id: groupID, myHandle: communications.myHandle); dismiss() } }
            }
            .confirmationDialog("Delete this group for everyone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { run("Group deleted") { try await BlindbanditAPI.deleteGroup(id: groupID); dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func memberActions(_ m: BlindbanditGroupMember) -> some View {
        if isAdmin && m.handle.lowercased() != communications.myHandle.lowercased() {
            Button(m.isAdmin ? "Remove admin" : "Make admin") {
                run(m.isAdmin ? "No longer an admin" : "Now an admin") {
                    try await BlindbanditAPI.setGroupRole(id: groupID, handle: m.handle, role: m.isAdmin ? "member" : "admin"); await reload()
                }
            }
            Button("Remove from group", role: .destructive) {
                run("Removed \(m.display_name)") { try await BlindbanditAPI.removeGroupMember(id: groupID, handle: m.handle); await reload() }
            }
        }
    }

    private func reload() async {
        if let detail = try? await BlindbanditAPI.groupDetail(id: groupID) { group = detail.group; members = detail.members }
    }

    private func run(_ success: String, _ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); message = success }
            catch { message = error.localizedDescription }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}

// MARK: - People directory

struct PeopleDirectoryView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var router: TabRouter
    @State private var query = ""
    @State private var people: [BlindbanditPerson] = []
    @State private var next: String?
    @State private var loading = false
    @State private var error = ""

    var body: some View {
        List {
            if loading && people.isEmpty { ProgressView("Loading people") }
            if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
            if !loading && people.isEmpty && error.isEmpty { Text(query.isEmpty ? "No one here yet." : "No one matches \(query).").foregroundStyle(.secondary) }
            ForEach(people) { p in
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 3) { Text(p.display_name).font(.headline); if p.verified == true { VerifiedBadge() } }
                        Text("@\(p.handle)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { message(p) } label: { Image(systemName: "message") }.buttonStyle(.borderless)
                    Button { call(p, video: false) } label: { Image(systemName: "phone") }.buttonStyle(.borderless)
                    Button { call(p, video: true) } label: { Image(systemName: "video") }.buttonStyle(.borderless)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(p.accessibilitySummary)
                .accessibilityActions {
                    Button("Message") { message(p) }
                    Button("Call") { call(p, video: false) }
                    Button("Video call") { call(p, video: true) }
                }
                .contextMenu {
                    Button { message(p) } label: { Label("Message", systemImage: "message") }
                    Button { call(p, video: false) } label: { Label("Call", systemImage: "phone") }
                    Button { call(p, video: true) } label: { Label("Video call", systemImage: "video") }
                }
            }
            if let next, !loading {
                Button("Load more") { Task { await load(cursor: next) } }
            }
        }
        .navigationTitle("People")
        .searchable(text: $query, prompt: "Name or @handle")
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await load(cursor: nil)
        }
        .refreshable { await load(cursor: nil) }
    }

    private func load(cursor: String?) async {
        loading = true
        defer { loading = false }
        do {
            let page = try await BlindbanditAPI.directory(query: query, cursor: cursor)
            people = cursor == nil ? page.people : people + page.people
            next = page.next
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func message(_ p: BlindbanditPerson) {
        router.pendingThread = TabRouter.ThreadTarget(id: nil, handle: p.handle)
        router.selection = .messages
    }

    private func call(_ p: BlindbanditPerson, video: Bool) {
        Task {
            guard await CommsPermissions.microphone(privacy, communications) else { return }
            if video { _ = await CommsPermissions.camera(privacy, communications) }
            await communications.startCall(recipient: p.handle, video: video)
        }
    }
}
