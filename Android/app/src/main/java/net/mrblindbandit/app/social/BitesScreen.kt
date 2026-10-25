package net.mrblindbandit.app.social

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.mrblindbandit.app.connect.ProductionCommunicationsService
import net.mrblindbandit.app.ui.Spacing

/**
 * Native BanditBites + community feed: compose (gallery video or HTTPS URL),
 * in-app VideoView playback, optimistic Like — no WebView.
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
    var localVideoUri by remember { mutableStateOf<Uri?>(null) }
    var localVideoName by remember { mutableStateOf("") }
    var postBody by remember { mutableStateOf("") }
    var publishing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    val pickVideo = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            localVideoUri = uri
            localVideoName = uri.lastPathSegment?.substringAfterLast('/') ?: "video"
            videoUrl = ""
            status = "Video selected. Add a caption and publish."
        }
    }

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
                                    OutlinedTextField(
                                        caption, { caption = it.take(2200) },
                                        label = { Text("Caption") },
                                        modifier = Modifier.fillMaxWidth(),
                                        minLines = 2,
                                    )
                                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                                        FilledTonalButton(
                                            onClick = { pickVideo.launch("video/*") },
                                            modifier = Modifier.heightIn(min = 48.dp),
                                        ) {
                                            Icon(Icons.Default.Videocam, contentDescription = null)
                                            Spacer(Modifier.width(8.dp))
                                            Text(if (localVideoUri != null) "Change video" else "Choose video")
                                        }
                                    }
                                    if (localVideoUri != null) {
                                        Text("Selected: $localVideoName", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        TextButton(onClick = { localVideoUri = null; localVideoName = "" }) { Text("Clear video") }
                                    }
                                    OutlinedTextField(
                                        videoUrl,
                                        {
                                            videoUrl = it
                                            if (it.isNotBlank()) localVideoUri = null
                                        },
                                        label = { Text("Or paste HTTPS video URL") },
                                        modifier = Modifier.fillMaxWidth(),
                                        singleLine = true,
                                        enabled = localVideoUri == null,
                                    )
                                    Button(
                                        enabled = (localVideoUri != null || videoUrl.isNotBlank()) && !publishing,
                                        onClick = {
                                            scope.launch {
                                                publishing = true
                                                status = "Publishing…"
                                                try {
                                                    val url = if (localVideoUri != null) {
                                                        status = "Uploading video…"
                                                        val bytes = withContext(Dispatchers.IO) {
                                                            context.contentResolver.openInputStream(localVideoUri!!)!!.use { it.readBytes() }
                                                        }
                                                        val mime = context.contentResolver.getType(localVideoUri!!) ?: "video/mp4"
                                                        social.uploadBiteVideo(bytes, mime)
                                                    } else videoUrl.trim()
                                                    social.publishBite(caption, url)
                                                    caption = ""; videoUrl = ""; localVideoUri = null; localVideoName = ""
                                                    status = "Published."
                                                    bites = social.bites(useCacheFirst = false)
                                                } catch (e: Exception) {
                                                    status = e.message ?: "Publish failed."
                                                } finally {
                                                    publishing = false
                                                }
                                            }
                                        },
                                        modifier = Modifier.heightIn(min = 48.dp),
                                    ) {
                                        if (publishing) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                                        else Text("Publish BanditBite")
                                    }
                                }
                            }
                        }
                    } else {
                        item {
                            Text(
                                "Sign in to publish BanditBites. You can still scroll and play the public feed.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
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
                                // Optimistic like
                                val was = bite.myReaction
                                bites = bites.map {
                                    if (it.id != bite.id) it
                                    else it.copy(
                                        myReaction = if (was == null) "like" else null,
                                        reactionTotal = (it.reactionTotal + if (was == null) 1 else -1).coerceAtLeast(0),
                                    )
                                }
                                scope.launch {
                                    try {
                                        social.reactBite(bite.id)
                                        status = "Liked ${bite.author.handle}'s BanditBite."
                                    } catch (e: Exception) {
                                        bites = bites.map { if (it.id == bite.id) bite else it }
                                        status = e.message ?: "Like failed."
                                    }
                                }
                            },
                            onViewed = {
                                scope.launch { social.markBiteViewed(bite.id) }
                            },
                            onRemove = {
                                scope.launch {
                                    try {
                                        social.removeBite(bite.id)
                                        status = "Removed BanditBite."
                                        bites = social.bites(useCacheFirst = false)
                                    } catch (e: Exception) {
                                        status = e.message ?: "Remove failed."
                                    }
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
                                                } finally {
                                                    loading = false
                                                }
                                            }
                                        },
                                    ) { Text("Post") }
                                }
                            }
                        }
                    }
                    itemsIndexed(posts, key = { _, p -> p.id }) { index, post ->
                        PostCard(
                            post = post,
                            index = index,
                            total = posts.size,
                            signedIn = signedIn,
                            onOpenProfile = { onOpenProfile(post.author.handle) },
                            onLike = {
                                val liked = post.myReaction != null
                                posts = posts.map {
                                    if (it.id != post.id) it
                                    else it.copy(
                                        myReaction = if (liked) null else "like",
                                        likes = (it.likes + if (liked) -1 else 1).coerceAtLeast(0),
                                    )
                                }
                                scope.launch {
                                    try {
                                        if (liked) social.unlikePost(post.id) else social.likePost(post.id)
                                    } catch (e: Exception) {
                                        posts = posts.map { if (it.id == post.id) post else it }
                                        status = e.message ?: "Like failed."
                                    }
                                }
                            },
                        )
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
    onViewed: () -> Unit,
    onRemove: () -> Unit,
) {
    var expanded by remember(bite.id) { mutableStateOf(false) }
    val authorLabel = buildString {
        append(bite.author.displayName)
        if (bite.author.verified) append(", verified")
        append(", @${bite.author.handle}")
    }
    val summary = buildString {
        append("BanditBite ${index + 1} of $total. $authorLabel. ")
        if (bite.caption.isNotBlank()) append(bite.caption).append(". ")
        if (bite.videoUrl.isNotBlank()) append("Has video. ")
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
            if (bite.videoUrl.isNotBlank()) {
                if (expanded) {
                    BiteVideoPlayer(videoUrl = bite.videoUrl, autoPlay = true, onPlaying = onViewed)
                    TextButton(onClick = { expanded = false }) { Text("Hide video") }
                } else {
                    Button(
                        onClick = { expanded = true },
                        modifier = Modifier.heightIn(min = 48.dp).semantics { contentDescription = "Play BanditBite video" },
                    ) {
                        Icon(Icons.Default.Videocam, null)
                        Spacer(Modifier.width(8.dp))
                        Text("Play video")
                    }
                }
            }
            Text("${bite.viewCount} views · ${bite.reactionTotal} reactions", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                if (signedIn) {
                    TextButton(onClick = onLike) {
                        Icon(
                            if (bite.myReaction != null) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                            contentDescription = null,
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(if (bite.myReaction != null) "Liked" else "Like")
                    }
                }
                if (canModerate) TextButton(onClick = onRemove) { Text("Remove") }
            }
        }
    }
}

@Composable
private fun PostCard(
    post: SocialPost,
    index: Int,
    total: Int,
    signedIn: Boolean,
    onOpenProfile: () -> Unit,
    onLike: () -> Unit,
) {
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
            post.mediaUrls.firstOrNull()?.let { url ->
                if (url.contains(".mp4") || url.contains("/media/")) {
                    BiteVideoPlayer(videoUrl = url)
                }
            }
            Text("${post.likes} likes · ${post.comments} comments", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (signedIn) {
                TextButton(onClick = onLike) {
                    Icon(
                        if (post.myReaction != null) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                        contentDescription = null,
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(if (post.myReaction != null) "Liked" else "Like")
                }
            }
        }
    }
}
