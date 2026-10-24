package net.mrblindbandit.app.connect

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

/** Uses the authenticated directory; no address-book access or contact upload. */
@Composable
fun PeoplePicker(c: ProductionCommunicationsService, onSelect: (String) -> Unit, onDismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var people by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
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
                else handle to it.lString("display_name", "name").ifBlank { "@$handle" }
            }.distinctBy { it.first }
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
                items(people, key = { it.first }) { (handle, name) ->
                    ListItem(headlineContent = { Text(name) }, supportingContent = { Text("@$handle") },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(onClickLabel = "Message @$handle") { onSelect(handle) })
                }
            }
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
        dismissButton = { TextButton(enabled = !busy && query.trim().length >= 2, onClick = { retry++ }) { Text("Retry") } })
}
