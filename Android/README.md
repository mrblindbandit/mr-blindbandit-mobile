# Mr. Blindbandit Android — v1.6

Native Android app built with Kotlin, Jetpack Compose, Clerk authentication, server-authorized LiveKit communications, Listen music services, creator tools, Android System WebView, Material 3, and Firebase Cloud Messaging integration.

## Setup

1. Copy `local.properties.example` to `local.properties` (gitignored).
2. Set `sdk.dir` plus the client-safe `CLERK_PUBLISHABLE_KEY`, `LIVEKIT_URL`, and `GOOGLE_OAUTH_CLIENT_ID` values when overriding production defaults locally.
3. Never put Clerk secret keys, LiveKit API keys/secrets, Google client secrets, signing credentials, or other reusable server credentials in the APK.
4. LiveKit participant tokens are obtained at runtime from the authenticated Blindbandit API.

```bash
gradle -p Android testDebugUnitTest --stacktrace
gradle -p Android lintDebug --stacktrace
gradle -p Android assembleDebug --stacktrace
gradle -p Android bundleRelease --stacktrace
```

## Release metadata

- Version name: `1.6.0`
- Version code: `6`
- Minimum SDK: `26`
- Target SDK: `36`

## Compliance

Account deletion, Privacy Policy, Terms, permissions, and accessibility controls are exposed in the app. See `../RELEASING.md` and `../Config/STORE_COMPLIANCE.md` for the release checklist and declaration notes.
