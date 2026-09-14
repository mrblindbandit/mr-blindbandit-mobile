import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit

private func copySecurityScopedFile(_ url: URL, prefix: String) -> URL? {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)-\(url.lastPathComponent)")
    do {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    } catch {
        return nil
    }
}

struct NativeAudioTrimmerView: View {
    @State private var inputURL: URL?
    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var outputURL: URL?
    @State private var status = "Choose an audio file to trim."
    @State private var picking = false
    @State private var working = false

    var body: some View {
        Form {
            Section("Source") {
                Button(inputURL?.lastPathComponent ?? "Choose audio file") {
                    AppHaptics.medium(); picking = true
                }
                if duration > 0 {
                    LabeledContent("Duration", value: formatTime(duration))
                }
            }

            if duration > 0 {
                Section("Trim range") {
                    VStack(alignment: .leading) {
                        Text("Start: \(formatTime(start))")
                        Slider(value: $start, in: 0...max(0, end - 0.1), step: 0.1)
                            .onChange(of: start) { _, _ in AppHaptics.selection() }
                    }
                    VStack(alignment: .leading) {
                        Text("End: \(formatTime(end))")
                        Slider(value: $end, in: min(duration, start + 0.1)...duration, step: 0.1)
                            .onChange(of: end) { _, _ in AppHaptics.selection() }
                    }
                    LabeledContent("Selected", value: formatTime(max(0, end - start)))
                }

                Section {
                    Button("Create trimmed file") {
                        AppHaptics.heavy()
                        Task { await trim() }
                    }
                    .disabled(working || end <= start)
                    if working { ProgressView("Trimming audio") }
                    Text(status).foregroundStyle(.secondary)
                    if let outputURL {
                        ShareLink(item: outputURL) {
                            Label("Share trimmed audio", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("Audio Trimmer")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                guard let local = copySecurityScopedFile(url, prefix: "trim") else {
                    status = "The selected file could not be opened."; AppHaptics.error(); return
                }
                inputURL = local
                Task { await loadDuration(local) }
            case .failure(let error):
                status = error.localizedDescription; AppHaptics.error()
            }
        }
    }

    private func loadDuration(_ url: URL) async {
        do {
            let asset = AVURLAsset(url: url)
            let value = try await asset.load(.duration).seconds
            duration = max(0, value)
            start = 0
            end = duration
            status = "Ready to trim."
            AppHaptics.success()
        } catch {
            status = "Could not read audio duration."
            AppHaptics.error()
        }
    }

    private func trim() async {
        guard let inputURL else { return }
        working = true
        outputURL = nil
        status = "Creating trimmed audio locally…"
        defer { working = false }
        do {
            let asset = AVURLAsset(url: inputURL)
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("Mr-Blind-Bandit-Trim-\(UUID().uuidString).m4a")
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw CocoaError(.fileWriteUnknown)
            }
            session.outputURL = output
            session.outputFileType = .m4a
            session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end - start, preferredTimescale: 600))
            await session.export()
            if let error = session.error { throw error }
            guard session.status == .completed else { throw CocoaError(.fileWriteUnknown) }
            outputURL = output
            status = "Trim complete."
            AppHaptics.creatorComplete()
            UIAccessibility.post(notification: .announcement, argument: "Audio trim complete")
        } catch {
            status = "Trim failed: \(error.localizedDescription)"
            AppHaptics.error()
        }
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        let total = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct NativeArtworkResizerView: View {
    enum Preset: String, CaseIterable, Identifiable {
        case cover = "Cover Art · 3000 × 3000"
        case square = "Social Square · 1080 × 1080"
        case landscape = "Video Landscape · 1920 × 1080"
        case vertical = "Shorts Vertical · 1080 × 1920"
        var id: String { rawValue }
        var size: CGSize {
            switch self {
            case .cover: return CGSize(width: 3000, height: 3000)
            case .square: return CGSize(width: 1080, height: 1080)
            case .landscape: return CGSize(width: 1920, height: 1080)
            case .vertical: return CGSize(width: 1080, height: 1920)
            }
        }
    }

    @State private var inputURL: URL?
    @State private var preset: Preset = .cover
    @State private var outputURL: URL?
    @State private var picking = false
    @State private var status = "Choose artwork to resize."

    var body: some View {
        Form {
            Section("Artwork") {
                Button(inputURL?.lastPathComponent ?? "Choose image") { AppHaptics.medium(); picking = true }
                Picker("Output size", selection: $preset) {
                    ForEach(Preset.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: preset) { _, _ in AppHaptics.selection() }
            }
            Section {
                Button("Resize artwork") { AppHaptics.heavy(); resize() }
                    .disabled(inputURL == nil)
                Text(status).foregroundStyle(.secondary)
                if let outputURL {
                    ShareLink(item: outputURL) { Label("Share resized artwork", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .navigationTitle("Artwork Resizer")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                inputURL = copySecurityScopedFile(url, prefix: "artwork")
                status = inputURL == nil ? "The selected image could not be opened." : "Ready to resize."
                inputURL == nil ? AppHaptics.error() : AppHaptics.success()
            case .failure(let error): status = error.localizedDescription; AppHaptics.error()
            }
        }
    }

    private func resize() {
        guard let inputURL, let image = UIImage(contentsOfFile: inputURL.path) else {
            status = "Could not read the selected image."; AppHaptics.error(); return
        }
        let canvas = preset.size
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let result = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            let scale = min(canvas.width / image.size.width, canvas.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
            image.draw(in: rect)
        }
        guard let data = result.pngData() else { status = "Could not encode PNG."; AppHaptics.error(); return }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Mr-Blind-Bandit-Artwork-\(Int(canvas.width))x\(Int(canvas.height)).png")
        do {
            try data.write(to: output, options: .atomic)
            outputURL = output
            status = "Artwork resized successfully."
            AppHaptics.creatorComplete()
        } catch {
            status = "Resize failed: \(error.localizedDescription)"; AppHaptics.error()
        }
    }
}

struct NativeImageConverterView: View {
    enum Format: String, CaseIterable, Identifiable { case png = "PNG", jpeg = "JPEG"; var id: String { rawValue } }
    @State private var inputURL: URL?
    @State private var format: Format = .png
    @State private var quality: Double = 0.92
    @State private var outputURL: URL?
    @State private var picking = false
    @State private var status = "Choose an image to convert."

    var body: some View {
        Form {
            Section("Image") {
                Button(inputURL?.lastPathComponent ?? "Choose image") { AppHaptics.medium(); picking = true }
                Picker("Format", selection: $format) { ForEach(Format.allCases) { Text($0.rawValue).tag($0) } }
                    .onChange(of: format) { _, _ in AppHaptics.selection() }
                if format == .jpeg {
                    VStack(alignment: .leading) {
                        Text("JPEG quality: \(Int(quality * 100))%")
                        Slider(value: $quality, in: 0.5...1.0, step: 0.05)
                    }
                }
            }
            Section {
                Button("Convert image") { AppHaptics.heavy(); convert() }.disabled(inputURL == nil)
                Text(status).foregroundStyle(.secondary)
                if let outputURL { ShareLink(item: outputURL) { Label("Share converted image", systemImage: "square.and.arrow.up") } }
            }
        }
        .navigationTitle("Image Converter")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result { inputURL = copySecurityScopedFile(url, prefix: "image"); AppHaptics.success() }
            if case let .failure(error) = result { status = error.localizedDescription; AppHaptics.error() }
        }
    }

    private func convert() {
        guard let inputURL, let image = UIImage(contentsOfFile: inputURL.path) else { status = "Could not read image."; AppHaptics.error(); return }
        let ext = format == .png ? "png" : "jpg"
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Mr-Blind-Bandit-Image-\(UUID().uuidString).\(ext)")
        let data = format == .png ? image.pngData() : image.jpegData(compressionQuality: quality)
        guard let data else { status = "Could not encode image."; AppHaptics.error(); return }
        do {
            try data.write(to: output, options: .atomic)
            outputURL = output
            status = "Image conversion complete."
            AppHaptics.creatorComplete()
        } catch {
            status = "Conversion failed: \(error.localizedDescription)"; AppHaptics.error()
        }
    }
}

struct NativeAudioInspectorView: View {
    @State private var inputURL: URL?
    @State private var picking = false
    @State private var rows: [(String, String)] = []
    @State private var status = "Choose an audio file to inspect."

    var body: some View {
        List {
            Section("File") {
                Button(inputURL?.lastPathComponent ?? "Choose audio file") { AppHaptics.medium(); picking = true }
                Text(status).foregroundStyle(.secondary)
            }
            if !rows.isEmpty {
                Section("Technical details") {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.0, value: row.1)
                    }
                }
            }
        }
        .navigationTitle("Audio Inspector")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                guard let local = copySecurityScopedFile(url, prefix: "inspect") else { status = "Could not open file."; AppHaptics.error(); return }
                inputURL = local
                inspect(local)
            case .failure(let error): status = error.localizedDescription; AppHaptics.error()
            }
        }
    }

    private func inspect(_ url: URL) {
        do {
            let audio = try AVAudioFile(forReading: url)
            let format = audio.processingFormat
            let seconds = format.sampleRate > 0 ? Double(audio.length) / format.sampleRate : 0
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            rows = [
                ("Duration", String(format: "%.2f seconds", seconds)),
                ("Sample rate", String(format: "%.0f Hz", format.sampleRate)),
                ("Channels", "\(format.channelCount)"),
                ("Frames", "\(audio.length)"),
                ("File size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)),
                ("Format", format.commonFormat == .pcmFormatFloat32 ? "32-bit float PCM decode" : "Audio")
            ]
            status = "Inspection complete."
            AppHaptics.success()
        } catch {
            rows = []
            status = "Inspection failed: \(error.localizedDescription)"
            AppHaptics.error()
        }
    }
}

struct NativePeakNormalizerView: View {
    @State private var inputURL: URL?
    @State private var targetDB: Double = -1.0
    @State private var outputURL: URL?
    @State private var picking = false
    @State private var working = false
    @State private var status = "Choose an audio file to peak-normalize."

    var body: some View {
        Form {
            Section("Source") {
                Button(inputURL?.lastPathComponent ?? "Choose audio file") { AppHaptics.medium(); picking = true }
            }
            Section("Target") {
                VStack(alignment: .leading) {
                    Text("Peak target: \(String(format: "%.1f", targetDB)) dBFS")
                    Slider(value: $targetDB, in: -6.0 ... -0.1, step: 0.1)
                        .onChange(of: targetDB) { _, _ in AppHaptics.selection() }
                }
            }
            Section {
                Button("Normalize audio") { AppHaptics.heavy(); Task { await normalize() } }
                    .disabled(inputURL == nil || working)
                if working { ProgressView("Normalizing audio") }
                Text(status).foregroundStyle(.secondary)
                if let outputURL { ShareLink(item: outputURL) { Label("Share normalized WAV", systemImage: "square.and.arrow.up") } }
            }
        }
        .navigationTitle("Peak Normalizer")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { result in
            if case let .success(url) = result {
                inputURL = copySecurityScopedFile(url, prefix: "normalize")
                status = inputURL == nil ? "Could not open audio." : "Ready to normalize."
                inputURL == nil ? AppHaptics.error() : AppHaptics.success()
            }
            if case let .failure(error) = result { status = error.localizedDescription; AppHaptics.error() }
        }
    }

    private func normalize() async {
        guard let inputURL else { return }
        working = true
        outputURL = nil
        status = "Scanning peak level…"
        defer { working = false }
        do {
            let source = try AVAudioFile(forReading: inputURL)
            let format = source.processingFormat
            guard let scanBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768) else { throw CocoaError(.fileReadUnknown) }
            var peak: Float = 0
            while true {
                try source.read(into: scanBuffer, frameCount: scanBuffer.frameCapacity)
                if scanBuffer.frameLength == 0 { break }
                guard let channels = scanBuffer.floatChannelData else { throw CocoaError(.fileReadUnknown) }
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<Int(scanBuffer.frameLength) { peak = max(peak, abs(channels[channel][frame])) }
                }
            }
            guard peak > 0 else { throw CocoaError(.fileReadUnknown) }
            let targetLinear = pow(10.0, Float(targetDB) / 20.0)
            let gain = min(32.0, targetLinear / peak)

            let reader = try AVAudioFile(forReading: inputURL)
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("Mr-Blind-Bandit-Normalized-\(UUID().uuidString).wav")
            let writer = try AVAudioFile(forWriting: output, settings: format.settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768) else { throw CocoaError(.fileWriteUnknown) }
            status = "Applying gain locally…"
            while true {
                try reader.read(into: buffer, frameCount: buffer.frameCapacity)
                if buffer.frameLength == 0 { break }
                guard let channels = buffer.floatChannelData else { throw CocoaError(.fileReadUnknown) }
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) {
                        channels[channel][frame] = max(-1, min(1, channels[channel][frame] * gain))
                    }
                }
                try writer.write(from: buffer)
            }
            outputURL = output
            status = "Peak normalization complete."
            AppHaptics.creatorComplete()
            UIAccessibility.post(notification: .announcement, argument: "Peak normalization complete")
        } catch {
            status = "Normalization failed: \(error.localizedDescription)"
            AppHaptics.error()
        }
    }
}
