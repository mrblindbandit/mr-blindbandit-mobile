import ActivityKit
import WidgetKit
import SwiftUI

struct CallLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallActivityAttributes.self) { context in
            HStack {
                VStack(alignment: .leading) {
                    Text(context.attributes.displayName)
                        .font(.headline)
                    Text(context.state.phase == "ringing" ? "Ringing…" : "On call")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(timerText(context.state.elapsedSeconds))
                    .monospacedDigit()
                    .font(.title2.weight(.semibold))
                if context.state.muted {
                    Image(systemName: "mic.slash.fill")
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.displayName).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerText(context.state.elapsedSeconds)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(context.state.muted ? "Muted" : "Mic on", systemImage: context.state.muted ? "mic.slash" : "mic")
                        Spacer()
                        Text(context.state.phase.capitalized)
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "phone.fill")
            } compactTrailing: {
                Text(timerText(context.state.elapsedSeconds)).monospacedDigit().font(.caption2)
            } minimal: {
                Image(systemName: "phone.fill")
            }
        }
    }

    private func timerText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct BitePostLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BitePostActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.state.detail).font(.subheadline.weight(.semibold))
                ProgressView(value: context.state.progress)
                Text(context.attributes.draftPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.detail)
                        ProgressView(value: context.state.progress)
                    }
                }
            } compactLeading: {
                Image(systemName: "square.and.arrow.up")
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2)
            } minimal: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
}
