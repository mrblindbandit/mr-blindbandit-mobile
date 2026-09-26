# Store compliance: Mr. Blindbandit Mobile 1.7

This file maps every App Store Review Guideline and Google Play policy that applies to the app to
the code that satisfies it, and lists what only the owner can do in the store consoles.

## Release metadata

| | iOS | Android |
|---|---|---|
| Identifier | `net.mrblindbandit.privateapp` | `net.mrblindbandit.app` |
| Version | 1.7 (7) | 1.7.0 (7) |
| Minimum OS | iOS 17, iPhone only | Android 8.0 (API 26) |
| Target | iOS 17+ SDK from current Xcode | targetSdk 36 |

## Sign-in (Apple 4.8, Play User Data)

- Clerk production instance `clerk.mrblindbandit.net`: email and password, Google, and Sign in with Apple (iOS).
- Sign in with Apple is shown on iOS because Google sign-in is offered (Guideline 4.8). **The Apple
  social connection must be enabled in Clerk**, or the button returns an error.
- iOS entitlements: `com.apple.developer.applesignin`, `aps-environment`, and associated domain
  `webcredentials:clerk.mrblindbandit.net`.

## User-generated content (Apple 1.2, Play UGC policy)

- In every conversation, the Safety menu lets you **report** a person, and long-press or the
  VoiceOver/TalkBack actions let you **report a message**. Both call `POST /v1/social/reports`.
- **Block**, with confirmation: `POST /v1/social/profiles/{handle}/block`.
- Only signed-in members can message or call. The terms of use are linked on the sign-in screen.
- Owner obligation: review reports promptly (Apple expects action within 24 hours) and remove
  abusive users.

## Account deletion (Apple 5.1.1(v), Play account deletion policy)

- Settings > Account & profile > Delete account. Two steps: an explanation, then typing DELETE.
- The app calls `POST /v1/privacy/delete` (server data), then deletes the Clerk user, then erases
  local settings and web data.
- Web deletion link for the Play Console Data safety form: https://mrblindbandit.net/account/delete

## Permissions (Apple 5.1.1, Play permissions policy)

| Permission | When it is requested |
|---|---|
| Microphone | When you start or join a call, or start a recording in the creator tools |
| Camera | When you start or join a video call |
| Notifications | Only from the Home card or Settings, never at launch |
| Face ID | When the optional app lock is on (Settings > Privacy & data) |

- Removed: the mass permission request at first launch, the unused Photos read/write permissions,
  and the unused Bluetooth usage strings (iOS).
- Android `POST_NOTIFICATIONS` (API 33+) is requested only when you tap "Turn on notifications". If the dialog is no longer available, the app opens the system notification settings instead.
- Android `BLUETOOTH_CONNECT` stays in the manifest for LiveKit headset routing. It is never
  requested at launch.

## Data handled (App Privacy labels / Play Data safety)

| Data | Purpose | Linked to user | Tracking |
|---|---|---|---|
| Name, email (Clerk) | Account | Yes | No |
| Username / profile | App functionality | Yes | No |
| Messages | App functionality | Yes | No |
| Call metadata (not audio/video content) | App functionality | Yes | No |
| Push token, installation ID (APNs; Firebase Cloud Messaging token + Firebase installation ID on Android) | Notifications | Yes | No |
| Settings | Stored only on the device | No | No |

There are no ads, no analytics SDKs and no tracking. Call media is peer-to-server over encrypted
LiveKit WebRTC and is not recorded by the app.

## Privacy manifest

`App/PrivacyInfo.xcprivacy` declares no tracking, the collected data types above, and the
required-reason APIs UserDefaults (CA92.1) and file timestamps (C617.1).

## Backups (Android)

`allowBackup=false` plus `data_extraction_rules.xml` excludes all app data from cloud backup and
device transfer, so sign-in sessions are never restored onto another device.

## Encryption

HTTPS/TLS and WebRTC only (standard, exempt). `ITSAppUsesNonExemptEncryption = NO` is set.

## Placeholder content gate

`scripts/check-placeholders.sh` fails CI on placeholder, fake or unfinished text in `App/` and
`Android/app/src/main` (Apple 2.1 app completeness, 2.3 accurate metadata).

## Links

- Privacy: https://mrblindbandit.net/privacy/
- Terms: https://mrblindbandit.net/terms/
- Support: https://mrblindbandit.net/support/ and business@mrblindbandit.net
- Accessibility: https://mrblindbandit.net/accessibility/
- Account deletion: https://mrblindbandit.net/account/delete

## Owner-only steps

See `RELEASING.md` for the full checklist: the Clerk dashboard, App Store Connect, Play Console,
Firebase, APNs, and the GitHub signing secrets.
