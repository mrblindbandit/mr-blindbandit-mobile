import SwiftUI
import CryptoKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

struct NativeCreatorToolkitView: View {
    private let tools: [(String, String, AnyView)] = [
        ("BPM Tapper", "Tap tempo without uploading audio", AnyView(BPMTapperView())),
        ("Royalty Split", "Calculate collaborator percentages", AnyView(RoyaltySplitView())),
        ("Storage Estimator", "Estimate audio storage requirements", AnyView(StorageEstimatorView())),
        ("Video Bitrate", "Calculate bitrate from size and duration", AnyView(VideoBitrateView())),
        ("Aspect Ratio", "Scale dimensions proportionally", AnyView(AspectRatioView())),
        ("Release Countdown", "Days until your release", AnyView(ReleaseCountdownView())),
        ("ISRC Validator", "Check basic ISRC formatting", AnyView(ISRCValidatorView())),
        ("UPC Validator", "Validate UPC-A check digits", AnyView(UPCValidatorView())),
        ("Slug Generator", "Make clean URL slugs", AnyView(SlugGeneratorView())),
        ("Filename Cleaner", "Create safe media filenames", AnyView(FilenameCleanerView())),
        ("Text Case Converter", "Uppercase, lowercase, or title case", AnyView(TextCaseView())),
        ("Caption Counter", "Count social caption characters", AnyView(CaptionCounterView())),
        ("Hashtag Builder", "Turn keywords into hashtags", AnyView(HashtagBuilderView())),
        ("SHA-256 Checksum", "Verify local file integrity", AnyView(ChecksumView())),
        ("Contrast Checker", "Check text/background contrast", AnyView(ContrastCheckerView())),
        ("QR Code Maker", "Create a QR image locally", AnyView(QRCodeView())),
        ("Metadata Notes", "Build release metadata notes", AnyView(MetadataNotesView())),
        ("Timecode Converter", "Frames to SMPTE-style timecode", AnyView(TimecodeView())),
        ("Sample Calculator", "Seconds to audio sample count", AnyView(SampleCountView())),
        ("Audio Duration", "Estimate duration from samples", AnyView(AudioDurationView()))
    ]

    var body: some View {
        List {
            Section {
                Text("20 offline creator utilities built with Swift. No WebKit and no upload required.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                NavigationLink { tool.2.navigationTitle(tool.0).navigationBarTitleDisplayMode(.inline) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.0).font(.headline)
                        Text(tool.1).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { AppHaptics.selection() })
            }
        }
        .navigationTitle("Creator Toolkit")
    }
}

private struct ToolShell<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View { Form { Section(title) { content } } }
}

struct BPMTapperView: View {
    @State private var taps: [Date] = []
    private var bpm: Int {
        guard taps.count >= 2 else { return 0 }
        let intervals = zip(taps.dropFirst(), taps).map { $0.0.timeIntervalSince($0.1) }
        guard let avg = intervals.isEmpty ? nil : intervals.reduce(0,+) / Double(intervals.count), avg > 0 else { return 0 }
        return Int((60 / avg).rounded())
    }
    var body: some View { ToolShell("Tempo") {
        LabeledContent("BPM", value: bpm == 0 ? "—" : "\(bpm)")
        Button("Tap Beat") { taps.append(Date()); if taps.count > 8 { taps.removeFirst() }; AppHaptics.medium() }
        Button("Reset") { taps.removeAll(); AppHaptics.light() }
    }}
}

struct RoyaltySplitView: View {
    @State private var total = 100.0
    @State private var collaborators = 2.0
    var body: some View { ToolShell("Equal split") {
        LabeledContent("Total percent", value: "\(Int(total))%")
        Stepper("People: \(Int(collaborators))", value: $collaborators, in: 1...20)
        LabeledContent("Each person", value: String(format: "%.2f%%", total / collaborators))
    }}
}

struct StorageEstimatorView: View {
    @State private var minutes = 3.0
    @State private var sampleRate = 48000.0
    @State private var bits = 24.0
    @State private var channels = 2.0
    private var mb: Double { minutes * 60 * sampleRate * bits * channels / 8 / 1_000_000 }
    var body: some View { ToolShell("PCM storage") {
        Stepper("Minutes: \(Int(minutes))", value: $minutes, in: 1...600)
        Picker("Sample rate", selection: $sampleRate) { Text("44.1 kHz").tag(44100.0); Text("48 kHz").tag(48000.0); Text("96 kHz").tag(96000.0) }
        Picker("Bit depth", selection: $bits) { Text("16-bit").tag(16.0); Text("24-bit").tag(24.0); Text("32-bit").tag(32.0) }
        Picker("Channels", selection: $channels) { Text("Mono").tag(1.0); Text("Stereo").tag(2.0) }
        LabeledContent("Estimated size", value: String(format: "%.1f MB", mb))
    }}
}

