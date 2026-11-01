import SwiftUI

/// Everything a card can ask for.
struct PreviewHandlers {
    var focus: @MainActor (PreviewCard) -> Void = { _ in }
    var close: @MainActor (PreviewCard) -> Void = { _ in }
    var minimize: @MainActor (PreviewCard) -> Void = { _ in }
    var fullScreen: @MainActor (PreviewCard) -> Void = { _ in }
    var hideApp: @MainActor () -> Void = {}
    var quitApp: @MainActor () -> Void = {}
    var openApp: @MainActor () -> Void = {}
}

/// Glass that falls back to a solid surface when Reduce Transparency is on.
private struct Surface<S: InsettableShape>: ViewModifier {
    let shape: S
    let model: PreviewModel

    func body(content: Content) -> some View {
        if model.reduceTransparency {
            content
                .background(shape.fill(Theme.ground))
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
        } else {
            content
                .overlay { if model.increaseContrast { shape.strokeBorder(Theme.text.opacity(0.7), lineWidth: 1.5) } }
                .glassEffect(.regular, in: shape)
        }
    }
}

struct PreviewRoot: View {
    let model: PreviewModel
    let handlers: PreviewHandlers
    static let padding: CGFloat = 12
    static let radius: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.mode == .dock { header }
            if model.rows.isEmpty {
                empty
            } else {
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row) { card in
                            CardView(card: card, model: model, handlers: handlers)
                        }
                    }
                }
            }
        }
        .padding(14)
        .modifier(Surface(shape: RoundedRectangle(cornerRadius: Self.radius, style: .continuous), model: model))
        .padding(Self.padding)
        .scaleEffect(model.appeared || model.reduceMotion ? 1 : 0.94, anchor: model.placedBelow ? .top : .bottom)
        .opacity(model.appeared ? 1 : 0)
        .fixedSize()
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = model.appIcon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            }
            Text(model.appName).font(Typeface.font(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer(minLength: 24)
            HeaderButton(symbol: "eye.slash", label: "Hide", action: handlers.hideApp)
            HeaderButton(symbol: "xmark.circle", label: "Quit", action: handlers.quitApp)
        }
        .padding(.horizontal, 2)
    }

    private var empty: some View {
        HStack(spacing: 12) {
            Text("No open windows").font(Typeface.font(13)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 16)
            Button(action: handlers.openApp) {
                Text("Open").font(Typeface.font(12, .medium)).padding(.horizontal, 12).frame(height: 26)
                    .foregroundStyle(Theme.onAccent).background(Capsule().fill(Theme.accent)).contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 240)
    }
}

private struct HeaderButton: View {
    let symbol: String
    let label: String
    let action: @MainActor () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.fill.opacity(hovered ? 1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondary)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct CardView: View {
    let card: PreviewCard
    let model: PreviewModel
    let handlers: PreviewHandlers
    private var width: CGFloat { model.width(of: card) }
    private var active: Bool { model.hovered == card.id || model.selected == card.id }
    private static let corner: CGFloat = 12
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.corner, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                picture
                if model.hovered == card.id, card.handle != nil { controls.padding(6).transition(.opacity) }
            }
            .frame(width: width, height: model.cardHeight)
            .overlay {
                shape.strokeBorder(model.selected == card.id ? Theme.accent : Theme.hairline.opacity(active ? 1 : 0.6),
                                   lineWidth: model.selected == card.id ? 2.5 : 1)
            }
            HStack(spacing: 6) {
                if model.mode == .switcher, let icon = model.icons[card.info.pid] {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                }
                Text(title).font(Typeface.font(12)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if let note { Text(note).font(Typeface.font(11)).foregroundStyle(Theme.secondary).fixedSize() }
            }
            .frame(width: width)
        }
        .contentShape(Rectangle())
        .onTapGesture { handlers.focus(card) }
        .onHover { inside in
            if inside { model.hovered = card.id } else if model.hovered == card.id { model.hovered = nil }
        }
        .animation(.easeOut(duration: 0.12), value: model.hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { handlers.focus(card) }
    }

    private var title: String {
        card.info.title.isEmpty ? (model.names[card.info.pid] ?? model.appName) : card.info.title
    }

    private var note: String? {
        if card.info.minimized { return "Minimized" }
        if card.info.elsewhere { return "Other Space" }
        return nil
    }

    @ViewBuilder private var picture: some View {
        if let image = card.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: model.cardHeight)
                .clipShape(shape)
                .accessibilityHidden(true)
        } else {
            // A window Dockline has not seen at full size yet: a clean card, never a smeared thumbnail.
            ZStack {
                shape.fill(Theme.surface)
                if let icon = model.icons[card.info.pid] ?? model.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            CircleControl(symbol: "arrow.up.left.and.arrow.down.right", label: "Full Screen") { handlers.fullScreen(card) }
            CircleControl(symbol: "minus", label: "Minimize") { handlers.minimize(card) }
            CircleControl(symbol: "xmark", label: "Close") { handlers.close(card) }
        }
    }
}

private struct CircleControl: View {
    let symbol: String
    let label: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.iceColor)
        .background(Circle().fill(Palette.inkColor.opacity(0.72)))
        .help(label)
        .accessibilityLabel(label)
    }
}
