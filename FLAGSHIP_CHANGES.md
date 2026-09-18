# Flagship 1.5 — file manifest

Branch target: `flagship/1.5-clerk-livekit`

## Summary

App Store / Play–ready upgrade: Clerk auth (Apple / Google / email), LiveKit voice/video/chat/voice notes, Listen music services, Musician Studio, branded gold loaders, accessibility, account deletion, privacy/terms, version **1.5 / build 5**.

## Secrets (gitignored — do not commit)

- `App/Secrets.local.swift`
- `Android/local.properties`
- Any `google-services.json` / `GoogleService-Info.plist`

Use examples instead:

- `Config/Secrets.example`
- `App/Secrets.local.swift.example`
- `Android/local.properties.example`

## New / changed paths

### Config & docs
Config/INTEGRATION_NOTES.md
Config/STORE_COMPLIANCE.md
Config/Secrets.example
brand/logo-blindbandit-records-gold.jpeg
brand/logo-square-1024.png
FLAGSHIP_CHANGES.md
push-via-api.sh
.gitignore
CHANGELOG.md
README.md
RELEASING.md
project.yml

### iOS (App/)
App/AdvancedSettings.swift
App/AppConfig.swift
App/AuthViews.swift
App/Blindbandit.entitlements
App/BlindbanditApp.swift
App/BrandVisuals.swift
App/Browser.swift
App/ClerkAuthService.swift
App/ConnectHub.swift
App/CreatorToolkit.swift
App/Dashboard.swift
App/Haptics.swift
App/ListenHub.swift
App/LiveKitService.swift
App/MediaCompatibility.swift
App/MobileCapabilities.swift
App/MoreHub.swift
App/MoreNativeCreatorTools.swift
App/MusicianToolkit.swift
App/NativeMediaTools.swift
App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
App/Resources/Assets.xcassets/AppIcon.appiconset/icon-120.png
App/Resources/Assets.xcassets/AppIcon.appiconset/icon-180.png
App/Resources/Assets.xcassets/AppIcon.appiconset/icon-40.png
App/Resources/Assets.xcassets/AppIcon.appiconset/icon-58.png
App/Resources/Assets.xcassets/AppIcon.appiconset/icon-60.png
App/Resources/Assets.xcassets/AppIcon.appiconset/icon-80.png
App/Resources/Assets.xcassets/AppIcon.appiconset/icon-87.png
App/Resources/Assets.xcassets/BlindbanditRecordsGold.imageset/BlindbanditRecordsGold.jpeg
App/Resources/Assets.xcassets/BlindbanditRecordsGold.imageset/Contents.json
App/Resources/Assets.xcassets/Contents.json
App/Resources/BlindbanditRecordsGold.jpeg
App/Secrets.local.swift
App/Secrets.local.swift.example
App/Secrets.swift
App/SettingsView.swift
AppTests/BlindbanditTests.swift

### Android
Android/README.md
Android/app/build.gradle.kts
Android/app/proguard-rules.pro
Android/app/src/main/AndroidManifest.xml
Android/app/src/main/java/net/mrblindbandit/app/AndroidAppPreferences.kt
Android/app/src/main/java/net/mrblindbandit/app/BlindbanditFirebaseMessagingService.kt
Android/app/src/main/java/net/mrblindbandit/app/ListenHubScreen.kt
Android/app/src/main/java/net/mrblindbandit/app/MainActivity.kt
Android/app/src/main/java/net/mrblindbandit/app/MoreHubScreen.kt
Android/app/src/main/java/net/mrblindbandit/app/UrlPolicy.kt
Android/app/src/main/java/net/mrblindbandit/app/auth/AuthGatewayScreen.kt
Android/app/src/main/java/net/mrblindbandit/app/auth/ClerkAuthService.kt
Android/app/src/main/java/net/mrblindbandit/app/brand/BrandComponents.kt
Android/app/src/main/java/net/mrblindbandit/app/config/AppConfig.kt
Android/app/src/main/java/net/mrblindbandit/app/connect/ConnectScreens.kt
Android/app/src/main/java/net/mrblindbandit/app/connect/LiveKitService.kt
Android/app/src/main/java/net/mrblindbandit/app/creator/NativeCreatorToolkitScreen.kt
Android/app/src/main/res/drawable/logo_blindbandit_gold.png
Android/app/src/main/res/mipmap-hdpi/ic_launcher.png
Android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png
Android/app/src/main/res/mipmap-mdpi/ic_launcher.png
Android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png
Android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
Android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png
Android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
Android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png
Android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
Android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png
Android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png
Android/app/src/main/res/values/colors.xml
Android/app/src/main/res/values/strings.xml
Android/app/src/main/res/values/themes.xml
Android/app/src/test/java/net/mrblindbandit/app/UrlPolicyTest.kt
Android/build.gradle.kts
Android/local.properties.example
Android/settings.gradle.kts

### CI
.github/workflows/android.yml
.github/workflows/ios.yml
