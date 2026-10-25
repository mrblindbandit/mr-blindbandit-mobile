import WidgetKit
import SwiftUI

@main
struct BlindbanditWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UnreadDMsWidget()
        LatestBiteWidget()
        QuickActionsWidget()
        CallLiveActivityWidget()
        BitePostLiveActivityWidget()
        if #available(iOS 18.0, *) {
            MuteCallControl()
            EndCallControl()
            StartCallControl()
        }
    }
}
