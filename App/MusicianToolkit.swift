import SwiftUI
import Combine

/// Expanded musician utilities — real native UI, not empty stubs.
struct MusicianStudioView: View {
    private let tools: [(String, String, String, AnyView)] = [
        ("Metronome", "metronome.fill", "Tap-accurate click with BPM and accents", AnyView(MetronomeView())),
        ("Key / BPM Helper", "music.note.list", "Guess relative keys and tempo notes", AnyView(KeyBPMHelperView())),
        ("Setlist Notes", "list.bullet.rectangle", "Build a gig setlist on device", AnyView(SetlistNotesView())),
        ("Release Checklist", "checklist", "Pre-release QA for masters and assets", AnyView(ReleaseChecklistView())),
        ("Lyric Scratchpad", "pencil.and.list.clipboard", "Draft verses and hooks offline", AnyView(LyricScratchpadView())),
        ("Loudness Tips", "speaker.wave.3.fill", "Practical LUFS / true-peak guidance", AnyView(LoudnessTipsView())),
        ("Cover Size Checker", "photo.badge.checkmark", "Validate square cover dimensions", AnyView(CoverSizeCheckerView())),
        ("Hashtag / Blurb Helper", "number", "Promo blurb + platform hashtags", AnyView(HashtagBlurbHelperView())),
        ("Capo / Transpose", "arrow.up.arrow.down", "Shift chords for live keys", AnyView(CapoTransposeView())),
        ("Practice Timer", "timer", "Focused practice sessions", AnyView(PracticeTimerView()))
    ]

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    BlindbanditLogoImage(size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Musician Studio").font(.headline)
                        Text("Native tools for writers, producers, and live artists.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                NavigationLink {
                    tool.3
                        .navigationTitle(tool.0)
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.0).font(.headline)
                            Text(tool.2).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: tool.1).foregroundStyle(.yellow)
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { AppHaptics.selection() })
                .accessibilityHint(tool.2)
            }
        }
        .navigationTitle("Musician Studio")
    }
}

// MARK: - Metronome

struct MetronomeView: View {
    @State private var bpm: Double = 120
    @State private var running = false
    @State private var beat = 0
    @State private var accents = 4
    @EnvironmentObject private var preferences: AppPreferences
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    @State private var accum: Double = 0

