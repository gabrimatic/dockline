import AppKit
import ApplicationServices
import os

/// Follows the window in front, and has the keeper take its picture: when it arrives, once Stage Manager
/// has settled, and every few seconds while someone is working in it. It keeps the order windows were used
/// in, for the switcher. Everything else is events: with nobody at the Mac its timer finds nothing to do.
@MainActor
final class FrontWatcher {
    private let log = Logger(subsystem: "info.gabrimatic.dockline", category: "front")
    /// Stage Manager's move into the centre takes about this long.
    static let settle: Duration = .milliseconds(650)
    static let refresh: TimeInterval = 6
    /// Without input for this long, the picture in hand is still right.
    static let idle: TimeInterval = 20

    private var tokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var timer: Timer?
    private var settling: Task<Void, Never>?
    private var locked = false
    /// Window ids, most recently used first.
    private(set) var recent: [CGWindowID] = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.frontChanged(pid) }
        })
        for (name, away) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.sessionDidResignActiveNotification, true),
                             (NSWorkspace.screensDidWakeNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.locked = away
                    if !away { self?.look() }
                }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, away) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedTokens.append(distributed.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.locked = away
                    if !away { self?.look() }
                }
            })
        }
        let timer = Timer(timeInterval: Self.refresh, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        frontChanged(NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    func stop() {
        guard running else { return }
        running = false
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens.removeAll()
        distributedTokens.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedTokens.removeAll()
        timer?.invalidate()
        timer = nil
        settling?.cancel()
        detach()
    }

    private func frontChanged(_ pid: pid_t?) {
        guard let pid, pid != ownPID else { return }
        if pid != observedPID { attach(pid) }
        look()
    }

    private func attach(_ pid: pid_t) {
        detach()
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FrontWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.look() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        observedPID = 0
    }

    private func tick() {
        guard !locked, CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) < Self.idle else { return }
        Task { await keepFront() }
    }

    /// The front window changed: wait for Stage Manager, then take its picture.
    private func look() {
        guard !locked else { return }
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            await self?.keepFront()
            Keeper.shared.dropClosedWindows()
        }
    }

    private func keepFront() async {
        guard observedPID != 0 else { return }
        let pid = observedPID
        let front = await Task.detached(priority: .utility) { Self.focused(pid) }.value
        guard let front else { return }
        recent.removeAll { $0 == front.id }
        recent.insert(front.id, at: 0)
        if recent.count > 200 { recent.removeLast(recent.count - 200) }
        await Keeper.shared.keep(front)
    }

    private nonisolated static func focused(_ pid: pid_t) -> WindowInfo? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var raw: CFTypeRef?
        let windows = WindowIndex.windows(of: pid)
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &raw) == .success, let raw,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return windows.first { !$0.info.elsewhere }?.info }
        let focused = unsafeDowncast(raw, to: AXUIElement.self)
        return windows.first { $0.handle.map { CFEqual($0.element, focused) } ?? false }?.info
    }
}
