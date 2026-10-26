package net.mrblindbandit.app.social

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import kotlinx.coroutines.launch
import net.mrblindbandit.app.connect.normalizeHandle
import net.mrblindbandit.app.ui.Spacing
import org.json.JSONObject

data class AdminTool(val id: String, val category: String, val title: String, val subtitle: String)

object AdminFatCatalog {
    val tools: List<AdminTool> = listOf(
    AdminTool("call_rtc_status", "Call RTC", "Call RTC status", "Show LiveKit/Agora provider"),
    AdminTool("call_rtc_livekit", "Call RTC", "Use LiveKit", "Switch to LiveKit"),
    AdminTool("call_rtc_agora", "Call RTC", "Use Agora", "Switch to Agora"),
    AdminTool("agora_flags", "Call RTC", "Agora feature flags", "Toggle Agora stubs"),
    AdminTool("call_analytics", "Call RTC", "Call analytics", "GET call analytics"),
    AdminTool("overview", "Overview", "Admin overview", "Dashboard counters"),
    AdminTool("user_search", "Users", "User search", "Search profiles"),
    AdminTool("verify_user", "Users", "Force verify", "Grant verified badge"),
    AdminTool("unverify_user", "Users", "Revoke verify", "Remove verified badge"),
    AdminTool("verification_queue", "Users", "Verification queue", "Pending verify requests"),
    AdminTool("ban_user", "Users", "Hard ban", "Permanently ban"),
    AdminTool("suspend_user", "Users", "Suspend 7 days", "Temporarily suspend"),
    AdminTool("reinstate_user", "Users", "Reinstate", "Unban or unsuspend"),
    AdminTool("mute_posts", "Users", "Mute posting", "Mute posts"),
    AdminTool("unmute_posts", "Users", "Unmute posting", "Clear mute"),
    AdminTool("mute_messages", "Users", "Mute messages", "Mute DMs"),
    AdminTool("disable_calls", "Users", "Disable calls", "Block calls"),
    AdminTool("enable_calls", "Users", "Enable calls", "Re-enable calls"),
    AdminTool("shadow_restrict", "Users", "Shadow restrict", "Shadowban"),
    AdminTool("rate_limit", "Users", "Rate-limit multiplier", "Raise multiplier"),
    AdminTool("inspect_devices", "Users", "Inspect devices", "Redacted devices"),
    AdminTool("revoke_push", "Users", "Revoke push tokens", "Wipe push tokens"),
    AdminTool("force_disconnect", "Users", "Force disconnect calls", "End active calls"),
    AdminTool("monetize_approve", "Users", "Approve monetization", "Approve monetize"),
    AdminTool("monetize_reject", "Users", "Reject monetization", "Reject monetize"),
    AdminTool("test_push", "Users", "Test push", "Admin test notification"),
    AdminTool("wipe_sessions", "Users", "Wipe sessions", "Force sign-out"),
    AdminTool("export_user", "Users", "Export user data", "Export JSON"),
    AdminTool("reports_queue", "Content", "Report queue", "Open reports"),
    AdminTool("hide_post", "Content", "Hide post", "Hide from feeds"),
    AdminTool("unhide_post", "Content", "Unhide post", "Restore post"),
    AdminTool("delete_post", "Content", "Delete post", "Admin delete"),
    AdminTool("pin_post", "Content", "Pin post", "Pin in feed"),
    AdminTool("unpin_post", "Content", "Unpin post", "Unpin"),
    AdminTool("hide_bite", "Content", "Hide / remove Bite", "Hide BanditBite"),
    AdminTool("feed_moderation", "Content", "Feed moderation list", "Feed controls"),
    AdminTool("content_search", "Content", "Content search", "Search posts/bites"),
    AdminTool("hashtag_blocklist", "Content", "Hashtag blocklist", "Blocked hashtags"),
    AdminTool("nsfw_filter", "Content", "NSFW filter toggle", "NSFW killswitch"),
    AdminTool("trending", "Content", "Trending / hashtags", "Trending controls"),
    AdminTool("appeals", "Content", "Appeals queue", "Appeals stub"),
    AdminTool("ads_queue", "Ads", "Ads marketplace queue", "Pending ads"),
    AdminTool("ads_placements", "Ads", "AdSense placements", "Placements"),
    AdminTool("broadcast_compose", "Comms", "Push broadcast", "System broadcast"),
    AdminTool("broadcast_history", "Comms", "Broadcast history", "Recent broadcasts"),
    AdminTool("label_announcement", "Comms", "Label announcement", "Portal announcement"),
    AdminTool("inapp_notification", "Comms", "In-app notification", "Notify one user"),
    AdminTool("device_stats", "Ops", "Device / install stats", "Device counters"),
    AdminTool("social_audit", "Ops", "Social admin audit", "Audit log"),
    AdminTool("platform_audit", "Ops", "Platform audit", "Ops audit"),
    AdminTool("ops_dashboard", "Ops", "Ops dashboard", "Ops overview"),
    AdminTool("ops_settings", "Ops", "System settings", "Maintenance / freeze"),
    AdminTool("maintenance_mode", "Ops", "Maintenance mode", "Toggle maintenance"),
    AdminTool("signup_freeze", "Ops", "Signup freeze", "Close signups"),
    AdminTool("invite_only", "Ops", "Invite-only mode", "Toggle invite_only"),
    AdminTool("global_flags", "Ops", "Global feature flags", "Killswitches"),
    AdminTool("feature_killswitches", "Ops", "Feature killswitches", "Global flags UI"),
    AdminTool("automod", "Ops", "Automod policy", "Automod rules"),
    AdminTool("app_config", "Ops", "Remote app config", "App configuration"),
    AdminTool("infra_status", "Ops", "Infra status", "Infra leftovers"),
    AdminTool("role_history", "Ops", "Role change history", "Role history"),
    AdminTool("trust_cases", "Ops", "Trust & safety cases", "Trust cases"),
    AdminTool("creator_payouts", "Ops", "Creator payouts", "Payouts queue"),
    AdminTool("platform_users", "Ops", "Platform user manager", "Platform accounts"),
    AdminTool("platform_sync", "Ops", "Sync platform users", "Backfill accounts"),
    AdminTool("invite_codes", "Ops", "Invite codes", "Mint/list codes"),
    AdminTool("invite_mods", "Ops", "Invite moderators", "Invite staff"),
    AdminTool("moderation_bundle", "Ops", "Moderation bundle", "Bundle endpoints"),
    AdminTool("agora_extras_recording", "Call RTC", "Agora recording stub", "Recording extras"),
    AdminTool("agora_extras_rtmp", "Call RTC", "Agora RTMP stub", "RTMP extras"),
    AdminTool("agora_extras_stt", "Call RTC", "Agora STT stub", "STT extras")
    )
    val count: Int get() = tools.size
}

