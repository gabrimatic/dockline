import Darwin
import AppKit
import SwiftUI

/// Facts about this build, as the bundle states them.
enum AppInfo {
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 Soroush Yousefpour"
    }

    /// The tagline as the About panel sets it: two lines, broken by hand, because at that width a
    /// single line fits and the break would otherwise depend on the font.
    static let taglineLines = ["Every window, sharp,", "from your Dock."]
    /// The tagline as one sentence, for places that wrap it themselves.
    static let tagline = taglineLines.joined(separator: " ")
}

// MARK: - Welcome

/// First launch: what Dockline does in one line, the two permissions it needs with the system's own
/// prompts behind buttons, and the login item. Done, Esc and the close button all end it the same
/// way. The window is a flat ground, and its one accent button is the next step.
struct WelcomeView: View {
    let permissions: Permissions
    let onDone: @MainActor () -> Void
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginNote: String?

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("Welcome to Dockline")
                    .font(Typeface.font(24, .light))
                    .foregroundStyle(Theme.text)
                Text("Rest the pointer on a Dock icon to see every window of that app, sharp, and one click away.")
                    .font(Typeface.font(13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)

            VStack(spacing: 0) {
                PermissionRow(kind: .accessibility, permissions: permissions)
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 12)
                PermissionRow(kind: .screen, permissions: permissions)
            }
            .welcomeCard()

            LoginRow(enabled: loginEnabled, note: loginNote, set: setLogin)

            // One accent button per surface: Allow while the permission is open, Done once it is granted.
            PillButton(title: "Done", prominent: permissions.trusted && permissions.canCapture, height: 36, fullWidth: true, action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 460)
        .tint(Theme.accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            loginEnabled = LoginItem.isEnabled
        }
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

/// One permission: what it is for, a button for the system prompt, and its live state.
struct PermissionRow: View {
    enum Kind { case accessibility, screen }
    let kind: Kind
    let permissions: Permissions

    private var allowed: Bool { kind == .accessibility ? permissions.trusted : permissions.canCapture }
    private var title: String { kind == .accessibility ? "Accessibility" : "Screen Recording" }
    /// The prompt was answered "no": only then is System Settings the way forward.
    private var needsSettings: Bool { kind == .accessibility ? permissions.needsSettingsFallback : permissions.captureRequested }
    private var symbol: String { kind == .accessibility ? "hand.raised" : "rectangle.dashed.badge.record" }
    private var detail: String {
        kind == .accessibility
            ? "Lets Dockline see which Dock icon the pointer is on, list an app's windows and bring one forward."
            : "Lets Dockline take pictures of your windows. They stay in memory on this Mac and never reach the disk."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title).font(Typeface.font(13)).foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    if allowed {
                        Label {
                            Text("Allowed").foregroundStyle(Theme.text)
                        } icon: {
                            Image(systemName: "checkmark").foregroundStyle(Theme.text)
                        }
                        .font(Typeface.font(12))
                        .fixedSize()
                        .accessibilityLabel("\(title) allowed")
                    } else {
                        // One accent button per surface: the next permission to allow.
                        PillButton(title: needsSettings ? "Open System Settings" : "Allow…",
                                   prominent: kind == .accessibility || permissions.trusted) { request() }
                            .accessibilityHint(needsSettings ? "Opens Privacy and Security." : "Shows the macOS permission prompt.")
                    }
                }
                Text(detail)
                    .font(Typeface.font(11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .animation(.default, value: allowed)
    }

    private func request() {
        if kind == .screen { permissions.requestScreenRecording() }
        else if needsSettings { permissions.openAccessibilitySettings() }
        else { permissions.requestAccessibility() }
    }
}

/// Launch at login in the welcome window: the name on the left, the switch on the right.
struct LoginRow: View {
    let enabled: Bool
    let note: String?
    let set: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Launch at login").font(Typeface.font(13)).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Toggle("Launch at login", isOn: .snapshot(enabled, set: set))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if let note {
                Text(note).font(Typeface.font(11)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(12)
        .welcomeCard()
    }
}

/// A capsule text button drawn without its own glass, so a surface never stacks glass on glass.
struct PillButton: View {
    let title: String
    let prominent: Bool
    var height: CGFloat = 26
    var fullWidth = false
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typeface.font(height > 30 ? 13 : 12, .medium))
                .padding(.horizontal, 12)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .foregroundStyle(prominent ? Theme.onAccent : Theme.text)
                .background(Capsule().fill(prominent ? Theme.accent : Theme.fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension View {
    /// A flat card on the flat ground: a faint fill and a hairline.
    func welcomeCard() -> some View {
        background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// The flat ground of the design language under the whole window, title bar included: ink in the
    /// dark appearance, paper in the light one.
    func groundWindowBackground() -> some View {
        background { Theme.ground.ignoresSafeArea() }
    }
}

/// A titled window that Esc closes, like a sheet.
final class EscapableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

/// A titled window on the flat ground, with only a close button. It is sized to its
/// content first and centred after: a window centred before it has its size lands off to the side.
/// It keeps following its content's size afterwards.
@MainActor
func makeAppWindow<Content: View>(title: String, content: Content) -> NSWindow {
    let hosting = NSHostingController(rootView: content.groundWindowBackground())
    hosting.sizingOptions = [.preferredContentSize]
    let w = EscapableWindow(contentViewController: hosting)
    w.styleMask = [.titled, .closable, .fullSizeContentView]
    w.title = title
    w.titlebarAppearsTransparent = true
    w.titleVisibility = .hidden
    w.isMovableByWindowBackground = true
    w.isReleasedWhenClosed = false
    w.backgroundColor = Theme.groundNS
    w.standardWindowButton(.miniaturizeButton)?.isHidden = true
    w.standardWindowButton(.zoomButton)?.isHidden = true
    hosting.view.layoutSubtreeIfNeeded()
    let size = hosting.view.fittingSize
    if size.width > 0, size.height > 0 { w.setContentSize(size) }
    w.center()
    return w
}

@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()
    private(set) var window: NSWindow?
    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let view = WelcomeView(permissions: Permissions.shared) { [weak self] in self?.window?.performClose(nil) }
            let w = makeAppWindow(title: "Welcome to Dockline", content: view)
            w.delegate = self
            window = w
        }
        Permissions.shared.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Done, Esc and the close button all end it the same way, and it never comes back on its own.
    func windowWillClose(_ notification: Notification) {
        AppSettings.shared.onboardingDone = true
        window = nil
    }
}

// MARK: - About

/// The About panel's content. The window around it is the flat ground, so this draws no
/// background of its own.
struct AboutView: View {
    static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
                .padding(.bottom, 6)
            Text("Dockline").font(Typeface.font(24, .light)).foregroundStyle(Theme.text)
            Text("Version \(AppInfo.version)")
                .font(Typeface.font(12))
                .foregroundStyle(Theme.secondary)
            Text(AppInfo.taglineLines.joined(separator: "\n"))
                .font(Typeface.font(13))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text(AppInfo.copyright)
                .font(Typeface.font(11))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 10)
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 28)
        .frame(width: Self.width)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    static let shared = AboutWindowController()
    private(set) var window: NSWindow?

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

    func show() {
        if window == nil {
            let w = makeAppWindow(title: "About Dockline", content: AboutView())
            w.delegate = self
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
