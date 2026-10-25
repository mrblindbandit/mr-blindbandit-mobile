package net.mrblindbandit.app.connect

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.SemanticsPropertyReceiver
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import net.mrblindbandit.app.safety.ContentFilter

private sealed interface MessagesRoute {
    data object List : MessagesRoute
    data object Notifications : MessagesRoute
    data object Groups : MessagesRoute
    data object Blocked : MessagesRoute
}

/**
 * Messages tab: conversation list, thread, new message, notification center and blocked accounts.
 * [pendingThread] opens a specific conversation (from a push or notification deep link).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessagesTab(
    communications: ProductionCommunicationsService,
    haptics: Haptics,
    signedIn: Boolean,
    pendingThread: String?,
    onPendingThreadHandled: () -> Unit,
    onCall: (handle: String, video: Boolean) -> Unit,
    onDestination: (CommsDestination) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var route by remember { mutableStateOf<MessagesRoute>(MessagesRoute.List) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    // Keep the list and badge fresh while the app is in the foreground.
    LaunchedEffect(signedIn) {
        if (!signedIn) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                communications.flushPendingMessages()
                if (communications.openConversationId == null) communications.refreshConversations()
                delay(15_000)
            }
        }
    }
    LaunchedEffect(pendingThread) {
        pendingThread?.let { id ->
            route = MessagesRoute.List
            communications.openConversation(id)
            onPendingThreadHandled()
        }
    }

    if (!signedIn) {
        CenteredText("Sign in from the Home tab to send and receive messages.")
        return
    }

    communications.openGroupId?.let { GroupThreadScreen(communications, it); return }
    val openId = communications.openConversationId
    if (openId != null) {
        ThreadScreen(communications, openId, haptics, onCall)
        return
    }
    when (route) {
        MessagesRoute.Notifications -> { NotificationCenter(communications, haptics, onBack = { route = MessagesRoute.List }, onOpen = { d -> route = MessagesRoute.List; onDestination(d) }); return }
        MessagesRoute.Blocked -> { BlockedAccountsScreen(communications, haptics, onBack = { route = MessagesRoute.List }); return }
        MessagesRoute.Groups -> { GroupsScreen(communications) { route = MessagesRoute.List }; return }
        MessagesRoute.List -> Unit
    }

    var query by remember { mutableStateOf("") }
    var searching by remember { mutableStateOf(false) }
    var composing by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var refreshing by remember { mutableStateOf(false) }
    val filter = ContentFilter.isEnabled(context)

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Messages", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f).semantics { heading() })
            IconButton(onClick = { haptics.tap(); searching = !searching; if (!searching) query = "" }) {
                Icon(Icons.Default.Search, contentDescription = if (searching) "Close search" else "Search conversations")
            }
            IconButton(onClick = { haptics.tap(); route = MessagesRoute.Notifications }) {
                Icon(Icons.Default.Notifications, contentDescription = "Notifications")
            }
            IconButton(onClick = { haptics.tap(); composing = true }) {
                Icon(Icons.Default.Edit, contentDescription = "New message")
            }
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, contentDescription = "More message options") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Groups") }, onClick = { menu = false; route = MessagesRoute.Groups })
                    DropdownMenuItem(text = { Text("Blocked accounts") }, onClick = { menu = false; route = MessagesRoute.Blocked })
                }
            }
        }
        if (searching) {
            OutlinedTextField(
                value = query, onValueChange = { query = it }, singleLine = true,
                label = { Text("Search by name, username or message") },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            )
        }
        if (communications.pendingMessages.isNotEmpty()) {
            Surface(color = MaterialTheme.colorScheme.secondaryContainer, modifier = Modifier.fillMaxWidth().padding(16.dp, 8.dp), shape = RoundedCornerShape(12.dp)) {
                Column(Modifier.padding(12.dp)) {
                    val n = communications.pendingMessages.size
                    Text("$n message${if (n == 1) "" else "s"} waiting to send", fontWeight = FontWeight.SemiBold)
                    communications.pendingMessages.forEach { p ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("To @${p.handle}: ${ContentFilter.display(p.body, filter)}", Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            TextButton(onClick = { communications.discardPending(p) }) { Text("Discard", Modifier.semantics { contentDescription = "Discard queued message to ${p.handle}" }) }
                        }
                    }
                    TextButton(onClick = { scope.launch { communications.flushPendingMessages() } }) { Text("Send now") }
                }
            }
        }

        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { scope.launch { refreshing = true; communications.refreshConversations(); refreshing = false } },
            modifier = Modifier.weight(1f).fillMaxWidth(),
        ) {
            val state = communications.conversationsState
            val q = query.trim().lowercase()
            val rows = communications.conversations
                .filter { q.isEmpty() || it.peerName.lowercase().contains(q) || it.peerHandle.lowercase().contains(q) || it.lastBody.lowercase().contains(q) }
                .sortedWith(compareByDescending<ServerConversation> { it.id in communications.pinned }.thenByDescending { it.lastCreatedAt })
            when {
                state is LoadState.Failed && communications.conversations.isEmpty() ->
                    LazyColumn(Modifier.fillMaxSize()) { item { ErrorRetry(state.message, { scope.launch { communications.refreshConversations() } }) } }
                (state is LoadState.Loading || state is LoadState.Idle) && communications.conversations.isEmpty() ->
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading conversations" })
                    }
                rows.isEmpty() ->
                    LazyColumn(Modifier.fillMaxSize()) { item { CenteredText(if (q.isEmpty()) "No conversations yet. Tap New message to start one." else "No conversations match \"$query\".") } }
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    items(rows, key = { it.id }) { c ->
                        ConversationRow(c, communications, filter, haptics) { scope.launch { haptics.tap(); communications.openConversation(c.id) } }
                        HorizontalDivider()
                    }
                }
            }
        }
    }

    if (composing) NewMessageDialog(communications, haptics, onDismiss = { composing = false })
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ConversationRow(c: ServerConversation, communications: ProductionCommunicationsService, filter: Boolean, haptics: Haptics, onOpen: () -> Unit) {
    val unread = communications.isUnread(c)
    val pinned = c.id in communications.pinned
    val muted = c.id in communications.muted
    var menu by remember { mutableStateOf(false) }
    val preview = ContentFilter.display(c.lastBody, filter).ifBlank { "No messages yet" }
    val fromMe = c.lastSenderId.isNotBlank() && c.lastSenderId == communications.myProfileId
    val description = buildString {
        append(c.peerName)
        if (c.verified) append(", verified")
        if (unread) append(if (c.unreadCount > 1) ", ${c.unreadCount} unread" else ", unread")
        if (pinned) append(", pinned")
        if (muted) append(", muted")
        append(". ")
        if (fromMe) append("You: ")
        append(preview)
        timeLabel(c.lastCreatedAt).takeIf { it.isNotBlank() }?.let { append(". $it") }
    }
    val pinLabel = if (pinned) "Unpin" else "Pin"
    val muteLabel = if (muted) "Unmute" else "Mute"
    val unreadLabel = if (unread) "Mark read" else "Mark unread"
    val togglePin = { haptics.tap(); communications.togglePinned(c.id); true }
    val toggleMute = { haptics.tap(); communications.toggleMuted(c.id); true }
    val scope = rememberCoroutineScope()
    val toggleUnread = { haptics.tap(); if (unread) scope.launch { communications.markRead(c.id) } else communications.markUnread(c.id); true }
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 72.dp)
                .combinedClickable(onClickLabel = "Open conversation", onClick = onOpen, onLongClickLabel = "Conversation options", onLongClick = { menu = true })
                .clearAndSetSemantics {
                    contentDescription = description
                    customActions = listOf(
                        CustomAccessibilityAction(pinLabel) { togglePin() },
                        CustomAccessibilityAction(muteLabel) { toggleMute() },
                        CustomAccessibilityAction(unreadLabel) { toggleUnread() },
                    )
                    onClickHelper(onOpen)
                }
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(10.dp).background(if (unread) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Transparent, CircleShape))
            Spacer(Modifier.size(10.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(c.peerName, fontWeight = if (unread) FontWeight.Bold else FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (pinned) Icon(Icons.Default.PushPin, null, Modifier.size(16.dp).padding(start = 4.dp))
                    if (muted) Icon(Icons.Default.VolumeOff, null, Modifier.size(16.dp).padding(start = 4.dp))
                    Spacer(Modifier.weight(1f))
                    Text(timeLabel(c.lastCreatedAt), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text((if (fromMe) "You: " else "") + preview, maxLines = 2, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(pinLabel) }, onClick = { menu = false; togglePin() })
            DropdownMenuItem(text = { Text(muteLabel) }, onClick = { menu = false; toggleMute() })
            DropdownMenuItem(text = { Text(unreadLabel) }, onClick = { menu = false; toggleUnread() })
        }
    }
}

private fun SemanticsPropertyReceiver.onClickHelper(action: () -> Unit) {
    onClick(label = "Open conversation") { action(); true }
}

@Composable
private fun NewMessageDialog(communications: ProductionCommunicationsService, haptics: Haptics, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var handle by remember { mutableStateOf("") }
    var findingPerson by remember { mutableStateOf(false) }
    var body by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    if (findingPerson) { PeoplePicker(communications, { handle = it; findingPerson = false }, { findingPerson = false }); return }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New message") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(handle, { handle = it; error = "" }, label = { Text("To (@username)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                TextButton(enabled = !busy, onClick = { findingPerson = true }) { Text("Find a person") }
                OutlinedTextField(body, { body = it.take(4000) }, label = { Text("Message") }, minLines = 3, modifier = Modifier.fillMaxWidth())
                if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive })
            }
        },
        confirmButton = {
            TextButton(enabled = !busy && handle.isNotBlank() && body.isNotBlank(), onClick = {
                busy = true
                scope.launch {
                    if (!communications.checkHandle(handle)) {
                        error = communications.statusMessage.ifBlank { "That username was not found." }
                        busy = false
                        return@launch
                    }
                    val id = communications.sendMessage(handle, body)
                    busy = false
                    haptics.success()
                    onDismiss()
                    if (id != null) communications.openConversation(id)
                }
            }) { Text(if (busy) "Sending…" else "Send") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ThreadScreen(communications: ProductionCommunicationsService, conversationId: String, haptics: Haptics, onCall: (String, Boolean) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val filter = ContentFilter.isEnabled(context)
    val readAloud = rememberReadAloud()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val convo = communications.conversations.firstOrNull { it.id == conversationId }
    val peerName = convo?.peerName ?: "Conversation"
    val peerHandle = convo?.peerHandle.orEmpty()
    var draft by remember(conversationId) { mutableStateOf(communications.local.draft(conversationId)) }
    var replyTo by remember { mutableStateOf<ServerMessage?>(null) }
    var menu by remember { mutableStateOf(false) }
    var report by remember { mutableStateOf<ReportTarget?>(null) }
    var blocking by remember { mutableStateOf(false) }
    var speedDialog by remember { mutableStateOf(false) }
    var findText by remember { mutableStateOf("") }
    var finding by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    readAloud.rate = communications.local.readAloudRate

    BackHandler { communications.closeConversation() }

    // 5-second refresh while this thread is on screen and the app is in the foreground.
    LaunchedEffect(conversationId) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                delay(5_000)
                val fresh = communications.reloadThread(conversationId)
                fresh.forEach { m -> Announcer.announce(context, "$peerName: ${ContentFilter.display(m.body, filter)}") }
            }
        }
    }
    val mine = communications.messages.filter { it.senderId == communications.myProfileId }
    val lastReceipt = mine.lastOrNull()?.receipt
    LaunchedEffect(lastReceipt) {
        if (lastReceipt == Receipt.READ || lastReceipt == Receipt.DELIVERED) Announcer.announce(context, "Your last message: ${lastReceipt.label}")
    }
    // Scroll only when the tail identity changes to a new message — not on poll/receipt reconcile.
    val tailKey = communications.messages.lastOrNull()?.let { "${it.id}:${it.body.hashCode()}" }
    LaunchedEffect(tailKey) {
        val last = communications.messages.lastOrNull() ?: return@LaunchedEffect
        if (last.id.startsWith("local-") || communications.messages.isNotEmpty()) {
            listState.animateScrollToItem(communications.messages.size - 1)
        }
    }

    fun send() {
        val text = draft.trim()
        if (text.isBlank() || sending) return
        val quoted = replyTo?.let { r -> r.body.lines().take(3).joinToString("\n") { "> $it" } + "\n" }.orEmpty()
        // Clear draft + unlock Send immediately; network runs after optimistic Sent (TF 39).
        val payload = quoted + text
        draft = ""; replyTo = null
        communications.local.setDraft(conversationId, "")
        sending = true
        haptics.success()
        scope.launch {
            communications.sendMessage(peerHandle.ifBlank { convo?.peerName.orEmpty() }, payload, conversationId)
            sending = false
        }
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { haptics.tap(); communications.closeConversation() }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back to conversations")
            }
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { heading() }) {
                Text(peerName, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (peerHandle.isNotBlank()) Text("@$peerHandle", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(enabled = peerHandle.isNotBlank(), onClick = { haptics.tap(); onCall(peerHandle, false) }) {
                Icon(Icons.Default.Call, contentDescription = "Voice call $peerName")
            }
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, contentDescription = "Conversation options") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Video call") }, enabled = peerHandle.isNotBlank(), onClick = { menu = false; onCall(peerHandle, true) })
                    DropdownMenuItem(text = { Text("Verify encryption safety number") }, onClick = {
                        menu = false
                        scope.launch {
                            try { val number = communications.encryption?.safetyNumber(peerHandle) ?: error("Encryption is not ready"); communications.statusMessage = "Compare this number with @$peerHandle in person or through a trusted channel: $number"; Announcer.announce(context, communications.statusMessage) }
                            catch (e: Exception) { communications.statusMessage = e.localizedMessage.orEmpty(); Announcer.announce(context, communications.statusMessage) }
                        }
                    })
                    DropdownMenuItem(text = { Text("Search in conversation") }, onClick = { menu = false; finding = true })
                    DropdownMenuItem(text = { Text("Read whole conversation aloud") }, onClick = {
                        menu = false
                        readAloud.speak(communications.messages.takeLast(30).joinToString(". ") { m -> (if (m.senderId == communications.myProfileId) "You" else peerName) + ": " + ContentFilter.display(m.body, filter) })
                    })
                    DropdownMenuItem(text = { Text("Read aloud speed") }, onClick = { menu = false; speedDialog = true })
                    DropdownMenuItem(text = { Text(if (conversationId in communications.pinned) "Unpin" else "Pin") }, onClick = { menu = false; communications.togglePinned(conversationId) })
                    DropdownMenuItem(text = { Text(if (conversationId in communications.muted) "Unmute" else "Mute") }, onClick = { menu = false; communications.toggleMuted(conversationId) })
                    DropdownMenuItem(text = { Text("Mark unread") }, onClick = { menu = false; communications.markUnread(conversationId); communications.closeConversation() })
                    if (peerHandle.isNotBlank()) {
                        DropdownMenuItem(text = { Text(if (peerHandle in communications.favorites) "Remove from favourites" else "Add to favourites") }, onClick = { menu = false; communications.toggleFavorite(peerHandle) })
                        DropdownMenuItem(text = { Text("Report $peerName") }, onClick = { menu = false; report = ReportTarget("profile", peerHandle, peerName) })
                        DropdownMenuItem(text = { Text("Block $peerName") }, leadingIcon = { Icon(Icons.Default.Block, null) }, onClick = { menu = false; blocking = true })
                    }
                }
            }
        }
        if (finding) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 16.dp)) {
                OutlinedTextField(findText, { findText = it }, singleLine = true, label = { Text("Search this conversation") }, modifier = Modifier.weight(1f))
                IconButton(onClick = { finding = false; findText = "" }) { Icon(Icons.Default.Close, contentDescription = "Close search") }
            }
        }
        HorizontalDivider()
        StatusText(communications.statusMessage)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            val state = communications.threadState
            val shown = communications.messages.filter { findText.isBlank() || it.body.contains(findText.trim(), ignoreCase = true) }
            when {
                state is LoadState.Failed && communications.messages.isEmpty() ->
                    ErrorRetry(state.message, { scope.launch { communications.openConversation(conversationId) } }, Modifier.align(Alignment.Center))
                state is LoadState.Loading && communications.messages.isEmpty() ->
                    CircularProgressIndicator(Modifier.align(Alignment.Center).semantics { contentDescription = "Loading messages" })
                shown.isEmpty() -> CenteredText(if (findText.isBlank()) "No messages yet. Say hello." else "No messages match \"$findText\".")
                else -> LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(shown, key = { it.id }) { m ->
                        val isMine = m.senderId == communications.myProfileId
                        val isLastMine = isMine && m.id == mine.lastOrNull()?.id
                        MessageBubble(
                            m, isMine, if (isMine) "You" else peerName, filter, showReceipt = isLastMine,
                            onReply = { haptics.tap(); replyTo = m; Announcer.announce(context, "Replying to message") },
                            onCopy = { copyText(context, m.body) },
                            onShare = { shareText(context, m.body) },
                            onReadAloud = { readAloud.speak(ContentFilter.display(m.body, filter)) },
                            onReport = if (isMine) null else ({ report = ReportTarget("message", m.id, "this message") }),
                        )
                        MessageMediaActions(m, communications)
                        TextButton(onClick = { scope.launch { try { communications.react(conversationId, m.id, "👍") } catch (e: Exception) { Announcer.announce(context, "Reaction could not be saved") } } }) { Text("React with thumbs up") }
                    }
                }
            }
        }

        if (communications.otherTyping) {
            Text("$peerName is typing…", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp).semantics { liveRegion = LiveRegionMode.Polite })
        }
        communications.pendingMessages.filter { it.conversationId == conversationId }.forEach { p ->
            Text("Waiting to send: ${ContentFilter.display(p.body, filter)}", style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(horizontal = 16.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        replyTo?.let { r ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(8.dp)).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Replying to: ${ContentFilter.display(r.body, filter)}", Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                IconButton(onClick = { replyTo = null }) { Icon(Icons.Default.Close, contentDescription = "Cancel reply") }
            }
        }
        MessageMediaComposer(communications, conversationId, listOf(peerHandle))
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = draft,
                onValueChange = {
                    draft = it.take(4000)
                    communications.local.setDraft(conversationId, draft)
                    if (it.isNotBlank()) communications.sendTyping(conversationId)
                },
                label = { Text("Message $peerName") },
                maxLines = 5,
                modifier = Modifier.weight(1f),
            )
            IconButton(enabled = draft.isNotBlank() && !sending, onClick = { send() }, modifier = Modifier.size(56.dp)) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = if (sending) "Sending" else "Send message")
            }
        }
    }

    report?.let { t -> ReportDialog(t, communications) { report = null } }
    if (blocking) BlockDialog(peerName, peerHandle, communications) { ok -> blocking = false; if (ok) { communications.closeConversation(); scope.launch { communications.refreshConversations() } } }
    if (speedDialog) ReadAloudSpeedDialog(communications.local.readAloudRate, onDone = { r -> communications.local.readAloudRate = r; readAloud.rate = r; speedDialog = false })
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageBubble(
    m: ServerMessage, isMine: Boolean, sender: String, filter: Boolean, showReceipt: Boolean,
    onReply: () -> Unit, onCopy: () -> Unit, onShare: () -> Unit, onReadAloud: () -> Unit, onReport: (() -> Unit)?,
) {
    var menu by remember { mutableStateOf(false) }
    val body = ContentFilter.display(m.body, filter)
    val quoteLines = body.lines().takeWhile { it.startsWith("> ") }
    val quote = quoteLines.joinToString("\n") { it.removePrefix("> ") }.ifBlank { m.replyToBody.let { ContentFilter.display(it, filter) } }
    val main = body.lines().drop(quoteLines.size).joinToString("\n").trim()
    val receipt = if (isMine) m.receipt.label else null
    val description = buildString {
        append("$sender: ")
        if (quote.isNotBlank()) append("In reply to \"$quote\". ")
        append(main)
        append(". ${timeLabel(m.createdAt)}")
        if (receipt != null && showReceipt) append(". $receipt")
    }
    val actions = buildList {
        add(CustomAccessibilityAction("Reply") { onReply(); true })
        add(CustomAccessibilityAction("Copy") { onCopy(); true })
        add(CustomAccessibilityAction("Share") { onShare(); true })
        add(CustomAccessibilityAction("Read aloud") { onReadAloud(); true })
        onReport?.let { add(CustomAccessibilityAction("Report message") { it(); true }) }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (isMine) Arrangement.End else Arrangement.Start) {
        Box {
            Surface(
                color = if (isMine) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.widthIn(max = 320.dp)
                    .combinedClickable(onClick = { menu = true }, onClickLabel = "Message options", onLongClick = { menu = true })
                    .clearAndSetSemantics { contentDescription = description; customActions = actions; if (showReceipt && receipt != null) stateDescription = receipt },
            ) {
                Column(Modifier.padding(12.dp)) {
                    if (quote.isNotBlank()) {
                        Text(quote, style = MaterialTheme.typography.bodySmall, maxLines = 3, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(bottom = 4.dp).background(MaterialTheme.colorScheme.surface.copy(alpha = 0.5f), RoundedCornerShape(6.dp)).padding(6.dp))
                    }
                    Text(main)
                    Text(
                        timeLabel(m.createdAt) + if (isMine && showReceipt) " · ${m.receipt.label}" else "",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Reply") }, onClick = { menu = false; onReply() })
                DropdownMenuItem(text = { Text("Copy") }, onClick = { menu = false; onCopy() })
                DropdownMenuItem(text = { Text("Share") }, onClick = { menu = false; onShare() })
                DropdownMenuItem(text = { Text("Read aloud") }, onClick = { menu = false; onReadAloud() })
                onReport?.let { r -> DropdownMenuItem(text = { Text("Report message") }, onClick = { menu = false; r() }) }
            }
        }
    }
}

@Composable
fun ReadAloudSpeedDialog(initial: Float, onDone: (Float) -> Unit) {
    var rate by remember { mutableFloatStateOf(initial) }
    AlertDialog(
        onDismissRequest = { onDone(initial) },
        title = { Text("Read aloud speed") },
        text = {
            Column {
                Text("Speed: ${"%.1f".format(rate)}×")
                Slider(value = rate, onValueChange = { rate = (it * 10).toInt() / 10f }, valueRange = 0.5f..2.0f, steps = 14,
                    modifier = Modifier.semantics { contentDescription = "Read aloud speed"; stateDescription = "${"%.1f".format(rate)} times" })
            }
        },
        confirmButton = { TextButton(onClick = { onDone(rate) }) { Text("Done") } },
    )
}

@Composable
private fun NotificationCenter(communications: ProductionCommunicationsService, haptics: Haptics, onBack: () -> Unit, onOpen: (CommsDestination) -> Unit) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val filter = ContentFilter.isEnabled(context)
    BackHandler(onBack = onBack)
    LaunchedEffect(Unit) { communications.loadNotifications() }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back to messages") }
            Text("Notifications", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f).semantics { heading() })
            TextButton(enabled = communications.notifications.any { !it.isRead }, onClick = {
                scope.launch { if (communications.markAllNotificationsRead()) haptics.success(); Announcer.announce(context, communications.statusMessage) }
            }) { Text("Mark all read") }
        }
        val state = communications.notificationsState
        when {
            state is LoadState.Failed && communications.notifications.isEmpty() -> ErrorRetry(state.message, { scope.launch { communications.loadNotifications() } })
            state is LoadState.Loading && communications.notifications.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading notifications" }) }
            communications.notifications.isEmpty() -> CenteredText("You're all caught up.")
            else -> LazyColumn(Modifier.fillMaxSize()) {
                items(communications.notifications, key = { it.id }) { n ->
                    val dest = CommsDestination.parse(n.link)
                    Column(
                        Modifier.fillMaxWidth().heightIn(min = 56.dp)
                            .clickable(enabled = dest != null, onClickLabel = "Open") { haptics.tap(); dest?.let(onOpen) }
                            .semantics(mergeDescendants = true) { stateDescription = if (n.isRead) "Read" else "Unread" }
                            .padding(16.dp, 10.dp),
                    ) {
                        Text(ContentFilter.display(n.title, filter), fontWeight = if (n.isRead) FontWeight.Normal else FontWeight.Bold)
                        if (n.detail.isNotBlank()) Text(ContentFilter.display(n.detail, filter), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(timeLabel(n.createdAt), style = MaterialTheme.typography.labelSmall)
                    }
                    HorizontalDivider()
                }
            }
        }
    }
}

@Composable
fun BlockedAccountsScreen(communications: ProductionCommunicationsService, haptics: Haptics, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    BackHandler(onBack = onBack)
    LaunchedEffect(Unit) { communications.loadBlocked() }
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
            Text("Blocked accounts", style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
        }
        val state = communications.blockedState
        when {
            state is LoadState.Failed && communications.blocked.isEmpty() -> ErrorRetry(state.message, { scope.launch { communications.loadBlocked() } })
            state is LoadState.Loading && communications.blocked.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading blocked accounts" }) }
            communications.blocked.isEmpty() -> CenteredText("You haven't blocked anyone.")
            else -> LazyColumn(Modifier.fillMaxSize()) {
                items(communications.blocked, key = { it.handle }) { b ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                            Text(b.displayName.ifBlank { "@${b.handle}" })
                            Text("@${b.handle}", style = MaterialTheme.typography.labelMedium)
                        }
                        OutlinedButton(onClick = {
                            scope.launch { if (communications.unblock(b.handle)) haptics.success(); Announcer.announce(context, communications.statusMessage) }
                        }) { Text("Unblock", Modifier.semantics { contentDescription = "Unblock ${b.displayName.ifBlank { b.handle }}" }) }
                    }
                    HorizontalDivider()
                }
            }
        }
    }
}

/** Badge wrapper used by the bottom navigation. */
@Composable
fun UnreadBadge(count: Int, content: @Composable () -> Unit) {
    if (count <= 0) { content(); return }
    BadgedBox(badge = { Badge { Text(if (count > 99) "99+" else count.toString()) } }) { content() }
}

@Composable
fun SettingSwitch(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = androidx.compose.ui.semantics.Role.Switch) { onChange(!checked) }.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = null)
    }
}

