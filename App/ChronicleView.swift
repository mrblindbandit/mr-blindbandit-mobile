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

    func load() async {
        loading = true; defer { loading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.feedURL)
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
                Text(message).foregroundStyle(.secondary)
            }
            ForEach(feed.stories) { story in
                NavigationLink {
                    Website(path: story.url.path, title: "Chronicle")
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
