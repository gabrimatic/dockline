import AppKit
import ApplicationServices
import os

/// The app icon under the pointer in the Dock.
struct DockItem: Equatable {
    let url: URL
    let title: String
    /// In Cocoa screen coordinates.
    let frame: CGRect
}

/// Hears which Dock icon is under the pointer from the Dock's own Accessibility notification. Nothing
/// polls and no input is watched, and clicks on the Dock stay the Dock's.
@MainActor
final class DockWatcher {
    private let log = Logger(subsystem: "info.gabrimatic.dockline", category: "dock")
    /// A new item, or nil when the pointer left the icons.
    var onHover: ((DockItem?) -> Void)?
    private var observer: AXObserver?
    private var dockPID: pid_t = 0
    private var token: NSObjectProtocol?
    private var list: AXUIElement?

    func start() {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            // The Dock restarts after a settings change or a crash.
            if bundle == "com.apple.dock" { MainActor.assumeIsolated { self?.attach() } }
        }
        attach()
    }

    func stop() {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = nil
        detach()
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        list = nil
        dockPID = 0
    }

    private func attach() {
        detach()
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let pid = dock.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
              let first = (children as? [AXUIElement])?.first else {
            log.info("the Dock is not answering yet")
            return
        }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<DockWatcher>.fromOpaque(refcon).takeUnretainedValue()
            nonisolated(unsafe) let element = element
            MainActor.assumeIsolated { watcher.selectionChanged(element) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(created, first, kAXSelectedChildrenChangedNotification as CFString, refcon) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        list = first
        dockPID = pid
        log.info("watching the Dock")
    }

    private func selectionChanged(_ element: AXUIElement) {
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedChildrenAttribute as CFString, &selected) == .success,
              let item = (selected as? [AXUIElement])?.first else {
            onHover?(nil)
            return
        }
        onHover?(Self.read(item))
    }

    private static func read(_ item: AXUIElement) -> DockItem? {
        func value(_ name: String) -> CFTypeRef? {
            var raw: CFTypeRef?
            return AXUIElementCopyAttributeValue(item, name as CFString, &raw) == .success ? raw : nil
        }
        guard value(kAXSubroleAttribute) as? String == "AXApplicationDockItem",
              let url = value(kAXURLAttribute) as? URL ?? (value(kAXURLAttribute) as? String).flatMap(URL.init(string:)),
              let position = value(kAXPositionAttribute), let size = value(kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin)
        AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
        let height = NSScreen.screens.first?.frame.height ?? 0
        return DockItem(url: url, title: value(kAXTitleAttribute) as? String ?? "",
                        frame: CGRect(x: origin.x, y: height - origin.y - extent.height, width: extent.width, height: extent.height))
    }
}
