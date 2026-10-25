import WidgetKit
import SwiftUI

struct QuickActionsEntry: TimelineEntry { let date: Date }

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) { completion(.init(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now)], policy: .never))
    }
}

struct QuickActionsWidget: Widget {
    let kind = "QuickActionsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsProvider()) { _ in
            HStack(spacing: 16) {
                Link(destination: URL(string: "blindbandit://call")!) {
                    Label("Call", systemImage: "phone.fill")
                }
                Link(destination: URL(string: "blindbandit://messages")!) {
                    Label("Message", systemImage: "message.fill")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Call / Message")
        .description("Jump into a Blind Bandit call or chat.")
        .supportedFamilies([.systemMedium, .systemSmall])
    }
}
