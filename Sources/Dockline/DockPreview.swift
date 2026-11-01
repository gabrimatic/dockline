import AppKit
import SwiftUI
import os

/// The panel over a Dock icon: every window of the app, sharp, one click from the front.
@MainActor
final class DockPreview {
    private let log = Logger(subsystem: "info.gabrimatic.dockline", category: "preview")
    private let settings: AppSettings
    private let model = PreviewModel()
    private let panel = FloatingPanel()
    private var hosting: FirstClickHostingView<PreviewRoot>?
    private var item: DockItem?
    /// The icon the panel belongs to, kept while the pointer is on the panel.
    private var shown: DockItem?
    private var app: NSRunningApplication?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private(set) var isVisible = false
    /// A picture this old is taken again while its card is on screen.
    static let liveEvery: Duration = .milliseconds(800)
    /// Long enough to cross from the icon to the panel.
    static let hideGrace: Duration = .milliseconds(320)
    static let gap: CGFloat = 8
    static let switchDelay = 0.13

    init(settings: AppSettings) { self.settings = settings }

    /// The Dock's selection moved.
    func hover(_ item: DockItem?) {
        guard !settings.isPaused, settings.dockPreviews else { hide(); return }
        guard let item else {
            showTask?.cancel()
            self.item = nil
            return
        }
        guard item.url != self.item?.url || !isVisible else { return }
        self.item = item
        showTask?.cancel()
        // With a panel up, a moment's wait lets the pointer cross a neighbour on its way there.
        let wait = isVisible ? Self.switchDelay : settings.hoverDelay.seconds
        showTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.present(item)
        }
    }

    private func present(_ item: DockItem, refreshing: Bool = false) async {
        let target = item.url.standardizedFileURL
        // An app that is not running has no windows. Passing over its icon on the way to the panel is
        // the same as leaving the icons.
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.standardizedFileURL == target }) else {
            self.item = nil
            return
        }
        let pid = app.processIdentifier
        let windows = await Task.detached(priority: .userInitiated) { WindowIndex.windows(of: pid) }.value
        guard refreshing || (!Task.isCancelled && self.item == item) else { return }
        self.app = app
        shown = item
        model.mode = .dock
        model.appName = app.localizedName ?? item.title
        model.appIcon = app.icon
        model.icons = [pid: app.icon ?? NSImage()]
        model.names = [pid: model.appName]
        model.cardHeight = settings.previewSize.height
        model.hovered = nil
        model.readDisplayOptions()
        let screen = NSScreen.screens.first { $0.frame.intersects(item.frame) } ?? NSScreen.main
        model.arrange(windows.map { PreviewCard(info: $0.info, handle: $0.handle, image: Keeper.shared.picture($0.info.id)) },
                      limit: (screen?.frame.width ?? 1_200) - 120)
        installHosting()
        place(item, on: screen)
        if !isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            isVisible = true
            watchClicks()
            followPointer()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                withAnimation(self.model.reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.26, bounce: 0.14)) { self.model.appeared = true }
            }
        }
        // SwiftUI takes the new content on its next pass: size the panel after it.
        DispatchQueue.main.async { [weak self] in self?.place(item, on: screen) }
        keepLive(windows.map(\.info))
    }

    private func installHosting() {
        guard hosting == nil else { return }
        let view = FirstClickHostingView(rootView: PreviewRoot(model: model, handlers: handlers()))
        view.sizingOptions = [.intrinsicContentSize]
        panel.contentView = view
        hosting = view
    }

    /// Above a bottom Dock, beside a side one, centred on the icon and fully on screen.
    private func place(_ item: DockItem, on screen: NSScreen?) {
        guard let hosting, let screen else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 20, size.height > 20 else { return }
        let area = screen.frame, icon = item.frame, pad = PreviewRoot.padding
        let toLeft = icon.minX - area.minX, toRight = area.maxX - icon.maxX, toBottom = icon.minY - area.minY
        var origin: CGPoint
        if toBottom <= min(toLeft, toRight) {
            origin = CGPoint(x: icon.midX - size.width / 2, y: icon.maxY + Self.gap - pad)
        } else if toLeft < toRight {
            origin = CGPoint(x: icon.maxX + Self.gap - pad, y: icon.midY - size.height / 2)
        } else {
            origin = CGPoint(x: icon.minX - Self.gap - size.width + pad, y: icon.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, area.minX - pad + 8), area.maxX - size.width + pad - 8)
        origin.y = min(max(origin.y, area.minY - pad + 8), area.maxY - size.height + pad - 8)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    /// Windows that can be seen at full size stay current while their cards are up.
    private func keepLive(_ windows: [WindowInfo]) {
        liveTask?.cancel()
        let live = windows.filter { !$0.parked && !$0.minimized && !$0.elsewhere }
        guard !live.isEmpty else { return }
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                for window in live {
                    guard !Task.isCancelled else { return }
                    if await Keeper.shared.keep(window), let image = Keeper.shared.picture(window.id) { self?.model.update(window.id, image: image) }
                }
                try? await Task.sleep(for: Self.liveEvery)
            }
        }
    }

    /// The panel stays while the pointer is on it or on its icon. Position decides, not the Dock's word
    /// that the pointer left, which does not always come. This only runs with a panel open.
    private func followPointer() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            var awaySince: ContinuousClock.Instant?
            while !Task.isCancelled, let self, self.isVisible {
                let pointer = NSEvent.mouseLocation
                let onPanel = self.panel.frame.insetBy(dx: PreviewRoot.padding - 4, dy: PreviewRoot.padding - 4).contains(pointer)
                let onIcon = self.shown?.frame.insetBy(dx: -14, dy: -14).contains(pointer) ?? false
                if onPanel || onIcon {
                    awaySince = nil
                } else if let since = awaySince {
                    if since.duration(to: .now) >= Self.hideGrace { self.hide(); return }
                } else {
                    awaySince = .now
                }
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    func hide() {
        showTask?.cancel()
        hideTask?.cancel()
        liveTask?.cancel()
        item = nil
        guard isVisible else { return }
        isVisible = false
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        model.appeared = false
        panel.orderOut(nil)
        model.rows = []
    }

    /// A click anywhere else, the Dock included, ends the preview.
    private func watchClicks() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func handlers() -> PreviewHandlers {
        var h = PreviewHandlers()
        h.focus = { [weak self] card in
            WindowIndex.focus(card.info, handle: card.handle)
            self?.hide()
        }
        h.close = { [weak self] card in
            self?.liveTask?.cancel()
            WindowIndex.close(card.handle)
            self?.refreshSoon()
        }
        h.minimize = { [weak self] card in
            // A picture taken while the window is flying to the Dock would replace the sharp one.
            self?.liveTask?.cancel()
            WindowIndex.setMinimized(!card.info.minimized, card.handle)
            self?.refreshSoon()
        }
        h.fullScreen = { [weak self] card in
            WindowIndex.focus(card.info, handle: card.handle)
            WindowIndex.toggleFullScreen(card.handle)
            self?.hide()
        }
        h.hideApp = { [weak self] in
            self?.app?.hide()
            self?.hide()
        }
        h.quitApp = { [weak self] in
            self?.app?.terminate()
            self?.hide()
        }
        h.openApp = { [weak self] in
            if let url = self?.app?.bundleURL { NSWorkspace.shared.open(url) }
            self?.hide()
        }
        return h
    }

    private func refreshSoon() {
        guard let shown else { return }
        Task { [weak self] in
            // Past the minimize animation.
            try? await Task.sleep(for: .milliseconds(750))
            guard let self, self.isVisible else { return }
            await self.present(shown, refreshing: true)
        }
    }
}
