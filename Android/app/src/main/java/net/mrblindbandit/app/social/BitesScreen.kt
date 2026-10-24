package net.mrblindbandit.app.social

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.CollectionItemInfo
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.collectionItemInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import net.mrblindbandit.app.connect.ProductionCommunicationsService
import net.mrblindbandit.app.ui.Spacing

/**
 * BanditBites + community newsfeed. TalkBack-first: vertical list with collection semantics,
 * merged card descriptions, and explicit actions — not a gesture-only pager.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BitesScreen(
    communications: ProductionCommunicationsService,
    social: SocialRepository,
    signedIn: Boolean,
    isOwnerAdmin: Boolean,
    onBack: () -> Unit,
    onOpenProfile: (String) -> Unit,
    onOpenAdmin: () -> Unit = {},
) {
    var tab by remember { mutableIntStateOf(0) }
    var bites by remember { mutableStateOf(social.cachedBites()) }
    var posts by remember { mutableStateOf(social.cachedNewsfeed()) }
    var loading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var caption by remember { mutableStateOf("") }
    var videoUrl by remember { mutableStateOf("") }
    var posterUrl by remember { mutableStateOf("") }
    var postBody by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    fun refresh() {
        scope.launch {
            loading = true
            status = "Loading…"
            try {
                bites = social.bites()
                posts = social.newsfeed()
                status = if (tab == 0) {
                    if (bites.isEmpty()) "No BanditBites yet." else "${bites.size} BanditBites."
                } else {
                    if (posts.isEmpty()) "No posts yet." else "${posts.size} posts."
                }
            } catch (e: Exception) {
                status = e.message ?: "Could not load the feed."
            } finally {
                loading = false
            }
        }
    }

    LaunchedEffect(Unit) { refresh() }
    BackHandler(onBack = onBack)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("BanditBites") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (isOwnerAdmin) {
                        TextButton(onClick = onOpenAdmin) { Text("Admin") }
                    }
                    IconButton(onClick = { refresh() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh feed")
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            TabRow(selectedTabIndex = tab) {
                Tab(selected = tab == 0, onClick = { tab = 0; status = "" }, text = { Text("Bites") })
                Tab(selected = tab == 1, onClick = { tab = 1; status = "" }, text = { Text("Feed") })
            }
            if (status.isNotBlank()) {
                Text(
                    status,
                    modifier = Modifier.padding(horizontal = Spacing.md, vertical = Spacing.sm)
                        .semantics { contentDescription = status },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (loading && bites.isEmpty() && posts.isEmpty()) {
                Row(Modifier.fillMaxWidth().padding(Spacing.lg), horizontalArrangement = Arrangement.Center) {
                    CircularProgressIndicator()
                }
            }
            if (tab == 0) {
                LazyColumn(
                    Modifier.fillMaxSize().padding(horizontal = Spacing.md)
                        .semantics { collectionInfo = CollectionInfo(rowCount = bites.size, columnCount = 1) },
                    verticalArrangement = Arrangement.spacedBy(Spacing.md),
                ) {
                    if (signedIn) {
                        item {
                            Card(Modifier.fillMaxWidth()) {
                                Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                                    Text("Publish a BanditBite", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                                    OutlinedTextField(caption, { caption = it.take(2200) }, label = { Text("Caption") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
                                    OutlinedTextField(videoUrl, { videoUrl = it }, label = { Text("Video URL") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                                    OutlinedTextField(posterUrl, { posterUrl = it }, label = { Text("Poster image URL (optional)") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                                    Button(
                                        enabled = videoUrl.isNotBlank() && !loading,
                                        onClick = {
                                            scope.launch {
                                                loading = true
                                                try {
                                                    social.publishBite(caption, videoUrl, posterUrl)
                                                    caption = ""; videoUrl = ""; posterUrl = ""
                                                    status = "Published."
                                                    bites = social.bites(useCacheFirst = false)
                                                } catch (e: Exception) {
                                                    status = e.message ?: "Publish failed."
                                                } finally { loading = false }
                                            }
                                        },
                                    ) { Text("Publish BanditBite") }
                                }
                            }
                        }
                    } else {
                        item {
                            Text("Sign in to publish BanditBites. You can still scroll the public feed.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    itemsIndexed(bites, key = { _, b -> b.id }) { index, bite ->
                        BiteCard(
                            bite = bite,
                            index = index,
                            total = bites.size,
                            signedIn = signedIn,
                            canModerate = isOwnerAdmin,
                            onOpenProfile = { onOpenProfile(bite.author.handle) },
                            onLike = {
                                scope.launch {
                                    try {
                                        social.reactBite(bite.id)
                                        status = "Liked ${bite.author.handle}'s BanditBite."
                                        bites = social.bites(useCacheFirst = false)
                                    } catch (e: Exception) { status = e.message ?: "Like failed." }
                                }
                            },
                            onOpenVideo = {
                                scope.launch { social.markBiteViewed(bite.id) }
                                if (bite.videoUrl.isNotBlank()) {
                                    runCatching {
                                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(bite.videoUrl)))
                                    }
                                }
                            },
                            onRemove = {
                                scope.launch {
                                    try {
                                        social.removeBite(bite.id)
                                        status = "Removed BanditBite."
                                        bites = social.bites(useCacheFirst = false)
                                    } catch (e: Exception) { status = e.message ?: "Remove failed." }
                                }
                            },
                        )
                    }
                    item { Spacer(Modifier.heightIn(min = Spacing.lg)) }
                }
            } else {
                LazyColumn(
                    Modifier.fillMaxSize().padding(horizontal = Spacing.md)
                        .semantics { collectionInfo = CollectionInfo(rowCount = posts.size, columnCount = 1) },
                    verticalArrangement = Arrangement.spacedBy(Spacing.md),
                ) {
                    if (signedIn) {
                        item {
                            Card(Modifier.fillMaxWidth()) {
                                Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                                    Text("Share an update", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                                    OutlinedTextField(postBody, { postBody = it.take(4000) }, label = { Text("What's happening?") }, modifier = Modifier.fillMaxWidth(), minLines = 3)
                                    Button(
                                        enabled = postBody.isNotBlank() && !loading,
                                        onClick = {
                                            scope.launch {
                                                loading = true
                                                try {
                                                    social.publishPost(postBody)
                                                    postBody = ""
                                                    status = "Posted."
                                                    posts = social.newsfeed()
                                                } catch (e: Exception) {
                                                    status = e.message ?: "Post failed."
                                                } finally { loading = false }
                                            }
                                        },
                                    ) { Text("Post") }
                                }
                            }
                        }
                    }
                    itemsIndexed(posts, key = { _, p -> p.id }) { index, post ->
                        PostCard(post, index, posts.size, onOpenProfile = { onOpenProfile(post.author.handle) })
                    }
                    item { Spacer(Modifier.heightIn(min = Spacing.lg)) }
                }
            }
        }
    }
}

@Composable
private fun BiteCard(
    bite: BanditBite,
    index: Int,
    total: Int,
    signedIn: Boolean,
    canModerate: Boolean,
    onOpenProfile: () -> Unit,
    onLike: () -> Unit,
    onOpenVideo: () -> Unit,
    onRemove: () -> Unit,
) {
    val authorLabel = buildString {
        append(bite.author.displayName)
        if (bite.author.verified) append(", verified")
        append(", @${bite.author.handle}")
    }
    val summary = buildString {
        append("BanditBite ${index + 1} of $total. $authorLabel. ")
        if (bite.caption.isNotBlank()) append(bite.caption).append(". ")
        append("${bite.viewCount} views. ${bite.reactionTotal} reactions.")
    }
    Card(
        Modifier.fillMaxWidth().heightIn(min = 120.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = summary
                collectionItemInfo = CollectionItemInfo(index, 1, 0, 1)
            },
    ) {
        Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Person, contentDescription = null, modifier = Modifier.size(28.dp))
                Spacer(Modifier.width(Spacing.sm))
                TextButton(onClick = onOpenProfile) {
                    Text("@${bite.author.handle}")
                    if (bite.author.verified) {
                        Spacer(Modifier.width(4.dp))
                        VerifiedBadge()
                    }
                }
            }
            if (bite.caption.isNotBlank()) Text(bite.caption, style = MaterialTheme.typography.bodyLarge)
            Text("${bite.viewCount} views · ${bite.reactionTotal} reactions", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Button(onClick = onOpenVideo) { Text("Play video") }
                if (signedIn) TextButton(onClick = onLike) { Text(if (bite.myReaction != null) "Liked" else "Like") }
                if (canModerate) TextButton(onClick = onRemove) { Text("Remove") }
            }
        }
    }
}

@Composable
private fun PostCard(post: SocialPost, index: Int, total: Int, onOpenProfile: () -> Unit) {
    val summary = buildString {
        append("Post ${index + 1} of $total. ${post.author.displayName}")
        if (post.author.verified) append(", verified")
        append(", @${post.author.handle}. ${post.body}. ${post.likes} likes, ${post.comments} comments.")
    }
    Card(
        Modifier.fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = summary
                collectionItemInfo = CollectionItemInfo(index, 1, 0, 1)
            },
    ) {
        Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            TextButton(onClick = onOpenProfile) {
                Text("@${post.author.handle}")
                if (post.author.verified) {
                    Spacer(Modifier.width(4.dp))
                    VerifiedBadge()
                }
            }
            Text(post.body, style = MaterialTheme.typography.bodyLarge)
            Text("${post.likes} likes · ${post.comments} comments", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
