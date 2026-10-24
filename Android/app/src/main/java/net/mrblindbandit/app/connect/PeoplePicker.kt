package net.mrblindbandit.app.connect

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import net.mrblindbandit.app.social.VerifiedBadge

/** Uses the authenticated directory; no address-book access or contact upload. */
@Composable
fun PeoplePicker(c: ProductionCommunicationsService, onSelect: (String) -> Unit, onDismiss: () -> Unit) {
    data class Hit(val handle: String, val name: String, val verified: Boolean)
    var query by remember { mutableStateOf("") }
    var people by remember { mutableStateOf<List<Hit>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Enter a name or username") }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(query, retry) {
        people = emptyList()
        if (query.trim().length < 2) { busy = false; status = "Enter at least two characters"; return@LaunchedEffect }
        delay(350)
        busy = true
        try {
            val q = c.enc(query.trim())
            val response = try { c.request("/v1/social/directory?q=$q") }
            catch (e: BlindbanditApiException) {
                if (e.status !in setOf(404, 405, 501)) throw e
                c.request("/v1/social/search?q=$q&limit=30")
            }
            people = response.items().mapNotNull {
                val handle = it.lString("handle", "username")
                if (handle.isBlank() || handle.equals(c.myHandle, true)) null
                else Hit(
                    handle = handle,
                    name = it.lString("display_name", "name").ifBlank { "@$handle" },
                    verified = it.lBool("verified", "is_verified"),
                )
            }.distinctBy { it.handle }
            status = if (people.isEmpty()) "No matching people" else "${people.size} people found"
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) { status = "People could not be loaded. Try again." }
        finally { busy = false }
    }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Find people", modifier = Modifier.semantics { heading() }) }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(query, { query = it.take(100) }, label = { Text("Name or username") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            StatusText(status)
            LazyColumn(Modifier.heightIn(max = 320.dp)) {
                items(people, key = { it.handle }) { hit ->
                    val a11y = buildString {
                        append(hit.name)
                        append(", @")
                        append(hit.handle)
                        if (hit.verified) append(", verified")
                    }
                    ListItem(
                        headlineContent = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(hit.name)
                                if (hit.verified) {
                                    Spacer(Modifier.width(4.dp))
                                    VerifiedBadge()
                                }
                            }
                        },
                        supportingContent = { Text("@${hit.handle}") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 56.dp)
                            .semantics { contentDescription = a11y }
                            .clickable(onClickLabel = "Message @${hit.handle}") { onSelect(hit.handle) },
                    )
                }
            }
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
        dismissButton = { TextButton(enabled = !busy && query.trim().length >= 2, onClick = { retry++ }) { Text("Retry") } })
}
