# Release process: Mr. Blindbandit Mobile

## Version

iOS 1.7 (build 7) and Android 1.7.0 (versionCode 7). Bump `project.yml` (`MARKETING_VERSION`,
`CURRENT_PROJECT_VERSION`), `App/AppConfig.swift`, `Android/app/build.gradle.kts` and
`Android/.../config/AppConfig.kt` together.

## CI gates (every pull request)

- **Android** (`.github/workflows/android.yml`, Ubuntu): placeholder check, unit tests (Robolectric),
  lint, debug APK, release AAB (signed when secrets exist), and instrumented tests on an API 34
  emulator. The APK and AAB are uploaded as artifacts.
- **iOS** (`.github/workflows/ios.yml`, macos-latest): placeholder check, XcodeGen, simulator
  build and unit tests, and an unsigned device build. A signed App Store archive runs only when
  signing secrets exist.

## GitHub secrets (Settings > Secrets and variables > Actions)

| Secret | Used for |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload.jks`: the Play **upload** keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |
| `IOS_CERTIFICATE_P12_BASE64` | Apple Distribution certificate + private key (.p12), base64 |
| `IOS_CERTIFICATE_PASSWORD` | .p12 password |
| `IOS_PROVISIONING_PROFILE_BASE64` | App Store provisioning profile for `net.mrblindbandit.privateapp`, base64 |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `KEYCHAIN_PASSWORD` | Optional; any random string |

For local Android release builds, put `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` in `Android/local.properties` (gitignored), or
export them as environment variables. Never commit keys.

## Clerk dashboard (production instance clerk.mrblindbandit.net)

1. **Native applications > iOS:** App ID Prefix = your Apple Team ID, Bundle ID = `net.mrblindbandit.privateapp`.
2. **Native applications > Android:** package `net.mrblindbandit.app` plus the SHA-256
   fingerprints of the upload key **and** the Play App Signing key (Play Console > App integrity).
3. **Allowlisted redirect URLs (mobile SSO):** `net.mrblindbandit.privateapp://callback`,
   `clerk://net.mrblindbandit.app.callback`, `clerk://net.mrblindbandit.app.oauth`.
4. **SSO connections > Apple:** enable it with custom credentials (Services ID, Team ID, Key ID,
   .p8 private key) and add the bundle ID `net.mrblindbandit.privateapp` for native sign-in.
5. Keep Google enabled with its production credentials.

## Apple App Store checklist

- App ID `net.mrblindbandit.privateapp` with Sign in with Apple, Push Notifications and Associated Domains.
- APNs key uploaded to the Blindbandit server for push delivery.
- App Privacy answers from `Config/STORE_COMPLIANCE.md`.
- A review demo account (email and password) in App Review Information, plus a second account to test calling.
- iPhone screenshots at 6.9" and 6.5".
- Privacy Policy URL https://mrblindbandit.net/privacy/ and Support URL https://mrblindbandit.net/support/.

## Google Play checklist

- Enroll in Play App Signing and upload the AAB built by CI with the upload key.
- Data safety form from `Config/STORE_COMPLIANCE.md`. Account deletion URL: https://mrblindbandit.net/account/delete
- Content rating questionnaire (the app has user-to-user communication).
- Target audience 18+ or 13+ as appropriate, not designed for children.
- Firebase (project `mr-blindbandit`): `Android/app/google-services.json` is committed. It is a public client
  config for `net.mrblindbandit.app`, and the `com.google.gms.google-services` plugin applies it. The Firebase
  **service-account key is a secret**. It belongs only in the server's secret store, never in this repo
  (`*firebase-adminsdk*.json` is gitignored).
- Deploy `https://mrblindbandit.net/.well-known/assetlinks.json` only if verified App Links are wanted.

## Artifacts

- `Mr-Blindbandit-Android-v<version>-debug.apk`
- `Mr-Blindbandit-Android-v<version>-signed.aab` or `-unsigned.aab`
- `Mr-Blindbandit-iOS-v<version>-unsigned.ipa`, and the App Store IPA when signing secrets exist.
