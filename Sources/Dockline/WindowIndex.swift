import AppKit
import ApplicationServices

/// One real window of an app. `size` is the window's true size from Accessibility. Stage Manager shrinks
/// a window in its strip for the window server too, so the two only agree when the window is full size.
struct WindowInfo: Identifiable, Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let size: CGSize
    let minimized: Bool
    /// Stage Manager has it in the strip: no capture can see it at full size now.
    let parked: Bool
    /// It lives in another Space, or Accessibility cannot reach it.
    let elsewhere: Bool
}

/// The Accessibility handle of a window, for acting on it.
final class WindowHandle: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
}

/// Finds an app's real windows: no helpers, tab strips or tooltips.
enum WindowIndex {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    /// Private but long stable. Loaded at runtime: without it, no Accessibility window matches, and
    /// only the window server's titled windows show, as icon cards with no controls.
    private static let getWindow: GetWindow? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
        .map { unsafeBitCast($0, to: GetWindow.self) }
    static let minimumSide: CGFloat = 120
    /// A window this much narrower on the server than it really is sits in the strip.
    static let parkedShare: CGFloat = 0.7

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        guard let raw = value(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // The type was checked above.
        return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cgSize, &size) ? size : nil
    }

    /// What the window server knows about every window of a process.
    private static func serverWindows(pid: pid_t) -> [(id: CGWindowID, bounds: CGRect, title: String)] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard (entry[kCGWindowOwnerPID as String] as? pid_t) == pid, (entry[kCGWindowLayer as String] as? Int) == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let raw = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw) else { return nil }
            return (id, bounds, entry[kCGWindowName as String] as? String ?? "")
        }
    }

    /// Runs off the main thread: a busy app can take its timeout to answer.
    static func windows(of pid: pid_t) -> [(info: WindowInfo, handle: WindowHandle?)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let server = serverWindows(pid: pid)
        let elements = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        var standard: [(WindowInfo, WindowHandle?)] = [], dialogs: [(WindowInfo, WindowHandle?)] = []
        for element in elements {
            var id: CGWindowID = 0
            guard let getWindow, getWindow(element, &id) == .success, id != 0, let size = size(of: element),
                  size.width >= minimumSide, size.height >= minimumSide else { continue }
            let subrole = value(element, kAXSubroleAttribute) as? String
            let title = value(element, kAXTitleAttribute) as? String ?? ""
            let minimized = value(element, kAXMinimizedAttribute) as? Bool ?? false
            let bounds = server.first { $0.id == id }?.bounds
            let parked = !minimized && (bounds.map { $0.width < size.width * parkedShare } ?? false)
            let info = WindowInfo(id: id, pid: pid, title: title, size: size, minimized: minimized, parked: parked, elsewhere: false)
            if subrole == (kAXStandardWindowSubrole as String) {
                standard.append((info, WindowHandle(element)))
            } else if subrole == (kAXDialogSubrole as String), !title.isEmpty {
                dialogs.append((info, WindowHandle(element)))
            }
        }
        // A panel-only app such as a player still has a window; apps with real windows keep only those.
        var result = standard.isEmpty ? dialogs : standard
        // Windows on other Spaces are not in Accessibility, but they have a server title.
        let known = Set(result.map(\.0.id))
        for window in server where !known.contains(window.id) && !window.title.isEmpty
            && window.bounds.width >= 200 && window.bounds.height >= 150 {
            result.append((WindowInfo(id: window.id, pid: pid, title: window.title, size: window.bounds.size,
                                      minimized: false, parked: false, elsewhere: true), nil))
        }
        return result
    }

    // MARK: Acting on a window

    @MainActor static func focus(_ info: WindowInfo, handle: WindowHandle?) {
        guard let app = NSRunningApplication(processIdentifier: info.pid) else { return }
        if app.isHidden { app.unhide() }
        if let element = handle?.element {
            if info.minimized { AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        app.activate()
    }

    @MainActor static func close(_ handle: WindowHandle?) {
        guard let element = handle?.element, let raw = value(element, kAXCloseButtonAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return }
        AXUIElementPerformAction(unsafeDowncast(raw, to: AXUIElement.self), kAXPressAction as CFString)
    }

    @MainActor static func setMinimized(_ on: Bool, _ handle: WindowHandle?) {
        guard let element = handle?.element else { return }
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    @MainActor static func toggleFullScreen(_ handle: WindowHandle?) {
        guard let element = handle?.element else { return }
        let on = value(element, "AXFullScreen") as? Bool ?? false
        AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, on ? kCFBooleanFalse : kCFBooleanTrue)
    }
}
