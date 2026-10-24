package net.mrblindbandit.app.connect

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** Native group UI uses the same routes and fields as CallsGroupsAPI.swift. */
data class SocialGroup(val id: String, val name: String, val unread: Int) {
    companion object {
        fun parse(row: JSONObject) = SocialGroup(row.lString("id", "group_id"), row.lString("name").ifBlank { "Group" }, (row.lLong("unread_count") ?: 0).toInt())
    }
}

suspend fun ProductionCommunicationsService.groups(): List<SocialGroup> = request("/v1/social/groups?limit=100").items().map(SocialGroup::parse).filter { it.id.isNotBlank() }
suspend fun ProductionCommunicationsService.createGroup(name: String, handles: List<String>): SocialGroup {
    require(name.isNotBlank())
    val members = JSONArray(handles.map(::normalizeHandle).filter { it.isNotBlank() }.distinct())
    return SocialGroup.parse(request("/v1/social/groups", "POST", JSONObject().put("name", name.trim().take(100)).put("member_handles", members).put("handles", members)))
}
suspend fun ProductionCommunicationsService.groupDetail(id: String) = request("/v1/social/groups/${enc(id)}")
suspend fun ProductionCommunicationsService.renameGroup(id: String, name: String) = request("/v1/social/groups/${enc(id)}", "PATCH", JSONObject().put("name", name.trim().take(100)))
suspend fun ProductionCommunicationsService.addGroupMembers(id: String, handles: List<String>) = request("/v1/social/groups/${enc(id)}/members", "POST", JSONObject().put("handles", JSONArray(handles.map(::normalizeHandle))))
suspend fun ProductionCommunicationsService.setGroupRole(id: String, handle: String, role: String) = request("/v1/social/groups/${enc(id)}/members/${enc(normalizeHandle(handle))}", "PATCH", JSONObject().put("role", role))
suspend fun ProductionCommunicationsService.groupTyping(id: String): List<String> {
    val names = request("/v1/social/groups/${enc(id)}/typing").optJSONArray("typing_handles") ?: return emptyList()
    return (0 until names.length()).map { names.getString(it) }.filter { !it.equals(myHandle, true) }
}
suspend fun ProductionCommunicationsService.removeGroupMember(id: String, handle: String) = request("/v1/social/groups/${enc(id)}/members/${enc(normalizeHandle(handle))}", "DELETE")
suspend fun ProductionCommunicationsService.groupMessages(id: String): List<ServerMessage> = request("/v1/social/groups/${enc(id)}/messages?limit=100").items().mapNotNull {
    if (encryption != null) encryption!!.resolve(it)
    else if (!it.lBool("e2ee")) ServerMessage.parse(it)
    else ServerMessage.parse(it)?.copy(body = "Encrypted message unavailable on this device", encrypted = true, decryptFailed = true)
}.sortedBy { it.createdAt }
suspend fun ProductionCommunicationsService.sendGroupMessage(id: String, text: String, silent: Boolean) {
    val handles = groupDetail(id).optJSONArray("members") ?: error("Group membership unavailable. Message not sent.")
    val peers = (0 until handles.length()).map { handles.getJSONObject(it).lString("handle") }.filter { it.isNotBlank() }
    check(peers.isNotEmpty()) { "Group membership unavailable. Message not sent." }
    request("/v1/social/groups/${enc(id)}/messages", "POST", messageFields(peers, text.trim().take(4000), silent))
}
suspend fun ProductionCommunicationsService.react(conversation: String, message: String, emoji: String?, group: Boolean = false) {
    val path = if (group) "/v1/social/groups/${enc(conversation)}/messages/${enc(message)}/reactions" else "/v1/social/messages/${enc(conversation)}/${enc(message)}/reactions"
    request(path, "POST", JSONObject().put("emoji", emoji ?: JSONObject.NULL))
}

