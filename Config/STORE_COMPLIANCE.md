# Store compliance — Mr. Blindbandit Mobile 1.6

This file documents the source-side release configuration. Store-console declarations, signing, screenshots, review notes, and final physical-device verification must still match the actual production services and behavior at submission time.

## Release metadata

| Platform | Version | Build/code | Minimum | Target |
|---|---:|---:|---:|---:|
| iOS | 1.6 | 6 | iOS 17 | Current Xcode SDK |
| Android | 1.6.0 | 6 | API 26 | API 36 |

## Data handled by the app

| Data | Purpose | Linked to identity | Notes |
|---|---|---|---|
| Clerk account data (email/name/user id) | Authentication and account | Yes | Client contains only the Clerk publishable key |
| OAuth identity/token state | Authentication | Yes | Managed through Clerk and OS/web authentication flows |
| Call signaling and LiveKit room grants | Voice/video calling | Yes during session | Room grants are short-lived and minted server-side |
| Audio/video streams | User-started calls | Session | Transported through LiveKit when the user joins a call |
| Message text and conversation metadata | Messaging | Yes | Sent through authenticated Blindbandit API endpoints |
| User-selected media/files | Creator tools, attachments, profile/media actions | When user submits it | User-initiated only |
| APNs / FCM device token | Notifications | Yes when registered | Used only when push is enabled/configured |
| First-party WebView cookies/session data | Website session | Yes when signed in | Restricted to approved first-party web surfaces |
| Crash/diagnostic provider data | None added by this app by default | — | Update declarations before adding a diagnostics SDK |

Final Apple privacy nutrition labels and Google Play Data safety answers must reflect the production backend, Clerk, LiveKit, push configuration, and any future SDKs actually enabled in the submitted build.

## Account deletion

Settings exposes in-app account deletion. The v1.6 client authenticates the request, calls the Blindbandit production deletion flow for associated app data, then deletes/signs out the authentication account as implemented by the platform auth service. A failed deletion must surface an error instead of claiming success.

The production API endpoint must remain deployed and must delete data according to the published Privacy Policy and applicable retention requirements.

## Sign in with Apple

The iOS source includes the Sign in with Apple entitlement and `AppConfig.enableSignInWithApple` is enabled. Google and email sign-in are also supported. Keep Sign in with Apple available in the submitted iOS build whenever required by App Store Review Guideline 4.8.

Phone OTP remains disabled until SMS/OTP is deliberately enabled in the production Clerk instance.

## LiveKit and communications security

- `LIVEKIT_URL` is a client-safe endpoint.
- LiveKit API key/secret stay server-side.
- Mobile obtains short-lived participant grants from the authenticated Blindbandit API.
- No reusable LiveKit participant token or test-token fallback is shipped in v1.6.
- Calls/messages require an authenticated Clerk session through the production communications layer.

## iOS privacy manifest

`App/PrivacyInfo.xcprivacy` is included in the iOS target. Keep the declared collected-data categories and required-reason APIs synchronized with the shipping code and third-party SDK manifests.

## Permissions

- Camera — video calls and user-started media/creator actions
- Microphone — voice/video calls and user-started audio capture
- Photo library/files — user-started import/export and media actions
- Bluetooth — compatible call audio devices
- Notifications — optional calls/messages/updates

Permission prompts must describe the actual user-facing purpose and should be requested in context or through the first-launch onboarding flow already implemented by the app.

## Network and browser policy

- Production API: `https://api.mrblindbandit.net`
- Public site: `https://mrblindbandit.net`
- Trusted in-app web content is HTTPS-only and restricted to approved first-party hosts.
- Cleartext HTTP and look-alike domains are rejected by the first-party URL policy.

## Encryption

The client relies on standard platform TLS/HTTPS and LiveKit transport security. It does not embed reusable cryptographic server secrets.

## Public policy/support links

- Privacy Policy: https://mrblindbandit.net/privacy
- Terms: https://mrblindbandit.net/terms
- Support: business@mrblindbandit.net

## Submission checks outside source control

Before pressing Submit in either store, verify the signed production build on physical devices, complete Apple privacy / Google Data safety forms from the actual deployed behavior, provide reviewer credentials or review instructions if required, confirm account deletion works end-to-end against production, configure production push credentials if push is advertised, and upload store screenshots/metadata that exactly match v1.6.
