import AppKit

let outputURL = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create graphics context")
}

context.setFillColor(NSColor(calibratedRed: 0.02, green: 0.025, blue: 0.035, alpha: 1).cgColor)
context.fill(CGRect(origin: .zero, size: canvas))

let gold = NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.16, alpha: 1)
let warmGold = NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.35, alpha: 1)

context.setStrokeColor(gold.cgColor)
context.setLineWidth(42)
context.strokeEllipse(in: CGRect(x: 126, y: 126, width: 772, height: 772))

let barWidths: CGFloat = 52
let gap: CGFloat = 30
let heights: [CGFloat] = [190, 320, 470, 620, 470, 320, 190]
let totalWidth = CGFloat(heights.count) * barWidths + CGFloat(heights.count - 1) * gap
let startX = (canvas.width - totalWidth) / 2

for (index, height) in heights.enumerated() {
    let x = startX + CGFloat(index) * (barWidths + gap)
    let rect = CGRect(x: x, y: (canvas.height - height) / 2, width: barWidths, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: barWidths / 2, cornerHeight: barWidths / 2, transform: nil)
    context.setFillColor(index == heights.count / 2 ? warmGold.cgColor : gold.cgColor)
    context.addPath(path)
    context.fillPath()
}

let crownRect = CGRect(x: 405, y: 742, width: 214, height: 94)
context.setFillColor(gold.cgColor)
let crown = CGMutablePath()
crown.move(to: CGPoint(x: crownRect.minX, y: crownRect.minY))
crown.addLine(to: CGPoint(x: crownRect.minX + 36, y: crownRect.maxY))
crown.addLine(to: CGPoint(x: crownRect.midX, y: crownRect.minY + 38))
crown.addLine(to: CGPoint(x: crownRect.maxX - 36, y: crownRect.maxY))
crown.addLine(to: CGPoint(x: crownRect.maxX, y: crownRect.minY))
crown.closeSubpath()
context.addPath(crown)
context.fillPath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode app icon")
}

try png.write(to: outputURL)
print("Generated \(outputURL.path)")
