package net.mrblindbandit.app.chronicle

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Xml
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** The Blindbandit Chronicle: published stories from https://mrblindbandit.net/feed.xml. */
data class ChronicleStory(
    val id: String,
    val title: String,
    val summary: String,
    val url: String,
    val date: Date?,
    val imageUrl: String? = null,
)

object ChronicleRss {
    const val FEED_URL = "https://mrblindbandit.net/feed.xml"
    private val dateFormat get() = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", Locale.US)

    fun parse(xml: String): List<ChronicleStory> {
        val out = mutableListOf<ChronicleStory>()
        runCatching {
            val p = Xml.newPullParser()
            p.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
            p.setInput(xml.reader())
            var current: MutableMap<String, String>? = null
            var text = StringBuilder()
            var event = p.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                when (event) {
                    XmlPullParser.START_TAG -> { if (p.name == "item") current = mutableMapOf(); text = StringBuilder() }
                    XmlPullParser.TEXT, XmlPullParser.CDSECT -> text.append(p.text)
                    XmlPullParser.END_TAG -> {
                        val c = current
                        if (p.name == "item" && c != null) {
                            val link = c["link"]
                            if (!link.isNullOrBlank()) out += ChronicleStory(
                                id = c["guid"] ?: link,
                                title = ChronicleArticleParser.clean(c["title"] ?: ""),
                                summary = ChronicleArticleParser.clean(c["description"] ?: ""),
                                url = link,
                                date = c["pubDate"]?.let { runCatching { dateFormat.parse(it) }.getOrNull() },
                            )
                            current = null
                        } else if (c != null && p.name in setOf("guid", "title", "link", "description", "pubDate")) {
                            c[p.name] = text.toString().trim()
                        }
                    }
                }
                event = p.nextToken()
            }
        }
        return out
    }

    fun ogImage(html: String, base: String): String? {
        val tag = Regex("""<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']""", RegexOption.IGNORE_CASE).find(html) ?: return null
        return runCatching { URL(URL(base), tag.groupValues[1]).toString() }.getOrNull()
    }
}

enum class BlockKind { H1, H2, H3, PARAGRAPH, QUOTE, BULLET }
data class ChronicleBlock(val kind: BlockKind, val text: String)

/** Reduces article HTML to headings, paragraphs, quotes and list items for a native, TalkBack-friendly reader. */
object ChronicleArticleParser {
    fun blocks(html: String): List<ChronicleBlock> {
        var body = html
        val start = html.indexOf("<article")
        if (start >= 0) {
            val end = html.indexOf("</article>", start)
            if (end > start) body = html.substring(start, end + 10)
        }
        for (tag in listOf("nav", "script", "style", "figure", "form", "aside", "footer", "button")) {
            body = body.replace(Regex("<$tag[\\s\\S]*?</$tag>", RegexOption.IGNORE_CASE), "")
        }
        return Regex("<(h1|h2|h3|h4|p|blockquote|li)[^>]*>([\\s\\S]*?)</\\1>", RegexOption.IGNORE_CASE).findAll(body).mapNotNull { m ->
            val text = clean(m.groupValues[2])
            if (text.isEmpty()) return@mapNotNull null
            val kind = when (m.groupValues[1].lowercase()) {
                "h1" -> BlockKind.H1; "h2" -> BlockKind.H2; "h3", "h4" -> BlockKind.H3
                "blockquote" -> BlockKind.QUOTE; "li" -> BlockKind.BULLET; else -> BlockKind.PARAGRAPH
            }
            ChronicleBlock(kind, text)
        }.toList()
    }

    private val entities = mapOf(
        "&amp;" to "&", "&lt;" to "<", "&gt;" to ">", "&quot;" to "\"", "&#39;" to "'", "&apos;" to "'", "&nbsp;" to " ",
        "&rsquo;" to "\u2019", "&lsquo;" to "\u2018", "&ldquo;" to "\u201C", "&rdquo;" to "\u201D", "&mdash;" to "\u2014",
        "&ndash;" to "\u2013", "&hellip;" to "\u2026",
    )

    fun clean(fragment: String): String {
        var t = fragment.replace(Regex("<br\\s*/?>", RegexOption.IGNORE_CASE), "\n").replace(Regex("<[^>]+>"), "")
        entities.forEach { (k, v) -> t = t.replace(k, v) }
        t = Regex("&#(\\d+);").replace(t) { m -> m.groupValues[1].toIntOrNull()?.let { String(Character.toChars(it)) } ?: m.value }
        t = Regex("&#x([0-9a-fA-F]+);").replace(t) { m -> m.groupValues[1].toIntOrNull(16)?.let { String(Character.toChars(it)) } ?: m.value }
        return t.replace(Regex("[ \\t]+"), " ").trim()
    }
}

