# Store compliance — Mr. Blindbandit Mobile 1.5

## Data collected (Play Data safety / Apple privacy nutrition)

| Data | Purpose | Linked to identity | Notes |
|---|---|---|---|
| Clerk email / name / user id | Account auth | Yes | Publishable key in app; secrets server-side |
| Google sign-in tokens | Auth | Yes | Via Clerk (existing mrblindbandit.net Clerk app) |
| LiveKit audio/video | Calls | Session | Ephemeral while connected; tokens short-lived |
| DM text / attachments / voice notes | Messaging | On device + session | User-initiated; data-channel payloads |
| FCM / APNs device tokens | Notifications | Yes when enabled | Opt-in |
| WebView cookies | First-party site session | Yes when signed into site | First-party hosts only |
| Crash / diagnostics | None by default | — | Add only if a provider is introduced |

## Account deletion

Settings → Account → Delete account requests deletion, signs the user out, and opens `https://mrblindbandit.net/account` for confirmation. Production must call Clerk user deletion + server data purge.

## Sign in with Apple

**Disabled for 1.5** (`AppConfig.enableSignInWithApple = false`). No Apple Developer account yet — Apple button is hidden. Primary CTAs: **Continue with Google** and **Continue with email**. Phone OTP remains behind `enablePhoneOTP` (default off; enable only if Clerk SMS is available on the plan). Before App Store submission with Google login, enable Sign in with Apple + entitlement per Guideline 4.8.

## Auth CTAs (shipping)

1. Continue with Google  
2. Continue with email  
3. Create an account  
4. (Optional later) Phone OTP / Sign in with Apple via feature flags  

## Permissions (usage strings)

- Camera — video calls, creator tools, profile media, user-started uploads  
- Microphone — voice calls, voice notes, recording, creator tools  
- Photo library — creator tools and uploads the user starts  
- Bluetooth — LiveKit call headsets  
- Notifications — optional push  

## Encryption

App uses HTTPS and LiveKit’s standard transport encryption. No custom cryptographic routines beyond OS/TLS.

## LiveKit tokens

Production: `POST /v1/livekit/token` with Clerk session → short-lived room JWT.  
QA scaffold: gitignored `Secrets.local.swift` / `Android/local.properties` `LIVEKIT_SCAFFOLD_TOKEN` only — never ship API secrets in the client. UI labels scaffold use as **TEST SCAFFOLD**.

## Sounds & haptics

Client-side UI SFX and haptics are optional (Settings toggles, default on). Silent switch / system haptic settings are respected. No audio is uploaded unless the user sends a voice note or places a call.


Privacy Policy: https://mrblindbandit.net/privacy
Terms: https://mrblindbandit.net/terms
Support: mailto:business@mrblindbandit.net
