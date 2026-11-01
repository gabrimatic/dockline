import Darwin
import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let log = Logger(subsystem: "info.gabrimatic.dockline", category: "app")
    private var statusItem: NSStatusItem?
    private var settings: AppSettings?
    private var front: FrontWatcher?
    private var preview: DockPreview?
    private var dock: DockWatcher?
    private var switcher: Switcher?
    /// The running app, for App Intents that act on it.
    static weak var shared: AppDelegate?

    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A plain `kill` (SIGTERM) skips `applicationWillTerminate`; this turns it into a normal quit.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        term.resume()
        terminationSignal = term

        // Launch leaves freed heap behind; hand it back once everything has settled.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            malloc_zone_pressure_relief(nil, 0)
        }
        Self.shared = self
        Typeface.register()
        MainMenu.install(target: self)
        let settings = AppSettings.shared
        self.settings = settings
        if !settings.loginConfigured {
            if let error = LoginItem.set(true) {
                log.error("login item registration failed: \(error, privacy: .public)")
            }
            settings.loginConfigured = true
        }

        let front = FrontWatcher()
        let preview = DockPreview(settings: settings)
        let dock = DockWatcher()
        dock.onHover = { [weak preview] item in preview?.hover(item) }
        self.front = front
        self.preview = preview
        self.dock = dock
        self.switcher = Switcher(settings: settings, front: front)

        settings.onChange = { [weak self] in self?.applyState() }
        settings.onMenuBarIconChange = { [weak self] in self?.applyStatusItem() }
        let permissions = Permissions.shared
        permissions.onChange = { [weak self] trusted in
            self?.log.info("accessibility trusted: \(trusted, privacy: .public)")
            self?.applyState()
        }
        applyStatusItem()
        applyState()

        if !settings.onboardingDone {
            WelcomeWindowController.shared.show()
        } else if !permissions.trusted || !permissions.canCapture {
            // Welcome was finished but the grant is gone (removed in System Settings): say so with one button.
            SettingsWindowController.shared.show(pane: .permissions)
        }
        log.info("launched, trusted: \(permissions.trusted, privacy: .public), login item: \(LoginItem.statusDescription, privacy: .public), menu bar icon: \(settings.showMenuBarIcon, privacy: .public)")
    }

    /// Shows the menu bar icon only when the setting is on. Everything it offers is also in Settings.
    private func applyStatusItem() {
        guard let settings else { return }
        if settings.showMenuBarIcon {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                let menu = NSMenu()
                menu.delegate = self
                item.menu = menu
                statusItem = item
            }
            updateIcon()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Runs the watchers only when they can work and are wanted.
    private func applyState() {
        guard let settings else { return }
        let on = Permissions.shared.trusted && !settings.isPaused
        if on { front?.start() } else { front?.stop() }
        if on, settings.dockPreviews { dock?.start() } else { dock?.stop(); preview?.hide() }
        if on, settings.switcher { switcher?.start() } else { switcher?.stop() }
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button, let settings else { return }
        button.image = BrandMark.menuBarImage(description: "Dockline")
        let inactive = settings.isPaused || !Permissions.shared.trusted
        button.appearsDisabled = inactive
        if settings.focusPaused && !settings.paused {
            button.toolTip = "Dockline (paused by Focus)"
        } else {
            button.toolTip = settings.paused ? "Dockline (paused)" : (Permissions.shared.trusted ? "Dockline" : "Dockline needs Accessibility access")
        }
    }

    // MARK: Reopen, quit

    /// Opening Dockline again from Finder or Spotlight while it runs brings up its window,
    /// so everything stays reachable with the menu bar icon switched off.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    /// The welcome window until it is finished, Settings after that.
    func showMainWindow() {
        if AppSettings.shared.onboardingDone {
            SettingsWindowController.shared.show()
        } else {
            WelcomeWindowController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Dockline changes nothing outside itself; this only takes its panels and watchers down cleanly.
        preview?.hide()
        switcher?.stop()
        dock?.stop()
        front?.stop()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePause) { menuItem.state = settings?.paused == true ? .on : .off }
        return true
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let settings else { return }
        Permissions.shared.refresh()
        menu.removeAllItems()
        let trusted = Permissions.shared.trusted
        let status: String
        if !trusted {
            status = "Needs Accessibility"
        } else if settings.paused {
            status = "Paused"
        } else if settings.focusPaused {
            status = "Paused by Focus"
        } else {
            status = "On"
        }
        menu.addItem(.appName("Dockline", state: status))
        if !trusted {
            let grant = NSMenuItem(title: "Allow Accessibility…", action: #selector(openAccessibility), keyEquivalent: "")
            grant.target = self
            grant.show(symbol: "exclamationmark.triangle")
            menu.addItem(grant)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause Dockline", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = settings.paused ? .on : .off
        pause.show(symbol: "pause.circle")
        menu.addItem(pause)

        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        prefs.show(symbol: "gearshape")
        menu.addItem(prefs)

        let about = NSMenuItem(title: "About Dockline", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        about.show(symbol: "info.circle")
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dockline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.show(symbol: "power")
        menu.addItem(quit)
    }

    @objc func togglePause() {
        settings?.paused.toggle()
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc func showAbout() {
        AboutWindowController.shared.show()
    }

    /// Help is the About pane: what Dockline does and how to use it.
    @objc func showHelp() {
        SettingsWindowController.shared.show(pane: .about)
    }

    @objc private func openAccessibility() {
        Permissions.shared.openAccessibilitySettings()
    }
}
