# Clerk + LiveKit integration notes (flagship 1.5)

## Clerk
- iOS: SPM `https://github.com/clerk/clerk-ios` → products `ClerkKit` (+ optional `ClerkKitUI`).
  Configure once: `Clerk.configure(publishableKey:)`, inject `Clerk.shared`.
  Natural CTAs: OAuth Google + email/password via ClerkKit or ClerkKitUI `AuthView`.
  Publishable key only in the client; secret key stays server-side.
- Android: `com.clerk:clerk-android-api` / `clerk-android-ui`.
  `Clerk.initialize(context, publishableKey)` in Application.onCreate.
  Mirror Google + email CTAs; session gates the main shell.

## LiveKit
- iOS: SPM LiveKit client; connect with **server-minted short-lived tokens** (never ship API secret).
- Android: `io.livekit:livekit-android` + JitPack for audio switch deps.
- Permissions: mic (voice/notes), camera (video), Bluetooth for headsets; justify in Info.plist / Play declarations.
- Data channel / text streams for chat; local AAC/M4A for voice notes then publish as data or shared attachment URL.

## Token pattern
Mobile requests `POST /v1/livekit/token` with Clerk session → server returns JWT for room join.
Scaffold token in gitignored Secrets.local / local.properties for device QA only.