    var body: some View {
        Form {
            Section("Tempo") {
                HStack {
                    Text("\(Int(bpm)) BPM").font(.largeTitle.monospacedDigit().bold())
                        .accessibilityLabel("\(Int(bpm)) beats per minute")
                    Spacer()
                    BlindbanditLogoImage(size: 36)
                        .opacity(running && beat == 0 ? 1 : 0.55)
                }
                Slider(value: $bpm, in: 40...240, step: 1)
                    .tint(.yellow)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(Int(bpm)) BPM")
                Stepper("Beats per bar: \(accents)", value: $accents, in: 1...8)
            }
            Section {
                Button(running ? "Stop" : "Start") {
                    running.toggle()
                    beat = 0
                    accum = 0
                    AppHaptics.medium()
                }
                .font(.headline)
                Text(running ? "Beat \(beat + 1) of \(accents)" : "Stopped")
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onReceive(timer) { _ in
            guard running else { return }
            accum += 0.05
            let interval = 60.0 / bpm
            if accum >= interval {
                accum -= interval
                beat = (beat + 1) % accents
                if beat == 0 { AppHaptics.rigid() } else { AppHaptics.light() }
            }
        }
    }
}

// MARK: - Key / BPM Helper

struct KeyBPMHelperView: View {
    @State private var root = "C"
    @State private var quality = "major"
    @State private var bpmNotes = ""
    private let roots = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
    private var relatives: String {
        let idx = roots.firstIndex(of: root) ?? 0
        if quality == "major" {
            let rel = roots[(idx + 9) % 12]
            return "Relative minor: \(rel)m · Parallel minor: \(root)m"
        } else {
            let rel = roots[(idx + 3) % 12]
            return "Relative major: \(rel) · Parallel major: \(root)"
        }
    }

    var body: some View {
        Form {
            Section("Key") {
                Picker("Root", selection: $root) { ForEach(roots, id: \.self) { Text($0).tag($0) } }
                Picker("Quality", selection: $quality) {
                    Text("Major").tag("major")
                    Text("Minor").tag("minor")
                }
                .pickerStyle(.segmented)
                Text(relatives).font(.subheadline)
            }
            Section("Tempo notes") {
                TextField("Session notes (e.g. chorus lifts to 128)", text: $bpmNotes, axis: .vertical)
                    .lineLimit(3...6)
                Text("Tip: mark half-time / double-time feels for live cues.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Setlist

struct SetlistNotesView: View {
    @AppStorage("musicianSetlistJSON") private var raw = ""
    @State private var items: [String] = []
    @State private var draft = ""

    var body: some View {
        List {
            Section("Add song") {
                HStack {
                    TextField("Song title / key / BPM", text: $draft)
                        .accessibilityLabel("New setlist item")
                    Button("Add") {
                        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        items.append(t)
                        draft = ""
                        persist()
                        AppHaptics.success()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("Setlist") {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Text("\(index + 1). \(item)")
                }
                .onDelete { idx in items.remove(atOffsets: idx); persist() }
                .onMove { a, b in items.move(fromOffsets: a, toOffset: b); persist() }
            }
        }
        .toolbar { EditButton() }
        .onAppear {
            if items.isEmpty, let data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                items = decoded
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items), let s = String(data: data, encoding: .utf8) {
            raw = s
        }
    }
}

// MARK: - Release checklist

struct ReleaseChecklistView: View {
    private struct Item: Identifiable { let id = UUID(); let title: String; var done: Bool }
    @State private var items: [Item] = [
        .init(title: "Master bounced (WAV 24-bit)", done: false),
        .init(title: "Streaming master (−14 LUFS integrated)", done: false),
        .init(title: "True peak under −1.0 dBTP", done: false),
        .init(title: "Cover art 3000×3000 JPEG/PNG", done: false),
        .init(title: "ISRC assigned", done: false),
        .init(title: "Metadata / credits proofed", done: false),
        .init(title: "Distributor draft submitted", done: false),
        .init(title: "Promo blurb + hashtags ready", done: false)
    ]

    var body: some View {
        List {
            Section {
                GoldProgressBar(value: Double(items.filter(\.done).count) / Double(max(items.count, 1)), label: "Release checklist progress")
            }
            Section("Before you ship") {
                ForEach($items) { $item in
                    Toggle(item.title, isOn: $item.done)
                        .onChange(of: item.done) { _, _ in AppHaptics.selection() }
                }
            }
        }
    }
}

// MARK: - Lyrics

struct LyricScratchpadView: View {
    @AppStorage("lyricScratchpad") private var lyrics = ""
    var wordCount: Int {
        lyrics.split{ $0.isWhitespace || $0.isNewline }.filter{ !$0.isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $lyrics)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Lyric scratchpad")
            Text("\(wordCount) words")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(wordCount) words")
        }
        .padding()
    }
}

// MARK: - Loudness

struct LoudnessTipsView: View {
    var body: some View {
        List {
            Section("Targets") {
                LabeledContent("Spotify / Apple Music", value: "≈ −14 LUFS")
                LabeledContent("YouTube", value: "≈ −13 to −14 LUFS")
                LabeledContent("Club / DJ master", value: "often louder; watch clipping")
                LabeledContent("True peak", value: "≤ −1.0 dBTP")
            }
            Section("Blindbandit tips") {
                Text("Leave headroom before limiting. Check mono compatibility. A/B against a reference at matched loudness, not matched peak.")
                Text("Use the native Peak Normalizer for local checks, then confirm with a metering plug-in on your DAW master.")
            }
        }
    }
}

// MARK: - Cover size

struct CoverSizeCheckerView: View {
    @State private var width = "3000"
    @State private var height = "3000"
    private var verdict: String {
        guard let w = Int(width), let h = Int(height), w > 0, h > 0 else { return "Enter width and height in pixels." }
        if w == h && w >= 3000 { return "Store-ready square (≥ 3000×3000)." }
        if w == h && w >= 1400 { return "Acceptable for many DSPs; 3000×3000 preferred." }
        if w != h { return "Not square — most stores require 1:1." }
        return "Too small — increase to at least 1400×1400 (prefer 3000)."
    }

    var body: some View {
        Form {
            TextField("Width (px)", text: $width).keyboardType(.numberPad)
            TextField("Height (px)", text: $height).keyboardType(.numberPad)
            Text(verdict).font(.headline)
                .accessibilityLabel(verdict)
        }
    }
}

// MARK: - Hashtag / blurb

struct HashtagBlurbHelperView: View {
    @State private var title = ""
    @State private var vibe = ""
    @State private var output = ""

    var body: some View {
        Form {
            TextField("Track / release title", text: $title)
            TextField("Vibe keywords (comma separated)", text: $vibe)
            Button("Build blurb + tags") {
                let tags = vibe.split(separator: ",").map { "#" + $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "") }.filter { $0.count > 1 }
                let tagLine = (tags + ["#BlindbanditRecords", "#MrBlindBandit", "#NewMusic"]).joined(separator: " ")
                output = "“\(title.isEmpty ? "New release" : title)” is out now on Blindbandit Records. Stream it, share it, turn it up.\n\n\(tagLine)"
                AppHaptics.success()
            }
            if !output.isEmpty {
                Section("Copy") {
                    Text(output).textSelection(.enabled)
                        .accessibilityLabel("Promo blurb")
                }
            }
        }
    }
}

// MARK: - Capo / transpose

struct CapoTransposeView: View {
    @State private var capo = 0
    private let open = ["G","C","D","Em","Am"]
    private let chromatic = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]

    private func shift(_ chord: String) -> String {
        let suffix = chord.hasSuffix("m") ? "m" : ""
        let root = suffix.isEmpty ? chord : String(chord.dropLast())
        guard let idx = chromatic.firstIndex(of: root) else { return chord }
        return chromatic[(idx + capo) % 12] + suffix
    }

    var body: some View {
        Form {
            Stepper("Capo fret: \(capo)", value: $capo, in: 0...7)
            Section("Open shapes → sounding") {
                ForEach(open, id: \.self) { c in
                    LabeledContent(c, value: shift(c))
                }
            }
        }
    }
}

// MARK: - Practice timer

struct PracticeTimerView: View {
    @State private var seconds = 600
    @State private var remaining = 600
    @State private var running = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Stepper("Session: \(seconds / 60) min", value: $seconds, in: 60...3600, step: 60)
                .disabled(running)
            Text(timeLabel(remaining))
                .font(.largeTitle.monospacedDigit().bold())
                .accessibilityLabel("Time remaining \(timeLabel(remaining))")
            Button(running ? "Pause" : "Start") {
                if !running { remaining = seconds }
                running.toggle()
                AppHaptics.selection()
            }
            Button("Reset") { running = false; remaining = seconds }
            GoldProgressBar(value: 1 - Double(remaining) / Double(max(seconds, 1)), label: "Practice session progress")
        }
        .onReceive(tick) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { running = false; AppHaptics.success() }
        }
    }

    private func timeLabel(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}
