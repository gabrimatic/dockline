import Darwin
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .permissions: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private(set) var window: NSWindow?
    private let selection = PaneSelection()

    /// A closed window is let go entirely, so its SwiftUI tree holds no memory while the app runs.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        closing.delegate = nil
        window = nil
        // After the close finishes, so AppKit is done with the views.
        Task { @MainActor in
            closing.contentViewController = nil
            // SwiftUI finishes tearing the tree down over the next moments.
            try? await Task.sleep(for: .seconds(3))
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    func show(pane: SettingsPane? = nil) {
        if let pane { selection.pane = pane }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(selection: selection))
            hosting.sizingOptions = []
            let w = NSWindow(contentViewController: hosting)
            // Like System Settings: the window is titled with the pane that is open.
            w.title = (selection.pane ?? .general).title
            selection.onChange = { [weak w] pane in w?.title = pane.title }
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.titlebarSeparatorStyle = .none
            let toolbar = NSToolbar(identifier: "DocklineSettings")
            toolbar.displayMode = .iconOnly
            w.toolbar = toolbar
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentMinSize = NSSize(width: 680, height: 500)
            w.setContentSize(NSSize(width: 720, height: 540))
            w.setFrameAutosaveName("DocklineSettings")
            if w.frame.origin == .zero { w.center() }
            window = w
        }
        window?.title = (selection.pane ?? .general).title
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor @Observable
final class PaneSelection {
    var pane: SettingsPane? = .general {
        didSet { if let pane { onChange?(pane) } }
    }
    @ObservationIgnored var onChange: ((SettingsPane) -> Void)?
}

/// The window: a flat sidebar of panes, a hairline, and the pane beside it under its title. The same
/// layout in every one of these apps, with the ground, text and accent from the palette.
struct SettingsView: View {
    @Bindable var selection: PaneSelection

    private var pane: SettingsPane { selection.pane ?? .general }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: selection)
                .frame(width: 200)
            Rectangle().fill(Theme.divider).frame(width: 1)
            Group {
                switch pane {
                case .general: GeneralPane()
                case .permissions: PermissionsPane()
                case .about: AboutPane()
                }
            }
            .font(Typeface.font(13))
            .scrollEdgeEffectStyle(.soft, for: .top)
            // The pane's title in the unified toolbar's row. Content scrolling under it fades out.
            .safeAreaBar(edge: .top, spacing: 0) {
                Text(pane.title)
                    .font(Typeface.font(22, .light))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30)
                    .frame(height: 56)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(minWidth: 460, minHeight: 500)
        }
        .background(Theme.ground)
        .tint(Theme.accent)
        .ignoresSafeArea()
    }
}

private struct SettingsSidebar: View {
    @Bindable var selection: PaneSelection
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { pane in
                SidebarRow(pane: pane, selected: selection.pane == pane) { selection.pane = pane }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        // Below the traffic lights.
        .padding(.top, 52)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let all = SettingsPane.allCases
        guard let current = selection.pane, let index = all.firstIndex(of: current) else { return .ignored }
        selection.pane = all[min(max(index + step, 0), all.count - 1)]
        return .handled
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 20)
                Text(pane.title).font(Typeface.font(13, .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Theme.text : Theme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.34) : (hovering ? Theme.surface : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(pane.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Look

extension View {
    /// A pane's grouped form on the paper or ink ground, its groups a faint fill instead of the
    /// system's grey, in the palette and Plex.
    fileprivate func settingsForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .listRowBackground(Theme.surface)
    }

    /// A section footer: small, quiet.
    fileprivate func footnote() -> some View {
        font(Typeface.font(11)).foregroundStyle(Theme.secondary)
    }

    /// A section header: a word above its group, regular weight.
    fileprivate func sectionHeader() -> some View {
        font(Typeface.font(12)).foregroundStyle(Theme.secondary)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable private var settings = AppSettings.shared
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginNote: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show windows when the pointer is on a Dock icon", isOn: $settings.dockPreviews)
                Picker("Size", selection: $settings.previewSize) {
                    ForEach(PreviewSize.allCases) { Text($0.title).tag($0) }
                }
                Picker("Appear", selection: $settings.hoverDelay) {
                    ForEach(HoverDelay.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Dock previews").sectionHeader()
            } footer: {
                Text("Dockline keeps a sharp picture of each window while it is in front, so a window Stage Manager has parked still shows at full size. Pictures stay in memory and never reach the disk.")
                    .footnote()
            }
            Section {
                Toggle("Switch windows with Option-Tab", isOn: $settings.switcher)
            } header: {
                Text("Window switcher").sectionHeader()
            } footer: {
                Text("Hold Option and press Tab to move through every window, most recent first. Shift goes back, Esc cancels, and letting go switches.")
                    .footnote()
            }
            Section {
                Toggle("Launch at login", isOn: .snapshot(loginEnabled, set: setLogin))
                if let loginNote { Text(loginNote).footnote() }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                Toggle("Pause Dockline", isOn: $settings.paused)
            } footer: {
                if !settings.showMenuBarIcon {
                    Text("Open Dockline again from Spotlight or Finder to come back here.").footnote()
                }
            }
        }
        .settingsForm()
    }

    private func setLogin(_ on: Bool) {
        if let error = LoginItem.set(on) {
            loginNote = "Could not change the login item: \(error)"
        } else {
            loginNote = LoginItem.needsApproval ? "Approve Dockline in System Settings > General > Login Items." : nil
        }
        loginEnabled = LoginItem.isEnabled
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    private var permissions = Permissions.shared

    var body: some View {
        Form {
            Section {
                PermissionRow(kind: .accessibility, permissions: permissions)
                PermissionRow(kind: .screen, permissions: permissions)
            } footer: {
                Text("Dockline makes no network requests. Window pictures stay in memory on this Mac, and password managers are never captured.")
                    .footnote()
            }
            Section {
                LabeledContent {
                    Button("Show Again") {
                        AppSettings.shared.onboardingDone = false
                        Permissions.shared.resetRequested()
                        WelcomeWindowController.shared.show()
                    }
                } label: {
                    Text("Welcome window")
                    Text("Show the first-run window again.")
                }
            }
        }
        .settingsForm()
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dockline").font(Typeface.font(22, .light))
                        Text("Version \(AppInfo.version)").foregroundStyle(Theme.secondary)
                        Text(AppInfo.tagline).foregroundStyle(Theme.secondary)
                        Text(AppInfo.copyright).font(Typeface.font(11)).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Preview", value: "Rest the pointer on a Dock icon")
                LabeledContent("Bring a window forward", value: "Click its card")
                LabeledContent("Close, minimize, full screen", value: "Point at a card")
                LabeledContent("Switch windows", value: "Option-Tab")
            } header: {
                Text("Using Dockline").sectionHeader()
            }
        }
        .settingsForm()
    }
}
