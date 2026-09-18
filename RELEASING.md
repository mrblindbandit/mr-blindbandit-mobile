# Release Process — Mr. Blindbandit Mobile

The version shown in the apps, source configuration, GitHub Actions, documentation, pull requests, and validation artifacts must agree.

## Canonical release version

Current source release: **1.6**

- iOS: `MARKETING_VERSION = 1.6`
- iOS build: `CURRENT_PROJECT_VERSION = 6`
- Android: `versionName = 1.6.0`
- Android build: `versionCode = 6`
- Android target SDK: `36`

## Repository-side release gates

These items should be complete before the release branch is merged:

- [x] iOS and Android version metadata updated to v1.6 / build-code 6
- [x] CI artifact names updated to v1.6
- [x] iOS privacy manifest included
- [x] Sign in with Apple entitlement and source-side feature enablement present
- [x] In-app account deletion source flow present
- [x] Production communications path uses authenticated server-issued LiveKit grants
- [x] Reusable/test LiveKit token fallback removed from the v1.6 shipping source
- [x] Android targets API 36
- [x] README, integration notes, secrets examples, and compliance documentation updated for v1.6
- [ ] Latest iOS unit-test + unsigned-IPA workflow is green
- [ ] Latest Android unit-test + lint + debug APK + unsigned AAB workflow is green

The final two boxes are CI results, not manual assertions. Do not merge a red release branch.

## Apple App Store submission checklist

Source-side items:

- [x] Privacy Policy link available in app/release docs: `https://mrblindbandit.net/privacy`
- [x] Terms link available in app/release docs: `https://mrblindbandit.net/terms`
- [x] Sign in with Apple source entitlement is present alongside Google/email authentication
- [x] Account deletion is exposed in-app
- [x] Camera, microphone, photo/file, and Bluetooth purpose strings are defined
- [x] `PrivacyInfo.xcprivacy` is included in the iOS target

Submission/device items that cannot be completed by source control alone:

- [ ] Create a properly signed/provisioned Release archive with the production Apple team/profile
- [ ] Verify Google, Apple, and email sign-in on a physical production-signed build
- [ ] Verify account deletion end-to-end against the deployed production API
- [ ] Verify voice/video calls, messages, mute/camera controls, and deep links on physical devices
- [ ] Run VoiceOver, Dynamic Type, reduced-motion, and permission-prompt smoke tests
- [ ] Complete App Privacy declarations from the actual deployed data behavior and enabled SDKs
- [ ] Review export-compliance answers against the encryption actually used by the submitted build and current Apple guidance
- [ ] Complete age rating, category, support URL, review contact, screenshots, and metadata
- [ ] Provide review notes/credentials or a review path if authentication blocks reviewers
- [ ] Confirm any advertised remote notifications are backed by production APNs configuration
- [ ] Upload through App Store Connect/TestFlight and pass Apple validation before submission

## Google Play submission checklist

Source-side items:

- [x] `targetSdk = 36`
- [x] HTTPS-first first-party URL policy
- [x] In-app account deletion path
- [x] Camera/microphone/notification permissions are requested through native flows
- [x] CI validates `bundleRelease` in addition to tests, lint, and debug APK assembly

Submission/device items:

- [ ] Create/sign the production AAB using the intended Play signing/release process
- [ ] Verify Clerk sign-in, deletion, calls, messages, notifications, and deep links on physical Android devices
- [ ] Run TalkBack, large-text/display-scaling, reduced-motion, and permission-prompt smoke tests
- [ ] Complete Google Play Data safety answers from the actual production services and SDKs
- [ ] Complete account-deletion URL/details required by Play Console
- [ ] Complete content rating, app access/reviewer instructions, screenshots, feature graphic, support/contact, and release notes
- [ ] Confirm any advertised remote notifications are backed by the production Firebase/FCM configuration
- [ ] Upload to an internal/closed test track and pass Play pre-launch / policy checks before production rollout

## CI validation commands

### iOS

```bash
xcodegen generate
xcodebuild -project Blindbandit.xcodeproj -scheme Blindbandit -destination 'platform=iOS Simulator,id=<device>' test
bash build-unsigned.sh
```

### Android

```bash
gradle -p Android testDebugUnitTest --stacktrace
gradle -p Android lintDebug --stacktrace
gradle -p Android assembleDebug --stacktrace
gradle -p Android bundleRelease --stacktrace
```

## Artifact naming

- iOS workflow artifact: `Mr-Blindbandit-iOS-v1.6-unsigned-IPA`
- iOS file: `Mr-Blindbandit-iOS-v1.6-unsigned.ipa`
- Android debug artifact: `Mr-Blindbandit-Android-v1.6-debug-APK`
- Android debug file: `Mr-Blindbandit-Android-v1.6-debug.apk`
- Android store-validation artifact: `Mr-Blindbandit-Android-v1.6-unsigned-AAB`

These are CI validation artifacts. They are not proof of App Store or Play Store signing/submission.

## Security rule

Never commit signing keys, Apple private keys, Firebase service-account/server credentials, Clerk secret keys, LiveKit API keys/secrets, Google OAuth client secrets, production keystores, or other long-lived private credentials. Mobile binaries should contain only client-safe identifiers/endpoints and short-lived user/session credentials obtained at runtime.
