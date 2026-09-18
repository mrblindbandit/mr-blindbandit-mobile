# Clerk + LiveKit integration notes — v1.6

## Toolchain

- **iOS:** Xcode 16.4, Clerk iOS `1.1.5` (exact), LiveKit Swift from `2.6.0`.
- **Android:** AGP `8.10.1`, Gradle `8.11.1`, compile/target SDK `36`, Clerk Android `1.0.33`, LiveKit Android `2.18.3`.
- CI installs Android platform 36 and validates both debug and release-bundle compilation.

## Authentication

### iOS

- ClerkKit is configured with the client-safe production publishable key.
- Supported sign-in paths: Google, Apple, and email.
- Sign in with Apple entitlement is included in `App/Blindbandit.entitlements`.
- Phone OTP remains disabled until SMS/OTP is enabled for the production Clerk instance.

### Android

- Clerk is initialized with the client-safe publishable key.
- Google and email authentication use the active Clerk session.
- Phone OTP remains disabled until the production Clerk instance supports it.

Reusable Clerk secrets remain server-side.

## Production communications

Both apps use the authenticated Blindbandit API for call setup and messaging. The client presents the active Clerk session token to `https://api.mrblindbandit.net`; the server authorizes the request and returns short-lived LiveKit room grants when required.

The shipping mobile code does **not** contain a reusable LiveKit participant token, API secret, or fallback test token.

Key responsibilities:

- API authorization: Clerk bearer token
- Call setup: authenticated mobile-native call endpoint
- LiveKit room grant: short-lived server-minted JWT
- Messages/conversations: authenticated Blindbandit API
- Audio/video transport: LiveKit
- Push routing: APNs / FCM once production provider credentials are configured server-side

## Permissions

- Microphone: calls and user-started audio capture
- Camera: video calls and user-started creator/media workflows
- Photos/files: user-started import/export workflows
- Bluetooth: compatible call audio devices
- Notifications: optional call/message notifications

Permissions are requested through native operating-system flows and described in the platform manifests/usage strings.

## OAuth/deep links

- Hosted Clerk OAuth callback: `https://clerk.mrblindbandit.net/v1/oauth_callback`
- Mobile callback: `blindbandit://oauth-callback`
- First-party web/API hosts are restricted by the app URL policy.

## Security rule

Only identifiers and public endpoints belong in mobile configuration. `CLERK_SECRET_KEY`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, OAuth client secrets, APNs private keys, Firebase service-account credentials, signing keys, and similar reusable credentials stay on trusted server/build infrastructure.
