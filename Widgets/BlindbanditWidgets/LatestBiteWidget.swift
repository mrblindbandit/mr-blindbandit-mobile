import WidgetKit
import SwiftUI

struct LatestBiteEntry: TimelineEntry {
    let date: Date
    let author: String
    let body: String
    let id: String
}

struct LatestBiteProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestBiteEntry {
        .init(date: .now, author: "@bandit", body: "What’s cooking on Bandit Feed…", id: "")
    }
    func getSnapshot(in context: Context, completion: @escaping (LatestBiteEntry) -> Void) {
        completion(current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestBiteEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
    private func current() -> LatestBiteEntry {
        .init(
            date: .now,
            author: BanditSharedStore.latestBiteAuthor.isEmpty ? "Bandit Feed" : BanditSharedStore.latestBiteAuthor,
            body: BanditSharedStore.latestBiteBody.isEmpty ? "Open Blind Bandit for the latest Bite." : BanditSharedStore.latestBiteBody,
            id: BanditSharedStore.latestBiteID
        )
    }
}

struct LatestBiteWidget: Widget {
    let kind = "LatestBiteWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestBiteProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                Label(entry.author, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                Text(entry.body)
                    .font(.subheadline)
                    .lineLimit(4)
                Spacer(minLength: 0)
            }
            .padding()
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "blindbandit://bites/\(entry.id)"))
        }
        .configurationDisplayName("Latest Bite")
        .description("The newest Bite from Bandit Feed.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
