package net.mrblindbandit.app.social

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** TalkBack-announced verification mark shown next to handles on profiles, Bites, and people rows. */
@Composable
fun VerifiedBadge(size: Dp = 16.dp, modifier: Modifier = Modifier) {
    Icon(
        imageVector = Icons.Default.Verified,
        contentDescription = "Verified account",
        tint = MaterialTheme.colorScheme.primary,
        modifier = modifier.size(size).semantics { contentDescription = "Verified account" },
    )
}