struct VideoBitrateView: View {
    @State private var sizeMB = 100.0
    @State private var minutes = 3.0
    private var mbps: Double { max(0, sizeMB * 8 / max(minutes * 60, 1)) }
    var body: some View { ToolShell("Target bitrate") {
        TextField("Target size MB", value: $sizeMB, format: .number).keyboardType(.decimalPad)
        TextField("Duration minutes", value: $minutes, format: .number).keyboardType(.decimalPad)
        LabeledContent("Approx bitrate", value: String(format: "%.2f Mbps", mbps))
    }}
}

struct AspectRatioView: View {
    @State private var width = 1920.0
    @State private var height = 1080.0
    @State private var targetWidth = 1080.0
    private var targetHeight: Double { width == 0 ? 0 : targetWidth * height / width }
    var body: some View { ToolShell("Scale dimensions") {
        TextField("Original width", value: $width, format: .number).keyboardType(.numberPad)
        TextField("Original height", value: $height, format: .number).keyboardType(.numberPad)
        TextField("Target width", value: $targetWidth, format: .number).keyboardType(.numberPad)
        LabeledContent("Target height", value: "\(Int(targetHeight.rounded())) px")
    }}
}

struct ReleaseCountdownView: View {
    @State private var date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    private var days: Int { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0) }
    var body: some View { ToolShell("Release date") { DatePicker("Release", selection: $date, displayedComponents: .date); LabeledContent("Days remaining", value: "\(days)") }}
}

struct ISRCValidatorView: View {
    @State private var code = ""
    private var valid: Bool { code.uppercased().replacingOccurrences(of: "-", with: "").range(of: "^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$", options: .regularExpression) != nil }
    var body: some View { ToolShell("ISRC") { TextField("USABC2612345", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled(); LabeledContent("Format", value: code.isEmpty ? "Enter a code" : (valid ? "Valid format" : "Invalid format")) }}
}

struct UPCValidatorView: View {
    @State private var code = ""
    private var valid: Bool {
        let d = code.compactMap(\.wholeNumberValue); guard d.count == 12 else { return false }
        let sum = d.prefix(11).enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10 == d[11]
    }
    var body: some View { ToolShell("UPC-A") { TextField("12 digits", text: $code).keyboardType(.numberPad); LabeledContent("Check digit", value: code.isEmpty ? "Enter UPC" : (valid ? "Valid" : "Invalid")) }}
}

private func slugify(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

struct SlugGeneratorView: View { @State private var text = ""; var body: some View { ToolShell("URL slug") { TextField("Title", text: $text); Text(slugify(text)).textSelection(.enabled) } } }
struct FilenameCleanerView: View { @State private var text = ""; private var cleaned: String { slugify(text).replacingOccurrences(of: "-", with: "_") }; var body: some View { ToolShell("Safe filename") { TextField("Filename", text: $text); Text(cleaned).textSelection(.enabled) } } }
struct TextCaseView: View { @State private var text = ""; var body: some View { ToolShell("Text") { TextEditor(text: $text).frame(minHeight: 120); Button("UPPERCASE") { text = text.uppercased(); AppHaptics.selection() }; Button("lowercase") { text = text.lowercased(); AppHaptics.selection() }; Button("Title Case") { text = text.capitalized; AppHaptics.selection() } } } }
struct CaptionCounterView: View { @State private var text = ""; var body: some View { ToolShell("Caption") { TextEditor(text: $text).frame(minHeight: 150); LabeledContent("Characters", value: "\(text.count)"); LabeledContent("Words", value: "\(text.split{ $0.isWhitespace }.count)") } } }
struct HashtagBuilderView: View { @State private var text = ""; private var tags: String { text.split{ $0 == "," || $0.isWhitespace }.map { "#" + $0.filter{ $0.isLetter || $0.isNumber } }.filter{ $0.count > 1 }.joined(separator: " ") }; var body: some View { ToolShell("Keywords") { TextField("rap, ambient, producer", text: $text); Text(tags).textSelection(.enabled) } } }

struct ChecksumView: View {
    @State private var showPicker = false
    @State private var hash = ""
    var body: some View { ToolShell("File checksum") {
        Button("Choose File") { showPicker = true }
        if !hash.isEmpty { Text(hash).font(.footnote.monospaced()).textSelection(.enabled) }
    }.fileImporter(isPresented: $showPicker, allowedContentTypes: [.data]) { result in
        guard case .success(let url) = result else { AppHaptics.error(); return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) { hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(); AppHaptics.success() } else { AppHaptics.error() }
    }}
}

private func luminance(_ hex: String) -> Double? {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
    guard s.count == 6, let n = Int(s, radix: 16) else { return nil }
    let vals = [Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255)].map { v -> Double in let x = v/255; return x <= 0.03928 ? x/12.92 : pow((x+0.055)/1.055, 2.4) }
    return 0.2126*vals[0] + 0.7152*vals[1] + 0.0722*vals[2]
}
struct ContrastCheckerView: View { @State private var fg = "#FFFFFF"; @State private var bg = "#000000"; private var ratio: Double? { guard let a=luminance(fg), let b=luminance(bg) else{return nil}; return (max(a,b)+0.05)/(min(a,b)+0.05) }; var body: some View { ToolShell("WCAG contrast") { TextField("Foreground hex", text:$fg).textInputAutocapitalization(.characters); TextField("Background hex", text:$bg).textInputAutocapitalization(.characters); LabeledContent("Ratio", value: ratio.map{String(format:"%.2f:1",$0)} ?? "Invalid"); if let ratio { Text(ratio >= 4.5 ? "Passes normal-text AA" : "Does not pass normal-text AA") } } } }

struct QRCodeView: View {
    @State private var text = "https://mrblindbandit.net"
    @State private var shareURL: URL?
    private let context = CIContext()
    private func generate() {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)), let cg = context.createCGImage(output, from: output.extent) else { AppHaptics.error(); return }
        let image = UIImage(cgImage: cg); let url = FileManager.default.temporaryDirectory.appendingPathComponent("qr-\(UUID().uuidString).png")
        if let data = image.pngData(), (try? data.write(to: url)) != nil { shareURL=url; AppHaptics.creatorComplete() }
    }
    var body: some View { ToolShell("QR code") { TextField("Text or URL", text:$text); Button("Generate QR") { generate() }; if let shareURL { ShareLink(item: shareURL) { Label("Share QR PNG", systemImage:"square.and.arrow.up") } } } }
}

