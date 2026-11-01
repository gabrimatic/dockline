import AppKit
import ApplicationServices
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import os

/// Keeps a sharp picture of every window. Stage Manager really shrinks the windows in its strip, so a
/// capture taken on hover can only ever see a thumbnail. The keeper takes its picture while a window
/// is in front at full size and holds on to it. Pictures stay in memory, compressed, and never reach the
/// disk, and an app that keeps secrets is never captured.
@MainActor
final class Keeper {
    static let shared = Keeper()

    private struct Shot {
        let data: Data
        var used: UInt64
    }

    /// The longest side a picture needs: a large card at 2x.
    nonisolated static let longestSide: CGFloat = 1_000
    /// About 150 windows' worth.
    private static let limit = 24 * 1_024 * 1_024
    private static let neverCaptured: Set<String> = ["com.apple.keychainaccess", "com.apple.Passwords", "com.1password.1password", "com.bitwarden.desktop"]

    private let log = Logger(subsystem: "info.gabrimatic.dockline", category: "keeper")
    private var shots: [CGWindowID: Shot] = [:]
    private var total = 0
    private var clock: UInt64 = 0
    private var capturable: [CGWindowID: SCWindow] = [:]
    private var inFlight = Set<CGWindowID>()
    /// Shown pictures, decoded: the system drops these first when memory is tight.
    private let decoded = NSCache<NSNumber, NSImage>()

    private init() { decoded.countLimit = 24 }

    func hasPicture(_ id: CGWindowID) -> Bool { shots[id] != nil }

    func picture(_ id: CGWindowID) -> NSImage? {
        guard let shot = shots[id] else { return nil }
        clock += 1
        shots[id]?.used = clock
        if let image = decoded.object(forKey: NSNumber(value: id)) { return image }
        guard let image = NSImage(data: shot.data) else { return nil }
        decoded.setObject(image, forKey: NSNumber(value: id))
        return image
    }

    /// Takes a fresh picture of a window. A window that is parked, minimized or in an app that keeps
    /// secrets is left alone, so a sharp picture is never replaced by a worse one.
    @discardableResult
    func keep(_ info: WindowInfo) async -> Bool {
        guard !info.parked, !info.minimized, !info.elsewhere, CGPreflightScreenCaptureAccess(), !inFlight.contains(info.id),
              NSRunningApplication(processIdentifier: info.pid)?.bundleIdentifier.map({ !Self.neverCaptured.contains($0) }) ?? false,
              let window = await window(info.id) else { return false }
        inFlight.insert(info.id)
        defer { inFlight.remove(info.id) }
        let scale = min(2, Self.longestSide / max(info.size.width, info.size.height, 1))
        let configuration = SCStreamConfiguration()
        configuration.width = Int(info.size.width * scale)
        configuration.height = Int(info.size.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.scalesToFit = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
            capturable[info.id] = nil
            return false
        }
        let data = await Task.detached(priority: .utility) { Self.compressed(image) }.value
        guard let data else { return false }
        store(data, for: info.id)
        return true
    }

    private func window(_ id: CGWindowID) async -> SCWindow? {
        if let known = capturable[id] { return known }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return nil }
        capturable = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        return capturable[id]
    }

    /// HEIC keeps the transparent corners of a window, which JPEG would fill in.
    private nonisolated static func compressed(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private func store(_ data: Data, for id: CGWindowID) {
        total += data.count - (shots[id]?.data.count ?? 0)
        clock += 1
        shots[id] = Shot(data: data, used: clock)
        decoded.removeObject(forKey: NSNumber(value: id))
        while total > Self.limit, let oldest = shots.min(by: { $0.value.used < $1.value.used })?.key, oldest != id { drop(oldest) }
    }

    private func drop(_ id: CGWindowID) {
        total -= shots[id]?.data.count ?? 0
        shots[id] = nil
        capturable[id] = nil
        decoded.removeObject(forKey: NSNumber(value: id))
    }

    /// Lets go of the pictures of windows that no longer exist.
    func dropClosedWindows() {
        guard !shots.isEmpty, let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return }
        let alive = Set(list.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        for id in shots.keys where !alive.contains(id) { drop(id) }
    }
}
