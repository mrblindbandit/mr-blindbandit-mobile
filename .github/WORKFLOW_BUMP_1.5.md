# CI workflow bump for 1.5 (requires `workflow` scope to commit)

Update `.github/workflows/ios.yml` and `android.yml` when a token with the `workflow` scope is available:

- `APP_VERSION: '1.5'`
- iOS grep: `MARKETING_VERSION: '1.5'` and `CURRENT_PROJECT_VERSION: '5'`
- Android grep: `versionCode = 5` and `versionName = "1.5.0"`
- Artifact names: `Mr-Blindbandit-*-v1.5-*`

Source versions are already 1.5 / build 5 in `project.yml` and `Android/app/build.gradle.kts`.
