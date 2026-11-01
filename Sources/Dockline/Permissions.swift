import AppKit
import ApplicationServices
import Observation

/// Accessibility trust, tracked without polling: macOS posts a distributed notification
/// whenever the Accessibility list changes, and the check is repeated whenever another app
/// comes forward (the usual next step after flipping the switch in System Settings), so a
/// missed notification never leaves Dockline waiting for a relaunch.
@MainActor @Observable
final class Permissions {
    static let shared = Permissions()
    static let accessibilityPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    private(set) var trusted = AXIsProcessTrusted()
    /// Screen Recording, for the pictures of windows. The pictures stay in memory on this Mac.
    private(set) var canCapture = CGPreflightScreenCaptureAccess()
    private(set) var captureRequested = UserDefaults.standard.bool(forKey: Permissions.captureRequestedKey)
    nonisolated static let captureRequestedKey = "screenRecordingRequested"
    static let screenRecordingPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    /// The system prompt has been asked for at least once. After that macOS shows no second
    /// prompt, so a still-missing grant has to be switched on in System Settings.
    private(set) var requested = UserDefaults.standard.bool(forKey: Permissions.requestedKey)
    nonisolated static let requestedKey = "accessibilityRequested"
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    private init() {
        tokens.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The trust database settles a moment after the notification.
            for delay in [0.3, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        })
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    func refresh() {
        let now = AXIsProcessTrusted(), capture = CGPreflightScreenCaptureAccess()
        guard now != trusted || capture != canCapture else { return }
        trusted = now
        canCapture = capture
        onChange?(now)
    }

    /// Shows the system's Screen Recording prompt once; after that the switch is in System Settings.
    func requestScreenRecording() {
        if captureRequested, let pane = Self.screenRecordingPane { NSWorkspace.shared.open(pane) }
        captureRequested = true
        UserDefaults.standard.set(true, forKey: Self.captureRequestedKey)
        CGRequestScreenCaptureAccess()
        refresh()
    }

    /// Shows the system's own Accessibility prompt, which also adds Dockline to the list, so nobody
    /// has to press "+" in System Settings. Returns whether access is already there.
    @discardableResult
    func requestAccessibility() -> Bool {
        // The documented option key (kAXTrustedCheckOptionPrompt), spelled out because the C global is not concurrency safe.
        let granted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        requested = true
        UserDefaults.standard.set(true, forKey: Self.requestedKey)
        refresh()
        return granted
    }

    /// Back to the state of a first launch: the next request shows the system prompt again
    /// (when macOS still allows it).
    func resetRequested() {
        requested = false
        captureRequested = false
        UserDefaults.standard.removeObject(forKey: Self.captureRequestedKey)
        UserDefaults.standard.removeObject(forKey: Self.requestedKey)
    }

    /// The pane button is for after the prompt was answered "no": only then is it the way forward.
    var needsSettingsFallback: Bool { requested && !trusted }

    func openAccessibilitySettings() {
        if let url = Self.accessibilityPane { NSWorkspace.shared.open(url) }
    }
}
