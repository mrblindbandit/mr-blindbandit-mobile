import WidgetKit
import SwiftUI

struct UnreadDMsEntry: TimelineEntry {
    let date: Date
    let count: Int
}

struct UnreadDMsProvider: TimelineProvider {
    func placeholder(in context: Context) -> UnreadDMsEntry { .init(date: .now, count: 3) }
    func getSnapshot(in context: Context, completion: @escaping (UnreadDMsEntry) -> Void) {
        completion(.init(date: .now, count: BanditSharedStore.unreadDMCount))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UnreadDMsEntry>) -> Void) {
        let entry = UnreadDMsEntry(date: .now, count: BanditSharedStore.unreadDMCount)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct UnreadDMsWidget: Widget {
    let kind = "UnreadDMsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UnreadDMsProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Text("Unread DMs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(entry.count)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text(entry.count == 1 ? "message" : "messages")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Unread DMs")
        .description("Blind Bandit unread direct messages.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}
