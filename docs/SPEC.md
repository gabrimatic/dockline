# Dockline specification

Single source of truth. README.md and docs/PLATFORM.md describe what ships; this file states what must be true.

## Product

Window previews for the macOS Dock and a window switcher, in Liquid Glass. Free, never writes a picture to disk. A Dock panel never takes focus from the app in use; the switcher takes the keyboard only while it is open.

## Platform and quality bar

- macOS 26 or later, Apple silicon, Swift 6, built with `build.sh`.
- IBM Plex Sans on every surface the app draws itself. Ink, ice and accent only (docs/DESIGN.md).
- Light and dark. Reduce Motion: a short fade. Reduce Transparency: solid surfaces. Increase Contrast: a visible border. VoiceOver reads every card and control.
- Idle CPU near 0%. At rest the only timer is the 6-second picture check in rule 5. One instance.
- Input is untrusted, every failure fails closed, and nothing secret is captured.

## Windows

1. An app's windows come from Accessibility: standard windows, and titled dialogs for an app that has no standard window. Smaller than 120 points on a side does not count.
2. A window is parked when the window server's width is under 70% of Accessibility's. That is Stage Manager's strip.
3. A titled window at least 200 by 150 that Accessibility does not list is on another Space. It can be shown; a click activates its app, and its card has no window controls.

## The sharp copy

4. A window's picture is taken at full size, never while parked, minimized or on another Space, so a good picture is never replaced by a worse one.
5. Taken 650 ms after a window comes to the front, and every 6 seconds while it is in front and input arrived in the last 20 seconds. Never while the display sleeps or the session is locked.
6. HEIC in memory, which keeps a window's transparent corners. Longest side 1000 pixels, 24 MB in all, oldest used dropped first. A closed window's picture is dropped. Nothing reaches the disk.
7. Keychain Access, Passwords, 1Password and Bitwarden are never captured.

## Dock previews

8. The Dock's selected-children notification says which icon the pointer is on. Hover needs no input monitoring.
9. The panel appears after the chosen delay (50, 180 or 450 ms), moves to a neighboring icon after 130 ms, and stays for as long as the pointer is on it, with 320 ms to cross from the icon. Passing an app that is not running does not close it.
10. It sits on the Dock's inner side, centered on the icon, fully on screen, sized after layout. It takes no focus. Cards wrap to the screen's width and follow each window's shape.
11. A card with no picture shows the app's icon and the window's title. It is never empty and never a stretched thumbnail.
12. Click brings the window forward and closes the panel. Hover shows Close, Minimize and Full Screen. The header has Hide and Quit. An app with no windows offers Open.
13. Windows on screen refresh every 800 ms while their cards are up. A click anywhere else closes the panel.

## Switcher

14. Option-Tab is a system hot key. Option-Shift-Tab goes back. Every window of every regular app, most recently used first, in a panel centered on the screen under the pointer, with cards at 80% of the preview size.
15. Letting go of Option switches. A press released at once goes to the previous window. Arrows move, Return chooses, Esc cancels, and a click chooses. Hover shows Close, Minimize and Full Screen.

## Settings and system

16. Settings has General, Permissions and About. General: previews on or off, Size (Small 140, Medium 190, Large 250 points; default Medium), Appear (Instant, Quick, Relaxed; default Quick), switcher, Launch at login, menu bar icon, Pause. Permissions: both live states, with "Allow…", "Allowed" and "Open System Settings", and a row "Welcome window" with the button "Show Again". About: version, tagline and a "Using Dockline" section.
17. App Intents: Pause or Resume Dockline, Toggle Dockline. A Control Center control and a Focus filter. Pause, from anywhere, stops previews, the switcher and picture taking. So does a missing Accessibility grant.
18. Dockline changes no system setting. It acts on another app or its windows only when you use a card or the panel's header.
19. No Dock icon, in any state. Dockline's standard menus show while one of its windows is in front. Help > Dockline Help opens Settings > About.
20. The menu bar menu opens with the app's name and its state, then Pause Dockline, Settings… (Command-comma), About Dockline and Quit Dockline (Command-Q). With Accessibility missing, an item under the state opens that pane of System Settings.
21. The welcome window shows both permissions and the Launch at login switch. Done, Esc and the close button end it the same way, and it never returns on its own. A later launch with a permission missing opens Settings > Permissions.
22. Launch at login starts on: the first launch registers it, and the welcome window and Settings show the real state.
23. A second launch, or opening the app from Finder or Spotlight, shows the welcome window until it is finished, and Settings after that. SIGTERM is a normal quit.
