# Mr. Blindbandit Android — v1.5

Native Android app: Kotlin, Jetpack Compose, Clerk auth, LiveKit Connect, Listen music services, creator toolkit, Android System WebView, Material 3, FCM scaffold.

## Setup

1. Copy `local.properties.example` → `local.properties` (gitignored).
2. Set `sdk.dir`, `CLERK_PUBLISHABLE_KEY`, `LIVEKIT_URL` (client-safe only).
3. Never put Clerk secret / LiveKit API secret / Google client secret in the APK.

```bash
gradle -p Android testDebugUnitTest lintDebug assembleDebug
```

## Compliance

Account deletion, Privacy Policy, and Terms are in Settings / More. See `../RELEASING.md` and `../Config/STORE_COMPLIANCE.md`.