@Composable
fun GroupsScreen(c: ProductionCommunicationsService, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val scope = rememberCoroutineScope()
    var groups by remember { mutableStateOf<List<SocialGroup>>(emptyList()) }
    var error by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var creating by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var handles by remember { mutableStateOf("") }
    suspend fun refresh() { busy = true; try { groups = c.groups(); error = "" } catch (e: Exception) { error = e.localizedMessage.orEmpty() } finally { busy = false } }
    LaunchedEffect(Unit) { refresh() }
    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(onClick = onBack) { Text("Back to messages") }
        Text("Groups", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
        Row { Button(onClick = { creating = true }) { Text("New group") }; TextButton(enabled = !busy, onClick = { scope.launch { refresh() } }) { Text("Refresh") } }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        StatusText(error)
        LazyColumn {
            items(groups, key = { it.id }) { g ->
                ListItem(headlineContent = { Text(g.name) }, supportingContent = { Text(if (g.unread > 0) "${g.unread} unread messages" else "Open group") },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(onClickLabel = "Open ${g.name}") { c.openGroupId = g.id })
                HorizontalDivider()
            }
        }
    }
    if (creating) AlertDialog(onDismissRequest = { if (!busy) creating = false }, title = { Text("Create group") }, text = {
        Column {
            OutlinedTextField(name, { name = it }, label = { Text("Group name") })
            OutlinedTextField(handles, { handles = it }, label = { Text("Member usernames, separated by commas") })
            StatusText(error)
        }
    }, confirmButton = { TextButton(enabled = !busy && name.isNotBlank(), onClick = { scope.launch {
        busy = true
        try { val g = c.createGroup(name, handles.split(',')); c.openGroupId = g.id; creating = false; error = "" }
        catch (e: Exception) { error = e.localizedMessage.orEmpty() } finally { busy = false }
    } }) { Text("Create") } }, dismissButton = { TextButton(onClick = { creating = false }, enabled = !busy) { Text("Cancel") } })
}

@Composable
internal fun StatusText(text: String) {
    if (text.isNotBlank()) Text(text, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
}

@Composable
fun GroupThreadScreen(c: ProductionCommunicationsService, id: String) {
    val scope = rememberCoroutineScope()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var rows by remember(id) { mutableStateOf<List<ServerMessage>>(emptyList()) }
    var title by remember(id) { mutableStateOf("Group") }
    var error by remember(id) { mutableStateOf("") }
    var draft by remember(id) { mutableStateOf(c.local.draft("group:$id")) }
    var silent by remember(id) { mutableStateOf(false) }
    var busy by remember(id) { mutableStateOf(false) }
    var members by remember(id) { mutableStateOf(false) }
    var typing by remember(id) { mutableStateOf<List<String>>(emptyList()) }
    suspend fun refresh() {
        try {
            rows = c.groupMessages(id)
            typing = try { c.groupTyping(id) } catch (_: Exception) { emptyList() }
            c.request("/v1/social/groups/${c.enc(id)}/read", "POST", JSONObject())
            error = ""
        } catch (e: Exception) { error = e.localizedMessage.orEmpty() }
    }
    LaunchedEffect(id, draft) {
        if (draft.isNotBlank()) {
            delay(600)
            runCatching { c.request("/v1/social/groups/${c.enc(id)}/typing", "POST", JSONObject().put("typing", true)) }
        }
    }
    BackHandler { c.openGroupId = null }
    LaunchedEffect(id) {
        runCatching { c.groupDetail(id) }.onSuccess { title = it.lString("name").ifBlank { "Group" } }
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { while (true) { refresh(); delay(5_000) } }
    }
    Column(Modifier.fillMaxSize().imePadding().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row { TextButton(onClick = { c.openGroupId = null }) { Text("Back") }; Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f).semantics { heading() }); TextButton(onClick = { members = true }) { Text("Members") } }
        StatusText(error)
        StatusText(if (typing.isEmpty()) "" else typing.joinToString(", ") { "@$it" } + " typing")
        LazyColumn(Modifier.weight(1f), reverseLayout = true) {
            items(rows.asReversed(), key = { it.id }) { m ->
                var reaction by remember(m.id) { mutableStateOf(false) }
                Column(Modifier.fillMaxWidth().padding(8.dp)) {
                    Text(if (m.senderId == c.myProfileId) "You" else "Group member", style = MaterialTheme.typography.labelMedium)
                    Text(net.mrblindbandit.app.safety.ContentFilter.display(m.body, net.mrblindbandit.app.safety.ContentFilter.isEnabled(c.local.context)))
                    MessageMediaActions(m, c)
                    TextButton(onClick = { reaction = true }) { Text("React to message") }
                    DropdownMenu(reaction, { reaction = false }) {
                        listOf("👍", "❤️", "😂").forEach { emoji -> DropdownMenuItem(text = { Text(emoji) }, onClick = { reaction = false; scope.launch { try { c.react(id, m.id, emoji, true) } catch (e: Exception) { error = "Reaction could not be saved." } } }) }
                    }
                }
                HorizontalDivider()
            }
        }
        MessageMediaComposer(c, id, emptyList(), group = true, onSent = { scope.launch { refresh() } })
        SettingSwitch("Send silently", silent) { silent = it }
        OutlinedTextField(draft, { draft = it.take(4000); c.local.setDraft("group:$id", draft) }, label = { Text("Message $title") }, modifier = Modifier.fillMaxWidth(), maxLines = 5)
        Button(enabled = !busy && draft.isNotBlank(), modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp), onClick = { scope.launch {
            busy = true
            try { c.sendGroupMessage(id, draft, silent); draft = ""; c.local.setDraft("group:$id", ""); refresh() }
            catch (e: Exception) { error = e.localizedMessage.orEmpty() } finally { busy = false }
        } }) { Text(if (busy) "Sending" else "Send message") }
    }
    if (members) GroupMembersDialog(c, id, title, onDismiss = { members = false }, onLeft = { members = false; c.openGroupId = null })
}

