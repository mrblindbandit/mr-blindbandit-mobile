import Foundation
// App icons are pre-generated under App/Resources/Assets.xcassets/AppIcon.appiconset
// from brand/logo-blindbandit-records-gold.jpeg. This script is a CI no-op when assets exist.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let icon = root.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
if FileManager.default.fileExists(atPath: icon.path) {
    fputs("GenerateAppIcon: using existing gold logo AppIcon assets.\n", stderr)
    exit(0)
}
fputs("GenerateAppIcon: icon-1024.png missing — add brand assets before release.\n", stderr)
exit(1)
