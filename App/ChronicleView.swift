import SwiftUI

/// The Blindbandit Chronicle: published stories from https://mrblindbandit.net/feed.xml.
struct ChronicleStory: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let url: URL
    let date: Date?
    var imageURL: URL?
}

@MainActor
final class ChronicleFeed: ObservableObject {
    @Published private(set) var stories: [ChronicleStory] = []
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?

    static let feedURL = URL(string: "https://mrblindbandit.net/feed.xml")!

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("chronicle-feed.xml")
    }

    func load() async {
        loading = true; defer { loading = false }
        if stories.isEmpty, let cached = try? Data(contentsOf: Self.cacheURL) {
            stories = ChronicleRSSParser.parse(cached)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.feedURL)
            try? data.write(to: Self.cacheURL, options: .atomic)
            let parsed = ChronicleRSSParser.parse(data)
            stories = parsed
            errorMessage = parsed.isEmpty ? "No stories are published yet." : nil
            await loadImages()
        } catch {
            errorMessage = stories.isEmpty ? "Couldn't load the Chronicle. Check your connection and pull to refresh." : nil
        }
    }

    /// Reads each story's og:image so the list shows the article's own artwork.
    private func loadImages() async {
        await withTaskGroup(of: (String, URL?).self) { group in
            for story in stories where story.imageURL == nil {
                group.addTask {
                    guard let (data, _) = try? await URLSession.shared.data(from: story.url),
                          let html = String(data: data, encoding: .utf8) else { return (story.id, nil) }
                    return (story.id, ChronicleRSSParser.ogImage(in: html, base: story.url))
                }
            }
            for await (id, url) in group {
                if let url, let i = stories.firstIndex(where: { $0.id == id }) { stories[i].imageURL = url }
            }
        }
    }
}

