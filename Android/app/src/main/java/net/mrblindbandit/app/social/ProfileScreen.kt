package net.mrblindbandit.app.social

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import net.mrblindbandit.app.connect.normalizeHandle
import net.mrblindbandit.app.ui.Spacing

enum class FollowListKind { Followers, Following }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    handle: String,
    myHandle: String,
    signedIn: Boolean,
    social: SocialRepository,
    onBack: () -> Unit,
    onOpenProfile: (String) -> Unit,
) {
    val h = normalizeHandle(handle)
    var profile by remember(h) { mutableStateOf(social.cachedProfile(h)) }
    var listKind by remember { mutableStateOf<FollowListKind?>(null) }
    var people by remember { mutableStateOf<List<SocialAuthor>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val isSelf = h.equals(normalizeHandle(myHandle), ignoreCase = true) && h.isNotBlank()

    fun loadProfile() {
        scope.launch {
            loading = true
            try {
                profile = social.refreshProfile(h)
                status = ""
            } catch (e: Exception) {
                if (profile == null) status = e.message ?: "Could not load profile."
                else status = "Showing cached profile. ${e.message ?: ""}"
            } finally { loading = false }
        }
    }

    fun loadList(kind: FollowListKind) {
        listKind = kind
        scope.launch {
            loading = true
            people = when (kind) {
                FollowListKind.Followers -> social.cachedFollowers(h)
                FollowListKind.Following -> social.cachedFollowing(h)
            }
            try {
                people = when (kind) {
                    FollowListKind.Followers -> social.followers(h)
                    FollowListKind.Following -> social.following(h)
                }
                status = if (people.isEmpty()) "No ${kind.name.lowercase()} yet." else "${people.size} ${kind.name.lowercase()}."
            } catch (e: Exception) {
                status = e.message ?: "Could not load list."
            } finally { loading = false }
        }
    }

    LaunchedEffect(h) {
        if (profile == null) loadProfile() else {
            // Refresh in background while showing cache.
            runCatching { profile = social.refreshProfile(h) }
        }
    }
    BackHandler {
        if (listKind != null) listKind = null else onBack()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when {
                            listKind == FollowListKind.Followers -> "Followers"
                            listKind == FollowListKind.Following -> "Following"
                            isSelf -> "My profile"
                            else -> "@$h"
                        },
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        if (listKind != null) listKind = null else onBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = {
                        if (listKind != null) listKind?.let { loadList(it) } else loadProfile()
                    }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
    ) { padding ->
        when (val kind = listKind) {
            null -> {
                val p = profile
                LazyColumn(
                    Modifier.fillMaxSize().padding(padding).padding(horizontal = Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(Spacing.md),
                ) {
                    item {
                        if (p == null && loading) {
                            Row(Modifier.fillMaxWidth().padding(Spacing.lg), horizontalArrangement = Arrangement.Center) {
                                CircularProgressIndicator()
                            }
                        } else if (p == null) {
                            Text(status.ifBlank { "Profile unavailable." })
                            Button(onClick = { loadProfile() }) { Text("Retry") }
                        } else {
                            val headerCd = buildString {
                                append(p.displayName)
                                if (p.verified) append(", verified")
                                append(". @${p.handle}. ")
                                if (p.bio.isNotBlank()) append(p.bio).append(". ")
                                append("${p.followers} followers, ${p.following} following, ${p.posts} posts, ${p.bites} BanditBites.")
                                if (p.isFollowing) append(" You follow this account.")
                            }
                            Column(
                                Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = headerCd },
                                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Default.Person, contentDescription = null, modifier = Modifier.size(56.dp))
                                    Spacer(Modifier.width(Spacing.md))
                                    Column {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text(p.displayName, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
                                            if (p.verified) {
                                                Spacer(Modifier.width(6.dp))
                                                VerifiedBadge(20.dp)
                                            }
                                        }
                                        Text("@${p.handle}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                                if (p.bio.isNotBlank()) Text(p.bio, style = MaterialTheme.typography.bodyLarge)
                                if (p.location.isNotBlank()) Text(p.location, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                                    Stat("Followers", p.followers) { loadList(FollowListKind.Followers) }
                                    Stat("Following", p.following) { loadList(FollowListKind.Following) }
                                    Stat("Posts", p.posts) {}
                                    Stat("Bites", p.bites) {}
                                }
                                if (signedIn && !isSelf) {
                                    Button(
                                        onClick = {
                                            scope.launch {
                                                try {
                                                    if (p.isFollowing) social.unfollow(p.handle) else social.follow(p.handle)
                                                    profile = social.refreshProfile(h)
                                                    status = if (p.isFollowing) "Unfollowed @${p.handle}." else "Following @${p.handle}."
                                                } catch (e: Exception) {
                                                    status = e.message ?: "Follow action failed."
                                                }
                                            }
                                        },
                                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                                    ) {
                                        Text(if (p.isFollowing) "Unfollow @${p.handle}" else "Follow @${p.handle}")
                                    }
                                }
                                if (status.isNotBlank()) Text(status, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
            else -> {
                LazyColumn(
                    Modifier.fillMaxSize().padding(padding).padding(horizontal = Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    item {
                        Text(
                            status.ifBlank { kind.name },
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = Spacing.sm),
                        )
                    }
                    items(people, key = { it.handle + it.id }) { person ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 56.dp)
                                .clickable { onOpenProfile(person.handle) }
                                .semantics {
                                    role = Role.Button
                                    contentDescription = buildString {
                                        append(person.displayName)
                                        if (person.verified) append(", verified")
                                        append(", @${person.handle}")
                                    }
                                }
                                .padding(vertical = Spacing.sm),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Default.Person, contentDescription = null)
                            Spacer(Modifier.width(Spacing.md))
                            Column(Modifier.weight(1f)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(person.displayName, style = MaterialTheme.typography.titleMedium)
                                    if (person.verified) {
                                        Spacer(Modifier.width(4.dp))
                                        VerifiedBadge()
                                    }
                                }
                                Text("@${person.handle}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Stat(label: String, value: Long, onClick: () -> Unit) {
    Column(
        Modifier
            .clickable(onClick = onClick)
            .padding(Spacing.sm)
            .semantics {
                role = Role.Button
                contentDescription = "$value $label"
            },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value.toString(), style = MaterialTheme.typography.titleLarge)
        Text(label, style = MaterialTheme.typography.labelMedium)
    }
}
