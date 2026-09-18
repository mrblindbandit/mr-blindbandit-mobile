# Store compliance — Mr. Blindbandit Mobile 1.5

## Data collected (Play Data safety / Apple privacy nutrition)

| Data | Purpose | Linked to identity | Notes |
|---|---|---|---|
| Clerk email / name / user id | Account auth | Yes | Publishable key in app; secrets server-side |
| Apple / Google sign-in tokens | Auth | Yes | Via Clerk; Sign in with Apple on iOS |
| LiveKit audio/video | Calls | Session | Ephemeral while connected; tokens short-lived |
| Voice note audio files | Messaging | On device / chat | User-initiated |
| FCM / APNs device tokens | Notifications | Yes when enabled | Opt-in |
| WebView cookies | First-party site session | Yes when signed into site | First-party hosts only |
| Crash / diagnostics | None by default | — | Add only if a provider is introduced |

## Account deletion

Settings → Account → Delete account requests deletion, signs the user out, and opens `https://mrblindbandit.net/account` for confirmation. Production must call Clerk user deletion + server data purge.

## Sign in with Apple

Required because Google (third-party) login is offered on iOS (Guideline 4.8). Entitlement `com.apple.developer.applesignin` is present.

## Encryption

App uses HTTPS and LiveKit’s standard transport encryption. No custom cryptographic routines beyond OS/TLS.
