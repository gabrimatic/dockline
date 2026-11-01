import AppKit
import Observation

/// One window as a card shows it.
struct PreviewCard: Identifiable {
    let info: WindowInfo
    let handle: WindowHandle?
    var image: NSImage?
    var id: CGWindowID { info.id }
}

/// What a panel shows. The controller owns it; SwiftUI only reads it.
@MainActor @Observable
final class PreviewModel {
    enum Mode { case dock, switcher }

    var mode = Mode.dock
    var appName = ""
    var appIcon: NSImage?
    var rows: [[PreviewCard]] = []
    var selected: CGWindowID?
    var appeared = false
    var hovered: CGWindowID?
    var cardHeight: CGFloat = 190
    var placedBelow = false
    var reduceMotion = false
    var reduceTransparency = false
    var increaseContrast = false
    @ObservationIgnored var icons: [pid_t: NSImage] = [:]
    @ObservationIgnored var names: [pid_t: String] = [:]

    var cards: [PreviewCard] { rows.flatMap { $0 } }

    func readDisplayOptions() {
        let ws = NSWorkspace.shared
        reduceMotion = ws.accessibilityDisplayShouldReduceMotion
        reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency
        increaseContrast = ws.accessibilityDisplayShouldIncreaseContrast
    }

    /// A card's width follows its window's shape, within reason.
    func width(of card: PreviewCard) -> CGFloat {
        let aspect = card.info.size.width / max(card.info.size.height, 1)
        return (cardHeight * min(max(aspect, 0.72), 1.9)).rounded()
    }

    /// Wraps cards into rows that fit `limit` points.
    func arrange(_ cards: [PreviewCard], limit: CGFloat) {
        var result: [[PreviewCard]] = [[]], used: CGFloat = 0
        for card in cards {
            let width = self.width(of: card) + 12
            if used + width > limit, !(result.last?.isEmpty ?? true) {
                result.append([])
                used = 0
            }
            result[result.count - 1].append(card)
            used += width
        }
        rows = result.filter { !$0.isEmpty }
    }

    func update(_ id: CGWindowID, image: NSImage) {
        for row in rows.indices {
            if let index = rows[row].firstIndex(where: { $0.id == id }) { rows[row][index].image = image }
        }
    }
}
