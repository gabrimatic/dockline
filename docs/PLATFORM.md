# Platform decisions

| Feature | Status | Notes |
| --- | --- | --- |
| Liquid Glass (`glassEffect`) | Adopted | The panel. A solid surface under Reduce Transparency. |
| ScreenCaptureKit (`SCScreenshotManager`) | Adopted | One window at a time, on demand. No stream runs. |
| Accessibility | Adopted | Dock hover by notification, windows, raise, close, minimize, full screen. |
| `_AXUIElementGetWindow` | Adopted, private | Ties an Accessibility window to its window number. Loaded at runtime. Long stable and used widely. |
| `CGWindowListCopyWindowInfo` | Adopted | A window's size as the window server sees it, and windows on other Spaces. |
| HEIC in memory | Adopted | Keeps a window's transparent corners, which JPEG fills in. |
| Carbon hot keys | Adopted | Option-Tab without input monitoring. |
| App Intents, Control Center, Focus filter | Adopted | Pause and resume. |
| `SMAppService` | Adopted | Launch at login, with no helper. |
| Replacing the Dock | Not adopted | The Dock stays the Dock. Dockline adds to it, so nothing about it can break. |
| Pictures on disk | Not adopted | Window contents are private. The price is that a restart starts with no pictures. |
| Capture on hover for parked windows | Not possible | Stage Manager shrinks the window for the window server too: Accessibility says 1443 by 989 and the server says 138 by 144. Every capture API sees the shrunken one. |
| Private Cloud Compute, any network | Not adopted | Nothing leaves the Mac. |
