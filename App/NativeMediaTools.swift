import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit

@MainActor
final class AudioConverterModel: ObservableObject {
    enum Preset: String, CaseIterable, Identifiable {
        case master24 = "Master WAV · 24-bit"
        case distribution16 = "Distribution WAV · 16-bit"
        case mobileAAC = "M4A AAC · Apple compatible"
        var id: String { rawValue }
    }

    @Published var inputURL: URL?
    @Published var preset: Preset = .master24
    @Published var isWorking = false
    @Published var progressText = "Choose an audio file to begin."
    @Published var outputURL: URL?

    func setInput(_ url: URL) {
        inputURL = copyToTemporaryLocation(url)
        outputURL = nil
        if inputURL == nil {
            progressText = "The selected file could not be opened."
            AppHaptics.error()
        } else {
            progressText = "Ready to convert."
            AppHaptics.success()
        }
    }

    func convert() async {
        guard let inputURL else {
            progressText = "Choose an audio file first."
            AppHaptics.warning()
            return
        }

        isWorking = true
        outputURL = nil
        progressText = "Converting locally on this iPhone…"
        AppHaptics.doublePulse()
        defer { isWorking = false }

        do {
            switch preset {
            case .mobileAAC:
                outputURL = try await exportM4A(inputURL)
            case .master24:
                outputURL = try convertPCM(inputURL, bitDepth: 24)
            case .distribution16:
                outputURL = try convertPCM(inputURL, bitDepth: 16)
            }
            progressText = "Conversion complete."
            AppHaptics.creatorComplete()
            UIAccessibility.post(notification: .announcement, argument: "Audio conversion complete")
        } catch {
            progressText = "Conversion failed: \(error.localizedDescription)"
            AppHaptics.error()
            UIAccessibility.post(notification: .announcement, argument: progressText)
        }
    }

    private func convertPCM(_ input: URL, bitDepth: Int) throws -> URL {
        let source = try AVAudioFile(forReading: input)
        let sourceFormat = source.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sourceFormat.sampleRate,
            AVNumberOfChannelsKey: Int(sourceFormat.channelCount),
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mr-Blind-Bandit-\(UUID().uuidString).wav")
        let destination = try AVAudioFile(forWriting: output, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 32_768) else {
            throw CocoaError(.fileWriteUnknown)
        }

        while true {
            try source.read(into: buffer, frameCount: buffer.frameCapacity)
            if buffer.frameLength == 0 { break }
            try destination.write(from: buffer)
        }
        return output
    }

    private func exportM4A(_ input: URL) async throws -> URL {
        let asset = AVURLAsset(url: input)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mr-Blind-Bandit-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: output)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileWriteUnknown)
        }
        session.outputURL = output
        session.outputFileType = .m4a
        try await runExport(session)
        return output
    }

    private func runExport(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                if let error = session.error {
                    continuation.resume(throwing: error)
                } else if session.status == .completed {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
        }
    }

    private func copyToTemporaryLocation(_ url: URL) -> URL? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("input-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

struct NativeAudioConverterView: View {
    @StateObject private var model = AudioConverterModel()
    @State private var showPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ToolHero(
                    icon: "waveform.badge.plus",
                    title: "Audio Converter",
                    subtitle: "Professional local conversion. Your audio stays on this iPhone."
                )

                VStack(alignment: .leading, spacing: 14) {
                    Label("Source", systemImage: "music.note")
                        .font(.headline)

                    Button(model.inputURL?.lastPathComponent ?? "Choose audio file") {
                        AppHaptics.medium()
                        showPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Output preset", selection: $model.preset) {
                        ForEach(AudioConverterModel.Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model.preset) { _, _ in AppHaptics.selection() }

                    Button("Convert audio") {
                        AppHaptics.rigid()
                        Task { await model.convert() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.inputURL == nil || model.isWorking)

                    if model.isWorking { ProgressView("Converting audio") }
                    Text(model.progressText).foregroundStyle(.secondary)

                    if let output = model.outputURL {
                        ShareLink(item: output) {
                            Label("Share converted file", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .simultaneousGesture(TapGesture().onEnded { AppHaptics.light() })
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))

                ToolInfoCard(title: "Built for creators", lines: [
                    "24-bit WAV for high-quality masters",
                    "16-bit WAV for broad distribution compatibility",
                    "M4A AAC for compact Apple-friendly delivery",
                    "No upload required for conversion"
                ])
            }
            .padding()
        }
        .navigationTitle("Audio")
        .onAppear { AppHaptics.soft() }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): model.setInput(url)
            case .failure(let error):
                model.progressText = error.localizedDescription
                AppHaptics.error()
            }
        }
    }
}