enum ChronicleRSSParser {
    static func parse(_ data: Data) -> [ChronicleStory] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    static func ogImage(in html: String, base: URL) -> URL? {
        guard let range = html.range(of: #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#, options: .regularExpression) else { return nil }
        let tag = String(html[range])
        guard let c = tag.range(of: #"content=["']([^"']+)"#, options: .regularExpression) else { return nil }
        let value = tag[c].dropFirst(9)
        return URL(string: String(value), relativeTo: base)?.absoluteURL
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [ChronicleStory] = []
        private var current: [String: String]?
        private var text = ""
        private static let formatter: DateFormatter = {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"; return f
        }()

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "item" { current = [:] }
            text = ""
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "item", let c = current, let link = c["link"], let url = URL(string: link) {
                items.append(ChronicleStory(id: c["guid"] ?? link, title: c["title"] ?? "", summary: c["description"] ?? "",
                                            url: url, date: c["pubDate"].flatMap { Self.formatter.date(from: $0) }))
                current = nil
            } else if current != nil, ["guid", "title", "link", "description", "pubDate"].contains(name) {
                current?[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

struct ChronicleView: View {
    @StateObject private var feed = ChronicleFeed()

    var body: some View {
        List {
            if let message = feed.errorMessage {
                VStack(spacing: 12) {
                    Image("BBEmptyChronicle").resizable().scaledToFit().frame(maxWidth: 220).accessibilityHidden(true)
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24).listRowSeparator(.hidden)
            }
            ForEach(feed.stories) { story in
                NavigationLink {
                    ChronicleReader(story: story)
                } label: {
                    ChronicleRow(story: story)
                }
            }
        }
        .listStyle(.plain)
        .overlay { if feed.loading && feed.stories.isEmpty { ProgressView("Loading the Chronicle") } }
        .refreshable { await feed.load() }
        .task { if feed.stories.isEmpty { await feed.load() } }
        .navigationTitle("The Chronicle")
    }
}

private struct ChronicleRow: View {
    let story: ChronicleStory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: story.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                BlindbanditLogoImage(size: 72)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(story.title).font(.headline).lineLimit(3)
                if let date = story.date {
                    Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                Text(story.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full story")
    }
}

/// Native article reader: the story's HTML is reduced to headings, paragraphs, quotes and list
/// items, rendered with Dynamic Type. Headings carry the VoiceOver header trait.
struct ChronicleBlock: Hashable {
    enum Kind: Hashable { case heading(Int), paragraph, quote, bullet }
    let kind: Kind
    let text: AttributedString
}

enum ChronicleArticleParser {
    static func blocks(fromHTML html: String) -> [ChronicleBlock] {
        var body = html
        if let start = html.range(of: "<article"), let end = html.range(of: "</article>", range: start.upperBound..<html.endIndex) {
            body = String(html[start.lowerBound..<end.upperBound])
        }
        for tag in ["nav", "script", "style", "figure", "form", "aside", "footer", "button"] {
            body = body.replacingOccurrences(of: "<\(tag)[\\s\\S]*?</\(tag)>", with: "", options: .regularExpression)
        }
        let pattern = "<(h1|h2|h3|h4|p|blockquote|li)[^>]*>([\\s\\S]*?)</\\1>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = body as NSString
        return regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let tag = ns.substring(with: m.range(at: 1)).lowercased()
            let text = clean(ns.substring(with: m.range(at: 2)))
            guard !text.isEmpty else { return nil }
            let kind: ChronicleBlock.Kind
            switch tag {
            case "h1": kind = .heading(1)
            case "h2": kind = .heading(2)
            case "h3", "h4": kind = .heading(3)
            case "blockquote": kind = .quote
            case "li": kind = .bullet
            default: kind = .paragraph
            }
            return ChronicleBlock(kind: kind, text: AttributedString(text))
        }
    }

    static func clean(_ fragment: String) -> String {
        var t = fragment.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        if let r = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = t as NSString
            for m in r.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let code = Int(ns.substring(with: m.range(at: 1))), let scalar = UnicodeScalar(code) {
                    t = (t as NSString).replacingCharacters(in: m.range, with: String(Character(scalar)))
                }
            }
        }
        return t.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChronicleReader: View {
    let story: ChronicleStory
    @State private var blocks: [ChronicleBlock] = []
    @State private var failed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let image = story.imageURL {
                    AsyncImage(url: image) { $0.resizable().scaledToFit() } placeholder: { Color.clear.frame(height: 0) }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                }
                if blocks.isEmpty {
                    Text(story.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    if let date = story.date { Text(date, style: .date).font(.subheadline).foregroundStyle(.secondary) }
                    Text(story.summary).font(.body)
                    if failed {
                        Text("The full story couldn't be loaded. Check your connection, or open it on the website.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ProgressView("Loading story")
                    }
                } else {
                    if let date = story.date { Text(date, style: .date).font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                Button {
                    openURL(story.url)
                } label: {
                    Label("Open on website", systemImage: "safari").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Chronicle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: story.url) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share story")
            }
        }
        .task { await load() }
    }

    @ViewBuilder private func blockView(_ block: ChronicleBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(level == 1 ? .largeTitle.bold() : level == 2 ? .title2.bold() : .title3.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.top, level == 1 ? 0 : 8)
        case .paragraph:
            Text(block.text).font(.body).lineSpacing(4)
        case .quote:
            Text(block.text).font(.body.italic()).padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Brand.gold).frame(width: 3) }
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").accessibilityHidden(true)
                Text(block.text).font(.body)
            }
        }
    }

    private func load() async {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chronicle-\(story.url.lastPathComponent).html")
        if let data = try? Data(contentsOf: cache), let html = String(data: data, encoding: .utf8) {
            blocks = ChronicleArticleParser.blocks(fromHTML: html)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: story.url)
            try? data.write(to: cache, options: .atomic)
            if let html = String(data: data, encoding: .utf8) {
                let parsed = ChronicleArticleParser.blocks(fromHTML: html)
                if !parsed.isEmpty { blocks = parsed }
            }
        } catch {
            failed = blocks.isEmpty
        }
    }
}

/// Maps `mrblindbandit://article/<slug>` and `https://mrblindbandit.net/publications/<slug>/` to the
/// article's web URL so the native reader can open it.
enum ChronicleDeepLink {
    static func articleURL(from url: URL) -> URL? {
        var slug: String?
        if url.scheme?.lowercased() == "mrblindbandit", url.host?.lowercased() == "article" {
            slug = url.pathComponents.filter { $0 != "/" }.first
        } else if ["mrblindbandit.net", "www.mrblindbandit.net"].contains(url.host?.lowercased() ?? ""),
                  url.pathComponents.count >= 3, url.pathComponents[1] == "publications" {
            slug = url.pathComponents[2]
        }
        guard let slug, slug.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://mrblindbandit.net/publications/\(slug)/")
    }

    static func story(for url: URL) -> ChronicleStory {
        let title = url.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
        return ChronicleStory(id: url.absoluteString, title: title, summary: "", url: url, date: nil)
    }
}

struct DeepLinkedArticle: Identifiable { let url: URL; var id: String { url.absoluteString } }
