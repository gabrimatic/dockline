import AppIntents
import Foundation

/// Dockline's actions for Shortcuts, Spotlight and Siri, plus its Focus filter. Each one runs in the
/// Dockline app on this Mac.

struct SetDocklinePausedIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Dockline"
    static let description = IntentDescription("Pauses or resumes Dockline's previews and switcher.")

    @Parameter(title: "Paused", default: true)
    var paused: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set Dockline paused to \(\.$paused)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppSettings.shared.paused = paused
        return .result(dialog: paused ? "Dockline is paused." : "Dockline is on.")
    }
}

/// Pause Dockline while a chosen Focus is on, from System Settings > Focus > Focus Filters.
struct DocklineFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Dockline"
    static let description: IntentDescription? = IntentDescription("Pause Dockline while this Focus is on.")

    /// Nil when the Focus turns off, which resumes Dockline.
    @Parameter(title: "Pause Dockline")
    var pause: Bool?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: pause == true ? "Pause Dockline" : "Keep Dockline on")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppSettings.shared.focusPaused = pause ?? false
        return .result()
    }
}

struct DocklineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleDocklineIntent(), phrases: ["Toggle \(.applicationName)", "Pause \(.applicationName)"],
                    shortTitle: "Toggle Dockline", systemImageName: "pause.circle")
    }
}
