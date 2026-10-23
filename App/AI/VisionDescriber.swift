import Foundation
import UIKit
import Vision
import AVFoundation

/// 1, 2, 14, 15: on-device photo descriptions + OCR. Vision classification, text recognition and face/person
/// detection; Foundation Models turns the facts into a sentence when available, otherwise a template is used.
enum VisionDescriber {
    struct Analysis: Equatable {
        var labels: [String] = []
        var text = ""
        var faces = 0
        var people = 0
        var summary = ""
    }

    static func analyze(_ image: UIImage) async -> Analysis {
        guard let cg = image.cgImage else { return Analysis(summary: "Image") }
        return await Task.detached(priority: .userInitiated) { () -> Analysis in
            var a = Analysis()
            let classify = VNClassifyImageRequest()
            let ocr = VNRecognizeTextRequest()
            ocr.recognitionLevel = .accurate
            ocr.usesLanguageCorrection = true
            ocr.automaticallyDetectsLanguage = true
            let faces = VNDetectFaceRectanglesRequest()
            let humans = VNDetectHumanRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            try? handler.perform([classify, ocr, faces, humans])
            a.labels = (classify.results ?? []).filter { $0.confidence > 0.3 }.prefix(6).map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
            a.text = (ocr.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            a.faces = faces.results?.count ?? 0
            a.people = humans.results?.count ?? 0
            return a
        }.value
    }

    static func template(_ a: Analysis) -> String {
        var parts: [String] = []
        let who = max(a.faces, a.people)
        if who == 1 { parts.append("One person") } else if who > 1 { parts.append("\(who) people") }
        if !a.labels.isEmpty { parts.append((parts.isEmpty ? "Likely shows " : "with ") + a.labels.prefix(3).joined(separator: ", ")) }
        var s = parts.isEmpty ? "A photo" : parts.joined(separator: " ")
        if !a.text.isEmpty { s += ". Text in image: " + String(a.text.prefix(400)) }
        return s + "."
    }

    /// Full description for VoiceOver.
    static func describe(_ image: UIImage) async -> Analysis {
        var a = await analyze(image)
        let facts = "Labels: \(a.labels.joined(separator: ", ")). Faces: \(a.faces). People: \(a.people). Text: \(a.text.prefix(800))"
        a.summary = await OnDeviceAI.composeDescription(facts: facts) ?? template(a)
        return a
    }

    /// Video: describe a frame one second in.
    static func describeVideo(_ url: URL) async -> String? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil) else { return nil }
        let d = await describe(UIImage(cgImage: cg))
        return "Video. " + d.summary
    }
}
