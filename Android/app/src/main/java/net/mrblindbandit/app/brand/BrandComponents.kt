package net.mrblindbandit.app.brand

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import net.mrblindbandit.app.R

private val BrandGold = Color(0xFFFFD54F)

@Composable
fun BlindbanditLogo(size: Dp, modifier: Modifier = Modifier) {
    Image(
        painter = painterResource(id = R.drawable.logo_blindbandit_gold),
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = modifier
            .size(size)
            .clip(RoundedCornerShape(size * 0.18f))
    )
}

@Composable
fun SpinningBrandLogo(size: Dp, reduceMotion: Boolean, modifier: Modifier = Modifier) {
    val rotation = if (reduceMotion) {
        0f
    } else {
        val t = rememberInfiniteTransition(label = "spin")
        val value by t.animateFloat(0f, 360f, infiniteRepeatable(tween(2400, easing = LinearEasing)), label = "spinV")
        value
    }
    BlindbanditLogo(
        size = size,
        modifier = modifier
            .rotate(rotation)
            .semantics { contentDescription = "Blindbandit Records logo" }
    )
}

@Composable
fun PulsingBrandLogo(size: Dp, reduceMotion: Boolean) {
    if (reduceMotion) {
        BlindbanditLogo(size)
        return
    }
    val t = rememberInfiniteTransition(label = "pulse")
    val scale by t.animateFloat(0.94f, 1.08f, infiniteRepeatable(tween(850), RepeatMode.Reverse), label = "ps")
    val alpha by t.animateFloat(0.76f, 1f, infiniteRepeatable(tween(850), RepeatMode.Reverse), label = "pa")
    Box(Modifier.scale(scale).alpha(alpha)) { BlindbanditLogo(size) }
}

@Composable
fun WaveformLoader(reduceMotion: Boolean) {
    val bars = listOf(14, 28, 40, 22, 46, 30, 18)
    val t = rememberInfiniteTransition(label = "wave")
    Row(
        Modifier.height(52.dp).semantics { contentDescription = "Loading" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        bars.forEachIndexed { index, maxHeight ->
            val animated by t.animateFloat(
                initialValue = if (reduceMotion) maxHeight.toFloat() else 8f,
                targetValue = maxHeight.toFloat(),
                animationSpec = infiniteRepeatable(tween(480 + index * 45), RepeatMode.Reverse),
                label = "bar$index"
            )
            Box(
                Modifier
                    .width(4.dp)
                    .height((if (reduceMotion) maxHeight.toFloat() else animated).dp)
                    .background(BrandGold, RoundedCornerShape(4.dp))
            )
        }
    }
}

@Composable
fun BrandProgressOverlay(title: String, progress: Int?, reduceMotion: Boolean) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Card(
            Modifier
                .padding(24.dp)
                .semantics {
                    liveRegion = LiveRegionMode.Polite
                    contentDescription = if (progress != null) "$title, $progress percent" else title
                },
            shape = RoundedCornerShape(24.dp)
        ) {
            Column(
                Modifier.padding(26.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                SpinningBrandLogo(88.dp, reduceMotion)
                WaveformLoader(reduceMotion)
                Text(title, fontWeight = FontWeight.SemiBold)
                if (progress != null) {
                    LinearProgressIndicator(progress = { progress / 100f }, color = BrandGold)
                    Text("$progress percent", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
fun GoldFallbackMark(size: Dp) {
    Box(Modifier.size(size).background(Color.Black, CircleShape), contentAlignment = Alignment.Center) {
        Text("♪", color = BrandGold, fontSize = (size.value * 0.46f).sp, fontWeight = FontWeight.Bold)
    }
}
