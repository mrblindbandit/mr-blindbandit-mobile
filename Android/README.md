# Mr. Blindbandit Android — v1.3

Native Android companion for mrblindbandit.net, built with Kotlin, Jetpack Compose, Android System WebView, Material 3, and a Firebase Cloud Messaging scaffold.

## Core behavior

- Native Compose shell and bottom navigation.
- Android System WebView for first-party site surfaces.
- TalkBack-first controls and an unmodified WebView accessibility tree so semantic website content remains available to screen readers.
- Branded pulsing logo and waveform while pages load, with a Reduce Motion setting.
- Camera and microphone runtime permissions granted only for approved HTTPS Mr. Blindbandit origins.
- Native Android file/document picker for HTML file upload controls.
- External sites open outside the embedded first-party browser.
- HTTPS-only first-party policy and mixed-content blocking.
- Deep-link routing for mrblindbandit.net.
- Firebase Cloud Messaging service scaffold and Android notification channel.
- Advanced settings for text zoom, page-load announcements, motion, media autoplay, third-party cookies, permissions, storage, and screen-awake behavior.
- Version 1.3.0 / versionCode 3 is visible in Settings.

## Push notifications

The FCM client framework is present, but production remote delivery intentionally remains unconfigured in source control. Add the production Firebase configuration (`google-services.json`) and wire the resulting FCM token to the authenticated Mr. Blindbandit server-side device-registration endpoint. Never embed reusable backend secrets in the APK.

## Accessibility acceptance targets

Test with TalkBack enabled, large font and display scaling, high-contrast text where available, Switch Access / keyboard navigation, orientation changes, reduced animation settings, and web content at 200% text zoom. Every native action must have a readable label, loading state must be announced without trapping focus, and WebView must retain its native accessibility tree.

## CI testing

GitHub Actions runs Android unit tests, Android Lint, and a full debug APK build on every pull request and main-branch push. The workflow uploads the APK and lint report as artifacts.
