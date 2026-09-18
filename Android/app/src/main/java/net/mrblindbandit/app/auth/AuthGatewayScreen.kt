package net.mrblindbandit.app.auth

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import net.mrblindbandit.app.brand.SpinningBrandLogo
import net.mrblindbandit.app.config.AppConfig

@Composable
fun AuthGatewayScreen(auth: ClerkAuthService, reduceMotion: Boolean) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var mode by remember { mutableStateOf("landing") }

    LaunchedEffect(Unit) { auth.configure() }

    Column(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Color.Black, Color(0xFF1E1E1E))))
            .verticalScroll(rememberScrollState())
            .padding(22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Spacer(Modifier.height(24.dp))
        SpinningBrandLogo(120.dp, reduceMotion)
        Text("Mr. Blind Bandit", fontSize = 32.sp, fontWeight = FontWeight.Bold, color = Color.White,
            modifier = Modifier.semantics { heading() })
        Text("Music · Creator Tools · Calls · Blindbandit Records", color = Color.White.copy(alpha = 0.78f), textAlign = TextAlign.Center)
        Text("Sign in to unlock your studio, calls, and messages.", color = Color.White.copy(alpha = 0.65f), textAlign = TextAlign.Center)

        when (mode) {
            "landing" -> {
                Button(
                    onClick = { scope.launch { auth.continueWithGoogle() } },
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black),
                    enabled = !auth.busy,
                    shape = RoundedCornerShape(14.dp)
                ) { Text("Continue with Google", fontWeight = FontWeight.SemiBold) }

                OutlinedButton(
                    onClick = { mode = "email" },
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    enabled = !auth.busy,
                    shape = RoundedCornerShape(14.dp)
                ) { Text("Continue with email", color = Color(0xFFFFD54F), fontWeight = FontWeight.SemiBold) }

                TextButton(onClick = { mode = "signup" }) {
                    Text("Create an account", color = Color(0xFFFFD54F))
                }
            }
            "email", "signup" -> {
                val signUp = mode == "signup"
                Text(if (signUp) "Create your account" else "Welcome back", color = Color.White, fontWeight = FontWeight.Bold,
                    modifier = Modifier.fillMaxWidth().semantics { heading() })
                if (signUp) {
                    OutlinedTextField(auth.nameDraft, { auth.nameDraft = it }, label = { Text("Display name") },
                        modifier = Modifier.fillMaxWidth(), singleLine = true)
                }
                OutlinedTextField(auth.emailDraft, { auth.emailDraft = it }, label = { Text("Email") },
                    modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(auth.passwordDraft, { auth.passwordDraft = it }, label = { Text("Password") },
                    modifier = Modifier.fillMaxWidth(), singleLine = true,
                    visualTransformation = PasswordVisualTransformation())
                Button(
                    onClick = { scope.launch { auth.continueWithEmail(signUp) } },
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFD54F), contentColor = Color.Black),
                    enabled = !auth.busy
                ) { Text(if (signUp) "Create account" else "Sign in", fontWeight = FontWeight.Bold) }
                TextButton(onClick = { mode = if (signUp) "email" else "signup" }) {
                    Text(if (signUp) "Already have an account? Sign in" else "Need an account? Create one", color = Color.White.copy(0.8f))
                }
                TextButton(onClick = { mode = "landing" }) { Text("Back", color = Color(0xFFFFD54F)) }
            }
        }

        if (auth.busy) CircularProgressIndicator(color = Color(0xFFFFD54F))
        if (auth.statusMessage.isNotBlank()) {
            Text(auth.statusMessage, color = Color(0xFFFFD54F), textAlign = TextAlign.Center)
        }
        if (!AppConfig.isClerkConfigured) {
            Text("Clerk publishable key missing — set local.properties for production.", color = Color(0xFFFF9800), textAlign = TextAlign.Center)
        }

        Text("By continuing you agree to the Terms of Use and acknowledge the Privacy Policy.",
            color = Color.White.copy(0.45f), fontSize = 11.sp, textAlign = TextAlign.Center)
        TextButton(onClick = {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://mrblindbandit.net/privacy/")))
        }) { Text("Privacy Policy", color = Color(0xFFFFD54F)) }
        TextButton(onClick = {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://mrblindbandit.net/terms/")))
        }) { Text("Terms of Use", color = Color(0xFFFFD54F)) }
        Spacer(Modifier.height(24.dp))
    }
}