/** Maps mrblindbandit://article/<slug> and https://mrblindbandit.net/publications/<slug>/ to the article URL. */
object ChronicleDeepLink {
    fun articleUrl(raw: String?): String? {
        if (raw == null) return null
        val uri = runCatching { android.net.Uri.parse(raw) }.getOrNull() ?: return null
        val host = uri.host?.lowercase()
        val slug = when {
            uri.scheme.equals("mrblindbandit", true) && host == "article" -> uri.pathSegments.firstOrNull()
            host in setOf("mrblindbandit.net", "www.mrblindbandit.net") && uri.pathSegments.size >= 2 && uri.pathSegments[0] == "publications" -> uri.pathSegments[1]
            else -> null
        } ?: return null
        if (!slug.matches(Regex("^[A-Za-z0-9-]+$"))) return null
        return "https://mrblindbandit.net/publications/$slug/"
    }

    fun story(url: String): ChronicleStory {
        val slug = url.trimEnd('/').substringAfterLast('/')
        return ChronicleStory(url, slug.split('-').joinToString(" ") { it.replaceFirstChar(Char::titlecase) }, "", url, null)
    }
}

private object ChronicleNet {
    fun get(url: String): ByteArray {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 10_000; c.readTimeout = 15_000
        c.setRequestProperty("User-Agent", "BlindbanditAndroid")
        try {
            if (c.responseCode !in 200..299) error("HTTP ${c.responseCode}")
            return c.inputStream.use { it.readBytes() }
        } finally { c.disconnect() }
    }
    fun cacheFile(context: Context, name: String) = File(context.cacheDir, "chronicle").apply { mkdirs() }.let { File(it, name) }
    fun safeName(url: String) = url.trimEnd('/').substringAfterLast('/').replace(Regex("[^A-Za-z0-9-]"), "_").ifBlank { "story" }
}

@Composable
private fun rememberRemoteBitmap(url: String?): Bitmap? {
    val context = LocalContext.current
    var bmp by remember(url) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(url) {
        if (url == null) return@LaunchedEffect
        bmp = withContext(Dispatchers.IO) {
            runCatching {
                val f = ChronicleNet.cacheFile(context, "img-" + url.hashCode() + ".bin")
                val bytes = if (f.exists()) f.readBytes() else ChronicleNet.get(url).also { f.writeBytes(it) }
                val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
            }.getOrNull()
        }
    }
    return bmp
}

