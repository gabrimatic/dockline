// The Control Center and menu bar control for Dockline. Its action, ToggleDocklineIntent, is
// shared with the app and runs only in the app's own process, so pausing and resuming
// never crosses an unauthenticated channel.
import AppIntents
import SwiftUI
import WidgetKit

@main
struct DocklineControls: WidgetBundle {
    var body: some Widget {
        PauseControl()
    }
}

struct PauseControl: ControlWidget {
    static let kind = "info.gabrimatic.dockline.toggle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleDocklineIntent()) {
                Label("Pause or Resume Dockline", systemImage: "pause.circle")
            }
        }
        .displayName("Dockline")
        .description("Pauses or resumes Dockline.")
    }
}
