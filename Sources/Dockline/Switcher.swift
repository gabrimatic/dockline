import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Option-Tab: every window on the Mac, most recently used first. Hold Option and press Tab to move,
/// let go to switch. It needs no input monitoring: the shortcut is a system hot key, and the panel takes
/// the keyboard only while it is open.
@MainActor
final class Switcher {
    private let settings: AppSettings
    private let front: FrontWatcher
    private let model = PreviewModel()
    private let panel = FloatingPanel()
    private var hosting: FirstClickHostingView<PreviewRoot>?
    private var keyMonitor: Any?
    private var releaseTimer: Timer?
    private var opening = false
    private(set) var isOpen = false

    private static let carbonHandler: EventHandlerUPP = { _, event, _ in
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                          MemoryLayout<EventHotKeyID>.size, nil, &id)
        let backward = id.id == 2
        MainActor.assumeIsolated { Switcher.active?.pressed(backward: backward) }
        return noErr
    }
    private static weak var active: Switcher?
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(settings: AppSettings, front: FrontWatcher) {
        self.settings = settings
        self.front = front
    }

    func start() {
        guard hotKeys.isEmpty else { return }
        Self.active = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        if handler == nil { InstallEventHandler(GetApplicationEventTarget(), Self.carbonHandler, 1, &spec, nil, &handler) }
        for (number, modifiers) in [(UInt32(1), UInt32(optionKey)), (UInt32(2), UInt32(optionKey | shiftKey))] {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x444B4C4E), id: number)
            if RegisterEventHotKey(UInt32(kVK_Tab), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { hotKeys.append(ref) }
        }
    }

    func stop() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        cancel()
    }

    private func pressed(backward: Bool) {
        if isOpen {
            move(by: backward ? -1 : 1)
        } else if !opening {
            Task { await open(backward: backward) }
        }
    }

    private func open(backward: Bool) async {
        opening = true
        defer { opening = false }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        let pids = apps.map(\.processIdentifier)
        let found = await Task.detached(priority: .high) { pids.flatMap { WindowIndex.windows(of: $0) } }.value
        // The windows in use first, the rest after them.
        let rank = Dictionary(front.recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let ordered = found.enumerated().sorted {
            (rank[$0.element.info.id] ?? Int.max, $0.offset) < (rank[$1.element.info.id] ?? Int.max, $1.offset)
        }.map(\.element)
        guard !ordered.isEmpty else { return }
        // Let go already: a quick press means "the window before this one".
        let held = NSEvent.modifierFlags.contains(.option)
        if !held {
            let index = min(1, ordered.count - 1)
            WindowIndex.focus(ordered[index].info, handle: ordered[index].handle)
            return
        }
        model.mode = .switcher
        model.cardHeight = settings.previewSize.height * 0.8
        model.icons = Dictionary(apps.compactMap { app in app.icon.map { (app.processIdentifier, $0) } }, uniquingKeysWith: { first, _ in first })
        model.names = Dictionary(apps.map { ($0.processIdentifier, $0.localizedName ?? "") }, uniquingKeysWith: { first, _ in first })
        model.readDisplayOptions()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        model.arrange(ordered.map { PreviewCard(info: $0.info, handle: $0.handle, image: Keeper.shared.picture($0.info.id)) },
                      limit: (screen?.frame.width ?? 1_200) * 0.82)
        let cards = model.cards
        model.selected = cards[backward ? cards.count - 1 : min(1, cards.count - 1)].id
        if hosting == nil {
            var h = PreviewHandlers()
            h.focus = { [weak self] card in self?.choose(card) }
            h.close = { [weak self] card in WindowIndex.close(card.handle); self?.cancel() }
            h.minimize = { card in WindowIndex.setMinimized(!card.info.minimized, card.handle) }
            h.fullScreen = { [weak self] card in
                WindowIndex.focus(card.info, handle: card.handle)
                WindowIndex.toggleFullScreen(card.handle)
                self?.cancel()
            }
            let view = FirstClickHostingView(rootView: PreviewRoot(model: model, handlers: h))
            view.sizingOptions = [.intrinsicContentSize]
            panel.contentView = view
            hosting = view
        }
        place(on: screen)
        panel.allowsKey = true
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        isOpen = true
        watchKeys()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.place(on: screen)
            withAnimation(.easeOut(duration: 0.1)) { self.model.appeared = true }
        }
    }

    private func place(on screen: NSScreen?) {
        guard let hosting, let screen else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 20 else { return }
        let area = screen.visibleFrame
        panel.setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: true)
    }

    private func move(by step: Int) {
        let cards = model.cards
        guard !cards.isEmpty, let index = cards.firstIndex(where: { $0.id == model.selected }) else { return }
        model.selected = cards[(index + step + cards.count) % cards.count].id
    }

    private func watchKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode)
            MainActor.assumeIsolated {
                switch code {
                case kVK_Escape: self?.cancel()
                case kVK_LeftArrow, kVK_UpArrow: self?.move(by: -1)
                case kVK_RightArrow, kVK_DownArrow: self?.move(by: 1)
                case kVK_Return: self?.chooseSelected()
                default: break
                }
            }
            return nil
        }
        // Let go of Option: a short timer that only runs while the panel is open, so a release that
        // reaches no window still counts.
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if !NSEvent.modifierFlags.contains(.option) { self?.chooseSelected() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseTimer = timer
    }

    private func chooseSelected() {
        if let card = model.cards.first(where: { $0.id == model.selected }) { choose(card) } else { cancel() }
    }

    private func choose(_ card: PreviewCard) {
        cancel()
        WindowIndex.focus(card.info, handle: card.handle)
    }

    func cancel() {
        releaseTimer?.invalidate()
        releaseTimer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard isOpen else { return }
        isOpen = false
        model.appeared = false
        panel.allowsKey = false
        panel.orderOut(nil)
        model.rows = []
    }
}