/**
 * Fat Social Admin Control Center — 50+ owner admin tools + Call RTC LiveKit↔Agora.
 * Gate: Profile → Admin (@kheck). Server still enforces social_admin / ops roles.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdminScreen(
    social: SocialRepository,
    onBack: () -> Unit,
) {
    var filter by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf<AdminTool?>(null) }
    var rtcStatus by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun run(label: String, block: suspend () -> Unit) {
        scope.launch {
            busy = true
            status = "$label…"
            try {
                block()
            } catch (e: Exception) {
                status = e.message ?: "$label failed."
            } finally {
                busy = false
            }
        }
    }

    fun refreshRtc() {
        run("Call RTC") {
            val o = social.adminCallRtc()
            val provider = o.optString("provider", "livekit")
            rtcStatus = "Provider: $provider · ${o.toString().take(180)}"
            status = "RTC refreshed."
        }
    }

    LaunchedEffect(Unit) { refreshRtc() }
    BackHandler(onBack = {
        if (selected != null) selected = null else onBack()
    })

    val filtered = remember(filter) {
        val q = filter.trim().lowercase()
        if (q.isEmpty()) AdminFatCatalog.tools
        else AdminFatCatalog.tools.filter {
            it.title.lowercase().contains(q) || it.subtitle.lowercase().contains(q) ||
                it.category.lowercase().contains(q) || it.id.contains(q)
        }
    }
    val grouped = remember(filtered) {
        filtered.groupBy { it.category }.toList()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (selected == null) "Admin (${AdminFatCatalog.count})"
                        else selected!!.title,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        if (selected != null) selected = null else onBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { refreshRtc() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
    ) { padding ->
        if (selected != null) {
            AdminToolDetail(
                tool = selected!!,
                social = social,
                busy = busy,
                status = status,
                modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = Spacing.md),
                onStatus = { status = it },
                run = ::run,
            )
        } else {
            LazyColumn(
                Modifier.fillMaxSize().padding(padding).padding(horizontal = Spacing.md),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                item {
                    Text(
                        "${AdminFatCatalog.count} admin tools. Owner-only — server enforces roles.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.semantics { contentDescription = "${AdminFatCatalog.count} admin tools" },
                    )
                    if (status.isNotBlank()) {
                        Text(status, modifier = Modifier.semantics { contentDescription = status })
                    }
                    OutlinedTextField(
                        value = filter,
                        onValueChange = { filter = it },
                        label = { Text("Filter tools") },
                        modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Filter admin tools" },
                        singleLine = true,
                    )
                }
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            Text("Call RTC · LiveKit ↔ Agora", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                            Text(if (rtcStatus.isBlank()) "Pull refresh for provider status." else rtcStatus)
                            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                                Button(
                                    enabled = !busy,
                                    onClick = {
                                        run("Use LiveKit") {
                                            social.adminSetCallRtc("livekit")
                                            refreshRtc()
                                            status = "Switched to livekit."
                                        }
                                    },
                                    modifier = Modifier.semantics { contentDescription = "Use LiveKit" },
                                ) { Text("Use LiveKit") }
                                Button(
                                    enabled = !busy,
                                    onClick = {
                                        run("Use Agora") {
                                            social.adminSetCallRtc("agora")
                                            refreshRtc()
                                            status = "Switched to agora."
                                        }
                                    },
                                    modifier = Modifier.semantics { contentDescription = "Use Agora" },
                                ) { Text("Use Agora") }
                            }
                            TextButton(onClick = { selected = AdminFatCatalog.tools.first { it.id == "agora_flags" } }) {
                                Text("Agora feature flags")
                            }
                        }
                    }
                }
                grouped.forEach { (cat, tools) ->
                    item {
                        Text("$cat (${tools.size})", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                    }
                    items(tools, key = { it.id }) { tool ->
                        Card(
                            Modifier.fillMaxWidth().clickable { selected = tool }
                                .semantics { contentDescription = tool.title },
                        ) {
                            Column(Modifier.padding(Spacing.md)) {
                                Text(tool.title, style = MaterialTheme.typography.titleSmall)
                                Text(tool.subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AdminToolDetail(
    tool: AdminTool,
    social: SocialRepository,
    busy: Boolean,
    status: String,
    modifier: Modifier,
    onStatus: (String) -> Unit,
    run: (String, suspend () -> Unit) -> Unit,
) {
    var target by remember { mutableStateOf("") }
    var reason by remember { mutableStateOf("") }
    var postId by remember { mutableStateOf("") }
    var title by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }
    var payload by remember { mutableStateOf("") }
    var flagOn by remember { mutableStateOf(false) }

    LazyColumn(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        item {
            Text(tool.subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (status.isNotBlank()) Text(status)
        }
        when {
            tool.id in setOf("call_rtc_status", "call_rtc_livekit", "call_rtc_agora") -> {
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        Button(enabled = !busy, onClick = {
                            run("Use LiveKit") { social.adminSetCallRtc("livekit"); onStatus("livekit") }
                        }) { Text("Use LiveKit") }
                        Button(enabled = !busy, onClick = {
                            run("Use Agora") { social.adminSetCallRtc("agora"); onStatus("agora") }
                        }) { Text("Use Agora") }
                        Button(enabled = !busy, onClick = {
                            run("Status") { payload = social.adminCallRtc().toString(2); onStatus("OK") }
                        }) { Text("Refresh status") }
                    }
                }
            }
            tool.id == "agora_flags" || tool.id.startsWith("agora_extras") -> {
                item {
                    Button(enabled = !busy, onClick = {
                        run("Agora flags") { payload = social.adminAgoraFlags().toString(2); onStatus("Loaded") }
                    }) { Text("Load Agora flags") }
                }
            }
            tool.category == "Users" && tool.id !in setOf("user_search", "verification_queue", "inspect_devices", "export_user", "test_push", "rate_limit") -> {
                item {
                    OutlinedTextField(value = target, onValueChange = { target = it }, label = { Text("User id or @handle") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                    OutlinedTextField(value = reason, onValueChange = { reason = it }, label = { Text("Reason") }, modifier = Modifier.fillMaxWidth())
                    Button(enabled = !busy && target.isNotBlank(), onClick = {
                        val action = when (tool.id) {
                            "verify_user" -> "verify"
                            "unverify_user" -> "unverify"
                            "ban_user" -> "ban"
                            "suspend_user" -> "suspend"
                            "reinstate_user" -> "reinstate"
                            "mute_posts" -> "mute_posts"
                            "unmute_posts" -> "unmute_posts"
                            "mute_messages" -> "mute_messages"
                            "disable_calls" -> "disable_calls"
                            "enable_calls" -> "enable_calls"
                            "shadow_restrict" -> "shadow"
                            "revoke_push" -> "revoke_push"
                            "force_disconnect" -> "force_disconnect"
                            "monetize_approve" -> "monetize_approve"
                            "monetize_reject" -> "monetize_reject"
                            "wipe_sessions" -> "wipe_sessions"
                            else -> tool.id
                        }
                        run(tool.title) {
                            val id = target.trim().removePrefix("@")
                            val b = JSONObject()
                            if (reason.isNotBlank()) b.put("reason", reason)
                            payload = social.adminUserAction(id, action, b).toString(2)
                            onStatus("OK")
                        }
                    }) { Text(tool.title) }
                }
            }
            tool.id in setOf("hide_post", "unhide_post", "delete_post", "pin_post", "unpin_post") -> {
                item {
                    OutlinedTextField(value = postId, onValueChange = { postId = it }, label = { Text("Post id") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                    Button(enabled = !busy && postId.isNotBlank(), onClick = {
                        val action = tool.id.removeSuffix("_post").let { if (it == "hide" || it == "unhide" || it == "delete" || it == "pin" || it == "unpin") it else tool.id }
                        val a = when (tool.id) {
                            "hide_post" -> "hide"; "unhide_post" -> "unhide"; "delete_post" -> "delete"; "pin_post" -> "pin"; "unpin_post" -> "unpin"; else -> "hide"
                        }
                        run(tool.title) {
                            payload = social.adminPostAction(postId.trim(), a).toString(2)
                            onStatus("OK")
                        }
                    }) { Text(tool.title) }
                }
            }
            tool.id == "broadcast_compose" -> {
                item {
                    OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Title") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = body, onValueChange = { body = it }, label = { Text("Body") }, modifier = Modifier.fillMaxWidth())
                    Button(enabled = !busy, onClick = {
                        run("Broadcast") { payload = social.adminBroadcast(title, body).toString(2); onStatus("Sent") }
                    }) { Text("Send broadcast") }
                }
            }
            tool.id == "test_push" -> {
                item {
                    OutlinedTextField(value = target, onValueChange = { target = it }, label = { Text("User id") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Title") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = body, onValueChange = { body = it }, label = { Text("Body") }, modifier = Modifier.fillMaxWidth())
                    Button(enabled = !busy && target.isNotBlank(), onClick = {
                        run("Test push") {
                            payload = social.adminUserAction(target.trim(), "test_push", JSONObject().put("title", title).put("body", body)).toString(2)
                            onStatus("Sent")
                        }
                    }) { Text("Send test push") }
                }
            }
            tool.id == "user_search" -> {
                item {
                    OutlinedTextField(value = target, onValueChange = { target = it }, label = { Text("Query") }, modifier = Modifier.fillMaxWidth())
                    Button(enabled = !busy && target.isNotBlank(), onClick = {
                        run("Search") {
                            val hits = social.adminSearchUsers(normalizeHandle(target))
                            payload = hits.joinToString("\n") { it.toString() }
                            onStatus("${hits.size} matches")
                        }
                    }) { Text("Search") }
                }
            }
            tool.id == "nsfw_filter" -> {
                item {
                    Row {
                        Text("NSFW filter")
                        Switch(checked = flagOn, onCheckedChange = { flagOn = it })
                    }
                    Button(enabled = !busy, onClick = {
                        run("Save NSFW") {
                            payload = social.adminPut("/v1/social/admin/nsfw-filter", JSONObject().put("enabled", flagOn)).toString(2)
                            onStatus("Saved")
                        }
                    }) { Text("Save") }
                }
            }
            tool.id in setOf("global_flags", "feature_killswitches") -> {
                item {
                    Button(enabled = !busy, onClick = {
                        run("Flags") { payload = social.adminGlobalFlags().toString(2); onStatus("Loaded") }
                    }) { Text("Load global flags") }
                }
            }
            else -> {
                val path = when (tool.id) {
                    "overview" -> "/v1/social/admin/overview"
                    "call_analytics" -> "/v1/social/admin/call-analytics?limit=40"
                    "verification_queue" -> "/v1/social/admin/verification?status=pending&limit=50"
                    "reports_queue" -> "/v1/social/admin/reports?status=open&limit=50"
                    "feed_moderation" -> "/v1/social/admin/feed"
                    "content_search" -> "/v1/social/admin/content-search?q=test"
                    "hashtag_blocklist" -> "/v1/social/admin/hashtag-blocklist"
                    "trending" -> "/v1/social/admin/trending"
                    "appeals" -> "/v1/social/admin/appeals"
                    "ads_queue" -> "/v1/social/admin/ads?limit=50"
                    "ads_placements" -> "/v1/admin/ops/ads/placements"
                    "broadcast_history" -> "/v1/social/admin/broadcast/history"
                    "device_stats" -> "/v1/social/admin/device-stats"
                    "social_audit" -> "/v1/social/admin/audit?limit=80"
                    "platform_audit" -> "/v1/admin/ops/audit"
                    "ops_dashboard" -> "/v1/admin/ops/dashboard"
                    "ops_settings", "maintenance_mode", "signup_freeze", "invite_only" -> "/v1/admin/ops/settings"
                    "automod" -> "/v1/social/admin/automod"
                    "app_config" -> "/v1/social/admin/app-config"
                    "infra_status" -> "/v1/admin/ops/infra/status"
                    "role_history" -> "/v1/admin/ops/roles/history"
                    "trust_cases" -> "/v1/admin/ops/trust-cases"
                    "creator_payouts" -> "/v1/admin/ops/payouts"
                    "platform_users" -> "/v1/admin/ops/users"
                    "invite_codes" -> "/v1/social/admin/invite-codes"
                    "moderation_bundle" -> "/v1/admin/ops/moderation/bundle"
                    "inspect_devices" -> null
                    "export_user" -> null
                    "hide_bite" -> null
                    "rate_limit" -> null
                    "label_announcement" -> null
                    "inapp_notification" -> null
                    "platform_sync" -> null
                    "invite_mods" -> null
                    else -> "/v1/social/admin/overview"
                }
                item {
                    when (tool.id) {
                        "inspect_devices", "export_user" -> {
                            OutlinedTextField(value = target, onValueChange = { target = it }, label = { Text("User id") }, modifier = Modifier.fillMaxWidth())
                            Button(enabled = !busy && target.isNotBlank(), onClick = {
                                val p = if (tool.id == "export_user") "/v1/social/admin/users/${java.net.URLEncoder.encode(target.trim(), "UTF-8")}/export"
                                else "/v1/social/admin/users/${java.net.URLEncoder.encode(target.trim(), "UTF-8")}/devices"
                                run(tool.title) { payload = social.adminPrettyGet(p); onStatus("OK") }
                            }) { Text("Run") }
                        }
                        "hide_bite" -> {
                            OutlinedTextField(value = postId, onValueChange = { postId = it }, label = { Text("Bite id") }, modifier = Modifier.fillMaxWidth())
                            Button(enabled = !busy && postId.isNotBlank(), onClick = {
                                run("Hide bite") {
                                    payload = social.adminPost("/v1/social/admin/bites/${java.net.URLEncoder.encode(postId.trim(), "UTF-8")}/hide", JSONObject().put("remove", true)).toString(2)
                                    onStatus("OK")
                                }
                            }) { Text("Hide/remove") }
                        }
                        "rate_limit" -> {
                            OutlinedTextField(value = target, onValueChange = { target = it }, label = { Text("User id") }, modifier = Modifier.fillMaxWidth())
                            Button(enabled = !busy && target.isNotBlank(), onClick = {
                                run("Rate limit") {
                                    payload = social.adminUserAction(target.trim(), "rate_limit", JSONObject().put("multiplier", 2)).toString(2)
                                    onStatus("OK")
                                }
                            }) { Text("Apply x2") }
                        }
                        "platform_sync" -> {
                            Button(enabled = !busy, onClick = {
                                run("Sync") { payload = social.adminPost("/v1/admin/ops/users/sync").toString(2); onStatus("OK") }
                            }) { Text("Sync platform users") }
                        }
                        "label_announcement", "inapp_notification", "invite_mods" -> {
                            OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Title / email") }, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(value = body, onValueChange = { body = it }, label = { Text("Body") }, modifier = Modifier.fillMaxWidth())
                            Button(enabled = !busy, onClick = {
                                run(tool.title) {
                                    val p = when (tool.id) {
                                        "label_announcement" -> "/v1/admin/ops/announcements"
                                        "inapp_notification" -> "/v1/admin/ops/notifications"
                                        else -> "/v1/admin/ops/invites"
                                    }
                                    val b = when (tool.id) {
                                        "invite_mods" -> JSONObject().put("email", title).put("role", "moderator")
                                        "inapp_notification" -> JSONObject().put("user_id", target).put("title", title).put("body", body)
                                        else -> JSONObject().put("title", title).put("body", body)
                                    }
                                    payload = social.adminPost(p, b).toString(2)
                                    onStatus("OK")
                                }
                            }) { Text("Submit") }
                        }
                        else -> {
                            if (path != null) {
                                Button(enabled = !busy, onClick = {
                                    run(tool.title) { payload = social.adminPrettyGet(path); onStatus("OK") }
                                }) { Text("Load") }
                            }
                        }
                    }
                }
            }
        }
        if (payload.isNotBlank()) {
            item {
                Text(payload, style = MaterialTheme.typography.bodySmall, modifier = Modifier.semantics { contentDescription = "Admin response" })
            }
        }
    }
}