@MainActor
final class ArtTrackGeneratorModel: ObservableObject {
    enum Canvas: String, CaseIterable, Identifiable {
        case square = "Square · 1080 × 1080"
        case landscape = "Landscape · 1920 × 1080"
        case vertical = "Vertical · 1080 × 1920"
        var id: String { rawValue }

        var size: CGSize {
            switch self {
            case .square: return CGSize(width: 1080, height: 1080)
            case .landscape: return CGSize(width: 1920, height: 1080)
            case .vertical: return CGSize(width: 1080, height: 1920)
            }
        }
    }

    @Published var artworkURL: URL?
    @Published var audioURL: URL?
    @Published var canvas: Canvas = .landscape
    @Published var showWaveform = true
    @Published var isWorking = false
    @Published var status = "Choose artwork and audio to create an art track."
    @Published var outputURL: URL?

    func setArtwork(_ url: URL) {
        artworkURL = copy(url)
        outputURL = nil
        if artworkURL == nil {
            status = "The selected artwork could not be opened."
            AppHaptics.error()
        } else {
            status = "Artwork ready. Choose audio to continue."
            AppHaptics.success()
        }
    }

    func setAudio(_ url: URL) {
        audioURL = copy(url)
        outputURL = nil
        if audioURL == nil {
            status = "The selected audio could not be opened."
            AppHaptics.error()
        } else {
            status = artworkURL == nil ? "Audio ready. Choose artwork to continue." : "Ready to generate."
            AppHaptics.success()
        }
    }

    func generate() async {
        guard let artworkURL, let audioURL else {
            status = "Choose both artwork and audio first."
            AppHaptics.warning()
            return
        }

        isWorking = true
        outputURL = nil
        status = "Rendering video locally…"
        AppHaptics.doublePulse()
        defer { isWorking = false }

        do {
            let audioAsset = AVURLAsset(url: audioURL)
            let duration = try await audioAsset.load(.duration)
            let imageData = try Data(contentsOf: artworkURL)
            guard let image = UIImage(data: imageData) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let silentVideo = try await renderStillVideo(
                image: image,
                duration: duration,
                size: canvas.size,
                waveform: showWaveform
            )
            outputURL = try await merge(video: silentVideo, audio: audioAsset, duration: duration)
            status = "Art track complete."
            AppHaptics.creatorComplete()
            UIAccessibility.post(notification: .announcement, argument: "Art track complete")
        } catch {
            status = "Art track failed: \(error.localizedDescription)"
            AppHaptics.error()
            UIAccessibility.post(notification: .announcement, argument: status)
        }
    }

    private func renderStillVideo(
        image: UIImage,
        duration: CMTime,
        size: CGSize,
        waveform: Bool
    ) async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("arttrack-video-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: output)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        writer.startSession(atSourceTime: .zero)

        let pixelBuffer = try makePixelBuffer(
            image: image,
            size: size,
            waveform: waveform,
            pool: adaptor.pixelBufferPool
        )

        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard adaptor.append(pixelBuffer, withPresentationTime: .zero) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }

