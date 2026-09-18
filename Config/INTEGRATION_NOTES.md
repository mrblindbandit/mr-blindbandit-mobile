# Clerk + LiveKit integration notes (flagship 1.5)

## CI / toolchain pins (Xcode 16.4)
- **iOS Clerk SPM**: **exactVersion 1.1.5** (`clerk-ios`). `1.2.0+` declares Swift tools **6.2.0**, which Xcode 16.4 cannot resolve. LiveKit SPM stays `from: 2.6.0`.
- **Android (option B for current CI)**: keep AGP **8.7.3** / `compileSdk = 35` / Gradle **8.9**. Force `androidx.browser:browser:1.8.0` and `okhttp(-android):5.3.2` so Clerk `1.0.33` does not pull AARs that require compileSdk 36 + AGP ≥ 8.9.1.
- **Preferred later (option A)**: AGP **8.9.3**, `compileSdk = 36`, Gradle **8.11.1+**. `ubuntu-24.04` runners already include `android-36`; workflow edit needs GitHub **`workflow`** OAuth scope.

## Clerk
- iOS: SPM `https://github.com/clerk/clerk-ios` **exactVersion 1.1.5** → products `ClerkKit` (+ optional `ClerkKitUI`).
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
