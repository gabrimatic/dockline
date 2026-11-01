import AppIntents

/// Pauses or resumes Dockline. Compiled into both the app and the Control Center extension,
/// so the control can name it, but it runs only inside the Dockline app: the extension has no
/// way to change Dockline, and no other process can send Dockline a pause or resume.
struct ToggleDocklineIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Dockline"
    static let description = IntentDescription("Pauses Dockline when it is on, and resumes it when it is paused.")

    /// Run in the main app only, never in an extension.
    @available(macOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if DOCKLINE_APP
        AppSettings.shared.paused.toggle()
        return .result(dialog: AppSettings.shared.paused ? "Dockline is paused." : "Dockline is on.")
        #else
        // Unreachable: the system runs this intent in the app. If it ever lands here, change nothing.
        return .result(dialog: "Open Dockline to pause or resume it.")
        #endif
    }
}
