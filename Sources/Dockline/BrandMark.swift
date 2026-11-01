import AppKit

/// Dockline's mark: a window lifted over the Dock, three app tiles on their shelf with the middle one in accent.
/// One drawing on a 24-unit grid, y down: solid ice, one accent part, detail cut out of it.
/// `scripts/make-icon.swift` paints it on the app icon's tile and `menuBarImage` draws it as a
/// template, so the two can never differ.
enum BrandMark {
    static let grid: CGFloat = 24

    /// The ice parts, each filled even-odd so its detail is cut out.
    static func icePaths() -> [CGPath] {
        let window = merged([rounded(2.6, 1.6, 18.8, 11, 2.2), circle(5.4, 4, 0.85), circle(8.1, 4, 0.85), rounded(4.4, 6.2, 15.2, 4.6, 0.8)])
        return [window, rounded(2.9, 14.6, 5, 5, 1.3), rounded(16.1, 14.6, 5, 5, 1.3), rounded(0.8, 20.8, 22.4, 2.4, 1.2)]
    }

    /// The one accent part: the app under the pointer.
    static func accentPaths() -> [CGPath] { [rounded(9.5, 14.6, 5, 5, 1.3)] }

    /// Paints the mark on a context whose unit is one grid unit, y down. Without an accent colour the
    /// accent part stays cut out.
    static func draw(in context: CGContext, ice: CGColor, accent: CGColor?) {
        context.setFillColor(ice)
        for path in icePaths() {
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        }
        guard let accent else { return }
        context.setFillColor(accent)
        for path in accentPaths() {
            context.addPath(path)
            context.fillPath()
        }
    }

    /// The menu bar image: the same drawing in one colour, as a template so macOS tints it.
    static func menuBarImage(description: String) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: 0, y: side)
            context.scaleBy(x: side / grid, y: -side / grid)
            draw(in: context, ice: NSColor.black.cgColor, accent: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    private static func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
    }

    private static func merged(_ paths: [CGPath]) -> CGPath {
        let path = CGMutablePath()
        paths.forEach { path.addPath($0) }
        return path
    }
}