private fun formatDate(d: Date?) = d?.let { DateFormat.getDateInstance(DateFormat.LONG).format(it) }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChronicleScreen(onBack: () -> Unit, initialArticleUrl: String? = null, onOpenWeb: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var stories by remember { mutableStateOf<List<ChronicleStory>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var offline by remember { mutableStateOf(false) }
    var open by remember { mutableStateOf(initialArticleUrl?.let { ChronicleDeepLink.story(it) }) }

    suspend fun load() {
        loading = true
        val cache = ChronicleNet.cacheFile(context, "feed.xml")
        if (stories.isEmpty() && cache.exists()) stories = ChronicleRss.parse(cache.readText())
        val fresh = withContext(Dispatchers.IO) { runCatching { String(ChronicleNet.get(ChronicleRss.FEED_URL)) }.getOrNull() }
        if (fresh != null) {
            withContext(Dispatchers.IO) { runCatching { cache.writeText(fresh) } }
            val parsed = ChronicleRss.parse(fresh)
            val old = stories.associateBy { it.id }
            stories = parsed.map { it.copy(imageUrl = old[it.id]?.imageUrl) }
            offline = false
            error = if (parsed.isEmpty()) "No stories are published yet." else null
            // og:image for each story so the list shows the article's own artwork.
            val withImages = coroutineScope {
                stories.map { s -> async(Dispatchers.IO) {
                    if (s.imageUrl != null) s else runCatching {
                        val html = String(ChronicleNet.get(s.url))
                        runCatching { ChronicleNet.cacheFile(context, ChronicleNet.safeName(s.url) + ".html").writeText(html) }
                        s.copy(imageUrl = ChronicleRss.ogImage(html, s.url))
                    }.getOrDefault(s)
                } }.awaitAll()
            }
            stories = withImages
        } else {
            offline = stories.isNotEmpty()
            error = if (stories.isEmpty()) "Couldn't load the Chronicle. Check your connection and try again." else null
        }
        loading = false
    }

    LaunchedEffect(Unit) { if (stories.isEmpty()) load() }

    val current = open
    if (current != null) {
        ChronicleReader(current, onBack = { open = null }, onOpenWeb = onOpenWeb)
        return
    }
    BackHandler(onBack = onBack)
    Scaffold(topBar = {
        TopAppBar(
            title = { Text("The Chronicle", modifier = Modifier.semantics { heading() }) },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
            actions = { IconButton(onClick = { scope.launch { load() } }, enabled = !loading) { Icon(Icons.Default.Refresh, contentDescription = "Refresh stories") } },
        )
    }) { inner ->
        LazyColumn(Modifier.fillMaxSize().padding(inner), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (loading && stories.isEmpty()) item {
                Row(Modifier.fillMaxWidth().padding(24.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(24.dp)); Spacer(Modifier.width(12.dp)); Text("Loading the Chronicle")
                }
            }
            if (offline) item { Text("You're offline. Showing saved stories.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
            error?.let { msg -> item { Text(msg, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth().padding(24.dp)) } }
            items(stories, key = { it.id }) { story -> ChronicleRow(story) { open = story } }
        }
    }
}

@Composable
private fun ChronicleRow(story: ChronicleStory, onOpen: () -> Unit) {
    val img = rememberRemoteBitmap(story.imageUrl)
    val date = formatDate(story.date)
    val spoken = listOfNotNull(story.title, date, story.summary.takeIf { it.isNotBlank() }).joinToString(". ")
    Card(
        Modifier.fillMaxWidth().clickable(onClick = onOpen)
            .clearAndSetSemantics { contentDescription = spoken; onClick(label = "Open the full story") { onOpen(); true } },
    ) {
        Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(72.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) {
                img?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(story.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 3, overflow = TextOverflow.Ellipsis)
                date?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                if (story.summary.isNotBlank()) Text(story.summary, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChronicleReader(story: ChronicleStory, onBack: () -> Unit, onOpenWeb: (String) -> Unit) {
    val context = LocalContext.current
    var blocks by remember(story.url) { mutableStateOf<List<ChronicleBlock>>(emptyList()) }
    var failed by remember(story.url) { mutableStateOf(false) }
    var image by remember(story.url) { mutableStateOf(story.imageUrl) }
    BackHandler(onBack = onBack)
    LaunchedEffect(story.url) {
        val cache = ChronicleNet.cacheFile(context, ChronicleNet.safeName(story.url) + ".html")
        withContext(Dispatchers.IO) { if (cache.exists()) runCatching { cache.readText() }.getOrNull() else null }?.let {
            blocks = ChronicleArticleParser.blocks(it); if (image == null) image = ChronicleRss.ogImage(it, story.url)
        }
        val fresh = withContext(Dispatchers.IO) { runCatching { String(ChronicleNet.get(story.url)) }.getOrNull() }
        if (fresh != null) {
            withContext(Dispatchers.IO) { runCatching { cache.writeText(fresh) } }
            val parsed = ChronicleArticleParser.blocks(fresh)
            if (parsed.isNotEmpty()) blocks = parsed
            if (image == null) image = ChronicleRss.ogImage(fresh, story.url)
        } else failed = blocks.isEmpty()
    }
    val bmp = rememberRemoteBitmap(image)
    Scaffold(topBar = {
        TopAppBar(
            title = { Text("Chronicle") },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back to stories") } },
            actions = {
                IconButton(onClick = {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, story.url).putExtra(Intent.EXTRA_SUBJECT, story.title)
                    context.startActivity(Intent.createChooser(send, "Share story"))
                }) { Icon(Icons.Default.Share, contentDescription = "Share story") }
            },
        )
    }) { inner ->
        LazyColumn(Modifier.fillMaxSize().padding(inner), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            bmp?.let { b -> item { Image(b.asImageBitmap(), null, Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)), contentScale = ContentScale.FillWidth) } }
            if (blocks.isEmpty()) {
                item { Text(story.title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() }) }
                formatDate(story.date)?.let { item { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                if (story.summary.isNotBlank()) item { Text(story.summary, style = MaterialTheme.typography.bodyLarge) }
                item {
                    if (failed) Text("The full story couldn't be loaded. Check your connection, or open it on the website.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    else Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)); Text("Loading story") }
                }
            } else {
                formatDate(story.date)?.let { item { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                items(blocks.size) { i -> BlockView(blocks[i]) }
            }
            item {
                OutlinedButton(onClick = { onOpenWeb(story.url) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Icon(Icons.Default.OpenInBrowser, null); Spacer(Modifier.width(8.dp)); Text("Open on website")
                }
            }
        }
    }
}

@Composable
private fun BlockView(b: ChronicleBlock) {
    val t = MaterialTheme.typography
    when (b.kind) {
        BlockKind.H1 -> Text(b.text, style = t.headlineMedium, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
        BlockKind.H2 -> Text(b.text, style = t.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp).semantics { heading() })
        BlockKind.H3 -> Text(b.text, style = t.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp).semantics { heading() })
        BlockKind.PARAGRAPH -> Text(b.text, style = t.bodyLarge)
        BlockKind.QUOTE -> Row(Modifier.height(IntrinsicSize.Min)) {
            Box(Modifier.width(3.dp).fillMaxHeight().background(MaterialTheme.colorScheme.primary))
            Spacer(Modifier.width(12.dp)); Text(b.text, style = t.bodyLarge, fontStyle = FontStyle.Italic)
        }
        BlockKind.BULLET -> Row(Modifier.semantics(mergeDescendants = true) {}) { Text("\u2022  ", style = t.bodyLarge); Text(b.text, style = t.bodyLarge) }
    }
}
