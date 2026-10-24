package net.mrblindbandit.app.social

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import kotlinx.coroutines.launch
import net.mrblindbandit.app.connect.lBool
import net.mrblindbandit.app.connect.lString
import net.mrblindbandit.app.connect.normalizeHandle
import net.mrblindbandit.app.ui.Spacing
import org.json.JSONObject

/**
 * Native Social Admin for @kheck only (client gate). Server enforces platform_role.
 * Verify/unverify by username, moderation reports, ban/mute, remove BanditBites by id.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdminScreen(
    social: SocialRepository,
    onBack: () -> Unit,
) {
    var overview by remember { mutableStateOf<JSONObject?>(null) }
    var username by remember { mutableStateOf("") }
    var biteId by remember { mutableStateOf("") }
    var searchHits by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var reports by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var pendingVerify by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
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

    fun refreshAll() {
        run("Refreshing admin") {
            overview = social.adminOverview()
            reports = social.adminOpenReports()
            pendingVerify = social.adminPendingVerification()
            status = "Admin data updated."
        }
    }

    LaunchedEffect(Unit) { refreshAll() }
    BackHandler(onBack = onBack)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Social Admin") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { refreshAll() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh admin data")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding).padding(horizontal = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            item {
                Text(
                    "Owner tools for @kheck. Verification badges update on profiles, BanditBites, and people lists after verify/unverify.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (status.isNotBlank()) {
                    Text(status, modifier = Modifier.semantics { contentDescription = status })
                }
            }
            item {
                val o = overview
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        Text("Overview", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                        if (o == null) Text("Loading…")
                        else {
                            Text("Profiles: ${o.opt("profiles")}")
                            Text("Posts: ${o.opt("posts")}")
                            Text("Open reports: ${o.opt("open_reports")}")
                            Text("Pending verify: ${o.opt("pending_verification")}")
                            Text("Banned: ${o.opt("banned")} · Suspended: ${o.opt("suspended")}")
                        }
                    }
                }
            }
            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        Text("Verify / unverify by username", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                        OutlinedTextField(
                            value = username,
                            onValueChange = { username = it },
                            label = { Text("@username") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            enabled = !busy,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            Button(
                                enabled = !busy && username.isNotBlank(),
                                onClick = {
                                    run("Verifying") {
                                        val h = social.adminSetVerifiedByUsername(username, true)
                                        status = "Verified @$h. Badge will show on profile, Bites, and people."
                                    }
                                },
                            ) { Text("Verify") }
                            Button(
                                enabled = !busy && username.isNotBlank(),
                                onClick = {
                                    run("Unverifying") {
                                        val h = social.adminSetVerifiedByUsername(username, false)
                                        status = "Revoked verification for @$h."
                                    }
                                },
                            ) { Text("Unverify") }
                            TextButton(
                                enabled = !busy && username.isNotBlank(),
                                onClick = {
                                    run("Searching") {
                                        searchHits = social.adminSearchUsers(normalizeHandle(username))
                                        status = if (searchHits.isEmpty()) "No matches." else "${searchHits.size} matches."
                                    }
                                },
                            ) { Text("Search") }
                        }
                    }
                }
            }
            items(searchHits, key = { it.lString("id").ifBlank { it.lString("handle") } }) { u ->
                val handle = u.lString("handle")
                val id = u.lString("id")
                val verified = u.lBool("verified")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        Row {
                            Text("${u.lString("display_name")} @$handle", style = MaterialTheme.typography.titleMedium)
                            if (verified) {
                                Text(" ")
                                VerifiedBadge()
                            }
                        }
                        Text(u.lString("email"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("id: $id", style = MaterialTheme.typography.labelSmall)
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), modifier = Modifier.fillMaxWidth()) {
                            TextButton(enabled = !busy, onClick = {
                                run("Verify @$handle") { social.adminVerify(id); status = "Verified @$handle." }
                            }) { Text("Verify") }
                            TextButton(enabled = !busy, onClick = {
                                run("Unverify @$handle") { social.adminUnverify(id); status = "Unverified @$handle." }
                            }) { Text("Unverify") }
                            TextButton(enabled = !busy, onClick = {
                                run("Mute @$handle") { social.adminMutePosts(id, true); status = "Muted posting for @$handle." }
                            }) { Text("Mute") }
                            TextButton(enabled = !busy, onClick = {
                                run("Unmute @$handle") { social.adminMutePosts(id, false); status = "Unmuted @$handle." }
                            }) { Text("Unmute") }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            TextButton(enabled = !busy, onClick = {
                                run("Ban @$handle") { social.adminBan(id); status = "Banned @$handle." }
                            }) { Text("Ban") }
                            TextButton(enabled = !busy, onClick = {
                                run("Reinstate @$handle") { social.adminReinstate(id); status = "Reinstated @$handle." }
                            }) { Text("Reinstate") }
                        }
                    }
                }
            }
            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        Text("Remove BanditBite", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                        OutlinedTextField(
                            value = biteId,
                            onValueChange = { biteId = it },
                            label = { Text("BanditBite id") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            enabled = !busy,
                        )
                        Button(
                            enabled = !busy && biteId.isNotBlank(),
                            onClick = {
                                run("Removing BanditBite") {
                                    social.removeBite(biteId.trim())
                                    biteId = ""
                                    status = "BanditBite removed."
                                }
                            },
                            modifier = Modifier.heightIn(min = 48.dp),
                        ) { Text("Remove BanditBite") }
                    }
                }
            }
            item {
                Text("Open reports", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            }
            items(reports, key = { it.lString("id") }) { r ->
                val id = r.lString("id")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        Text("${r.lString("target_type")} ${r.lString("target_id")}", style = MaterialTheme.typography.titleSmall)
                        Text(r.lString("reason"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (r.lString("details").isNotBlank()) Text(r.lString("details"))
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            TextButton(enabled = !busy, onClick = {
                                run("Resolving") {
                                    social.adminResolveReport(id, "resolved")
                                    reports = social.adminOpenReports()
                                    status = "Report resolved."
                                }
                            }) { Text("Resolve") }
                            TextButton(enabled = !busy, onClick = {
                                run("Dismissing") {
                                    social.adminResolveReport(id, "dismissed")
                                    reports = social.adminOpenReports()
                                    status = "Report dismissed."
                                }
                            }) { Text("Dismiss") }
                            TextButton(enabled = !busy, onClick = {
                                run("Escalating") {
                                    social.adminResolveReport(id, "escalated")
                                    reports = social.adminOpenReports()
                                    status = "Report escalated."
                                }
                            }) { Text("Escalate") }
                        }
                    }
                }
            }
            if (reports.isEmpty()) {
                item { Text("No open reports.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            item {
                Text("Pending verification queue", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            }
            items(pendingVerify, key = { it.lString("id") }) { v ->
                val id = v.lString("id")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        Text("@${v.lString("handle")} ${v.lString("display_name")}", style = MaterialTheme.typography.titleSmall)
                        if (v.lString("evidence").isNotBlank()) Text(v.lString("evidence"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            TextButton(enabled = !busy, onClick = {
                                run("Approving verify") {
                                    social.adminReviewVerification(id, true)
                                    pendingVerify = social.adminPendingVerification()
                                    status = "Verification approved."
                                }
                            }) { Text("Approve") }
                            TextButton(enabled = !busy, onClick = {
                                run("Rejecting verify") {
                                    social.adminReviewVerification(id, false)
                                    pendingVerify = social.adminPendingVerification()
                                    status = "Verification rejected."
                                }
                            }) { Text("Reject") }
                        }
                    }
                }
            }
            if (pendingVerify.isEmpty()) {
                item { Text("Verification queue empty.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
    }
}