@Composable
private fun GroupMembersDialog(c: ProductionCommunicationsService, id: String, title: String, onDismiss: () -> Unit, onLeft: () -> Unit) {
    val scope = rememberCoroutineScope()
    var members by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var error by remember { mutableStateOf("") }
    var handles by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var rename by remember { mutableStateOf(title) }
    suspend fun refresh() { val a = c.groupDetail(id).optJSONArray("members") ?: JSONArray(); members = (0 until a.length()).map { a.getJSONObject(it) } }
    fun action(block: suspend () -> Unit) { scope.launch { busy = true; try { block(); error = "" } catch (e: Exception) { error = e.localizedMessage.orEmpty() } finally { busy = false } } }
    LaunchedEffect(id) { try { refresh() } catch (e: Exception) { error = e.localizedMessage.orEmpty() } }
    val admin = members.any { it.lString("handle").equals(c.myHandle, true) && it.lString("role") in setOf("owner", "admin") }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Group members") }, text = {
        LazyColumn {
            item { StatusText(error) }
            items(members) { m ->
                val handle = m.lString("handle")
                Text("@${handle}: ${m.lString("role")}")
                if (admin && handle != c.myHandle && m.lString("role") != "owner") TextButton(enabled = !busy, onClick = { action {
                    c.setGroupRole(id, handle, if (m.lString("role") == "admin") "member" else "admin"); refresh()
                } }) { Text(if (m.lString("role") == "admin") "Make @$handle a member" else "Make @$handle an admin") }
                if (admin && handle != c.myHandle && m.lString("role") != "owner") TextButton(enabled = !busy, onClick = { action { c.removeGroupMember(id, handle); refresh() } }) { Text("Remove @$handle") }
            }
            if (admin) item {
                OutlinedTextField(rename, { rename = it }, label = { Text("Group name") })
                TextButton(enabled = !busy && rename.isNotBlank(), onClick = { action { c.renameGroup(id, rename) } }) { Text("Save name") }
                OutlinedTextField(handles, { handles = it }, label = { Text("Usernames to add, comma separated") })
                TextButton(enabled = !busy && handles.isNotBlank(), onClick = { action { c.addGroupMembers(id, handles.split(',')); handles = ""; refresh() } }) { Text("Add members") }
            }
            item { TextButton(enabled = !busy, onClick = { action { c.removeGroupMember(id, c.myHandle); onLeft() } }) { Text("Leave group") } }
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } })
}
