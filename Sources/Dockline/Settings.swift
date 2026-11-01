import AppKit
import Observation

enum PreviewSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var height: CGFloat {
        switch self {
        case .small: return 140
        case .medium: return 190
        case .large: return 250
        }
    }
}

enum HoverDelay: String, CaseIterable, Identifiable, Sendable {
    case instant, quick, relaxed
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var seconds: Double {
        switch self {
        case .instant: return 0.05
        case .quick: return 0.18
        case .relaxed: return 0.45
        }
    }
}

/// All settings, stored in UserDefaults. Pictures of windows never are.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let paused = "paused"
        static let focusPaused = "focusPaused"
        static let dockPreviews = "dockPreviews"
        static let switcher = "switcher"
        static let size = "previewSize"
        static let delay = "hoverDelay"
        static let menuBarIcon = "showMenuBarIcon"
        static let loginConfigured = "loginConfigured"
        static let onboardingDone = "onboardingDone"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onMenuBarIconChange: (() -> Void)?

    var paused: Bool { didSet { defaults.set(paused, forKey: Key.paused); onChange?() } }
    /// Set by a Dockline Focus filter: paused while that Focus is on.
    var focusPaused: Bool { didSet { defaults.set(focusPaused, forKey: Key.focusPaused); onChange?() } }
    var dockPreviews: Bool { didSet { defaults.set(dockPreviews, forKey: Key.dockPreviews); onChange?() } }
    var switcher: Bool { didSet { defaults.set(switcher, forKey: Key.switcher); onChange?() } }
    var previewSize: PreviewSize { didSet { defaults.set(previewSize.rawValue, forKey: Key.size) } }
    var hoverDelay: HoverDelay { didSet { defaults.set(hoverDelay.rawValue, forKey: Key.delay) } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.menuBarIcon); onMenuBarIconChange?() } }

    var isPaused: Bool { paused || focusPaused }

    var loginConfigured: Bool {
        get { defaults.bool(forKey: Key.loginConfigured) }
        set { defaults.set(newValue, forKey: Key.loginConfigured) }
    }

    /// The welcome window was finished: Done, Esc and the close button all set this.
    var onboardingDone: Bool {
        get { defaults.bool(forKey: Key.onboardingDone) }
        set { defaults.set(newValue, forKey: Key.onboardingDone) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paused = defaults.bool(forKey: Key.paused)
        focusPaused = defaults.bool(forKey: Key.focusPaused)
        dockPreviews = defaults.object(forKey: Key.dockPreviews) as? Bool ?? true
        switcher = defaults.object(forKey: Key.switcher) as? Bool ?? true
        previewSize = PreviewSize(rawValue: defaults.string(forKey: Key.size) ?? "") ?? .medium
        hoverDelay = HoverDelay(rawValue: defaults.string(forKey: Key.delay) ?? "") ?? .quick
        showMenuBarIcon = defaults.object(forKey: Key.menuBarIcon) as? Bool ?? true
    }
}
