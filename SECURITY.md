# Security Policy

## Privacy by Design

- **All processing is local.** Window pictures stay in memory and never reach the disk.
- **No network requests.** Dockline has no web client and no update checker.
- **No window content is logged or stored.** The only thing Dockline writes to disk is its settings (macOS user defaults). Logs under the subsystem `info.gabrimatic.dockline` never contain window titles or pictures.
- **No telemetry, no analytics, no accounts.**

## Permissions

| Permission | Why | Scope |
|------------|-----|-------|
| **Accessibility** | See the Dock icon under the pointer, list windows and act on them | This Mac |
| **Screen Recording** | Take pictures of your windows | One window at a time, kept in memory |

No other permission is requested: no Input Monitoring, Full Disk Access, camera, microphone, contacts or location.

## Stored Data

| Data | Location |
|------|----------|
| Settings | `~/Library/Preferences/info.gabrimatic.dockline.plist` |

`defaults delete info.gabrimatic.dockline` resets everything. Window pictures live in memory only.

## Secure by Default

- Keychain Access, Passwords, 1Password and Bitwarden are never captured, and a picture is never written to disk.
- In the background, no picture is taken while the display sleeps or the screen is locked, or when nobody has touched the Mac for 20 seconds. Pictures stay live only while their cards are on screen.
- Pictures live in memory only, up to 24 MB in all, and go when their window closes or Dockline quits.
- The Control Center control runs its action only inside the Dockline app (`allowedExecutionTargets = .main`); no other process can pause or resume Dockline.

## Trust Boundaries

| Boundary | Trust Level | Notes |
|----------|-------------|-------|
| Window titles and pictures | Untrusted input | Shown as text and images only; never parsed, executed or logged |
| Dockline app | Trusted | Built from this repository |
| Release downloads | Ad hoc signed | Not notarized; checksums are in `SHA256SUMS.txt` on each release page, and `install.sh` verifies them |

## Verifying a Download

```bash
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
codesign --verify --strict --verbose=2 /Applications/Dockline.app
```

`install.sh` runs the same checks before it installs anything.

## Supported Versions

Only the latest release receives fixes.

## Vulnerability Reporting

Report vulnerabilities responsibly:

1. **Do not open a public issue.**
2. Use [GitHub's private vulnerability reporting](https://github.com/gabrimatic/dockline/security/advisories/new) to submit.
3. Include:
   - Steps to reproduce
   - Demonstrated impact
   - Affected version and macOS version
   - Suggested fix (if any)

Expect acknowledgment within 48 hours.