        let end = CMTimeSubtract(duration, CMTime(value: 1, timescale: 30))
        if CMTimeCompare(end, .zero) > 0 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard adaptor.append(pixelBuffer, withPresentationTime: end) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }

        input.markAsFinished()
        try await finish(writer)
        return output
    }

    private func finish(_ writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if let error = writer.error {
                    continuation.resume(throwing: error)
                } else if writer.status == .completed {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
        }
    }

    private func makePixelBuffer(
        image: UIImage,
        size: CGSize,
        waveform: Bool,
        pool: CVPixelBufferPool?
    ) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        }
        if buffer == nil {
            CVPixelBufferCreate(
                nil,
                Int(size.width),
                Int(size.height),
                kCVPixelFormatType_32ARGB,
                nil,
                &buffer
            )
        }
        guard let pixelBuffer = buffer else { throw CocoaError(.fileWriteUnknown) }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let fitted = aspectFit(image.size, inside: size)
        if let cgImage = image.cgImage {
            context.draw(cgImage, in: fitted)
        }

        if waveform {
            drawWaveform(in: context, size: size)
        }

        return pixelBuffer
    }

    private func drawWaveform(in context: CGContext, size: CGSize) {
        let centerY = size.height * 0.86
        let levels: [CGFloat] = [0.18, 0.34, 0.54, 0.28, 0.72, 0.46, 0.22, 0.62, 0.38, 0.16]
        context.setFillColor(UIColor.white.withAlphaComponent(0.92).cgColor)

        let total = size.width * 0.6
        let barWidth = total / CGFloat(levels.count * 2)
        let start = (size.width - total) / 2

        for (index, scale) in levels.enumerated() {
            let height = size.height * 0.10 * scale
            let x = start + CGFloat(index * 2) * barWidth
            context.fill(CGRect(
                x: x,
                y: centerY - height / 2,
                width: barWidth,
                height: height
            ))
        }
    }

    private func aspectFit(_ image: CGSize, inside canvas: CGSize) -> CGRect {
        let scale = min(canvas.width / image.width, canvas.height / image.height)
        let fitted = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (canvas.width - fitted.width) / 2,
            y: (canvas.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func merge(video: URL, audio: AVURLAsset, duration: CMTime) async throws -> URL {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)

        guard let videoSource = try await videoAsset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoSource,
            at: .zero
        )

        if let audioSource = try await audio.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try audioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioSource,
                at: .zero
            )
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mr-Blind-Bandit-Art-Track-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: output)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        session.outputURL = output
        session.outputFileType = .mp4
        try await runExport(session)
        return output
    }

    private func runExport(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                if let error = session.error {
                    continuation.resume(throwing: error)
                } else if session.status == .completed {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
        }
    }

    private func copy(_ url: URL) -> URL? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

struct NativeArtTrackGeneratorView: View {
    @StateObject private var model = ArtTrackGeneratorModel()
    @State private var pickArtwork = false
    @State private var pickAudio = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ToolHero(
                    icon: "rectangle.stack.badge.play",
                    title: "Art Track Generator",
                    subtitle: "Create a finished MP4 locally from your artwork and audio."
                )

                VStack(alignment: .leading, spacing: 14) {
                    Button(model.artworkURL?.lastPathComponent ?? "Choose artwork") {
                        AppHaptics.medium()
                        pickArtwork = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button(model.audioURL?.lastPathComponent ?? "Choose audio") {
                        AppHaptics.medium()
                        pickAudio = true
                    }
                    .buttonStyle(.borderedProminent)

                    Picker("Video canvas", selection: $model.canvas) {
                        ForEach(ArtTrackGeneratorModel.Canvas.allCases) { canvas in
                            Text(canvas.rawValue).tag(canvas)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model.canvas) { _, _ in AppHaptics.selection() }

                    Toggle("Show waveform", isOn: $model.showWaveform)
                        .accessibilityHint("When off, the artwork fills the composition without the waveform graphic.")
                        .onChange(of: model.showWaveform) { _, _ in AppHaptics.selection() }

                    Button("Generate art track") {
                        AppHaptics.rigid()
                        Task { await model.generate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.artworkURL == nil || model.audioURL == nil || model.isWorking)

                    if model.isWorking { ProgressView("Rendering art track") }
                    Text(model.status).foregroundStyle(.secondary)

                    if let output = model.outputURL {
                        ShareLink(item: output) {
                            Label("Share finished MP4", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .simultaneousGesture(TapGesture().onEnded { AppHaptics.light() })
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))

                ToolInfoCard(title: "Local rendering", lines: [
                    "Square, landscape, and vertical presets",
                    "Optional waveform graphic",
                    "High-quality H.264 MP4 export through AVFoundation",
                    "Artwork and audio remain on device while rendering"
                ])
            }
            .padding()
        }
        .navigationTitle("Art Track")
        .onAppear { AppHaptics.soft() }
        .fileImporter(isPresented: $pickArtwork, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): model.setArtwork(url)
            case .failure(let error):
                model.status = error.localizedDescription
                AppHaptics.error()
            }
        }
        .fileImporter(isPresented: $pickAudio, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): model.setAudio(url)
            case .failure(let error):
                model.status = error.localizedDescription
                AppHaptics.error()
            }
        }
    }
}

struct ToolHero: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(.black)
                Image(systemName: icon)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.yellow)
            }
            .frame(height: 140)
            .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ToolInfoCard: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "checkmark.circle.fill")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
    }
}