struct MetadataNotesView: View { @State private var title=""; @State private var artist=""; @State private var label="Blindbandit Records"; @State private var year=Calendar.current.component(.year, from: Date()); private var notes:String { "Title: \(title)\nArtist: \(artist)\nLabel: \(label)\nYear: \(year)\nCopyright: © \(year) \(label)\nPhonographic: ℗ \(year) \(label)" }; var body: some View { ToolShell("Release metadata") { TextField("Title",text:$title); TextField("Artist",text:$artist); TextField("Label",text:$label); Stepper("Year: \(year)",value:$year,in:1900...2100); Text(notes).textSelection(.enabled) } } }
struct TimecodeView: View { @State private var frames=0.0; @State private var fps=30.0; private var tc:String { let total=Int(frames/max(fps,1)); let f=Int(frames)%Int(max(fps,1)); return String(format:"%02d:%02d:%02d:%02d", total/3600,(total%3600)/60,total%60,f) }; var body: some View { ToolShell("Frames to timecode") { TextField("Frames",value:$frames,format:.number).keyboardType(.numberPad); Picker("FPS",selection:$fps){Text("24").tag(24.0);Text("25").tag(25.0);Text("30").tag(30.0);Text("60").tag(60.0)}; LabeledContent("Timecode",value:tc) } } }
struct SampleCountView: View { @State private var seconds=60.0; @State private var rate=48000.0; private var samples:Int { Int(seconds*rate) }; var body: some View { ToolShell("Seconds to samples") { TextField("Seconds",value:$seconds,format:.number).keyboardType(.decimalPad); Picker("Sample rate",selection:$rate){Text("44.1 kHz").tag(44100.0);Text("48 kHz").tag(48000.0);Text("96 kHz").tag(96000.0)}; LabeledContent("Samples",value:"\(samples)") } } }
struct AudioDurationView: View { @State private var samples=2_880_000.0; @State private var rate=48000.0; private var duration:Double { samples/max(rate,1) }; var body: some View { ToolShell("Samples to duration") { TextField("Samples",value:$samples,format:.number).keyboardType(.numberPad); Picker("Sample rate",selection:$rate){Text("44.1 kHz").tag(44100.0);Text("48 kHz").tag(48000.0);Text("96 kHz").tag(96000.0)}; LabeledContent("Duration",value:String(format:"%.2f seconds",duration)) } } }
