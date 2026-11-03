# Nimbus

Menu-bar clipboard manager for macOS (Apple Silicon). Keeps a history of text, links, and screenshots. Open the history panel with a hotkey (default ⌘⇧V).

**Version:** 1.0.0 · **Platform:** macOS 14+ · **Bundle ID:** `krmll.Nimbus` · **License:** [MIT](./LICENSE)

## MVP features

- Clipboard history: text / links / images
- Floating history panel (no permanent Dock icon)
- System **Settings** window (separate window — intentional on macOS)
- Screenshots: ⌘⇧3 / ⌘⇧4 / ⌘⇧5, including drag from the floating thumbnail
- Pins, filters, search (including OCR text)
- Paste / Paste as plain (Accessibility)
- Pause capture, ignore apps, history limit
- Dock icon appears only while Settings is open

### Languages

UI language picker (`AppLanguage`):

| Code | Language |
|------|----------|
| `system` | Follow macOS |
| `en` | English |
| `uk` | Ukrainian |
| `es` | Spanish |
| `pl` | Polish |
| `cs` | Czech |
| `sk` | Slovak |
| `hu` | Hungarian |
| `de` | German |
| `fr` | French |

**String tables today:** full translations for **English** and **Ukrainian**. Other selected languages fall back to English until their catalogs are filled in `L10n` (`AppSettings.swift`).

## Repository layout

```
Nimbus/                      # App target (UI, wiring, hotkeys)
  NimbusApp.swift            # MenuBarExtra + Settings scene
  ClipboardController.swift  # Orchestrates store / monitor / screenshots / panel
  HistoryPanel*.swift        # History panel UI
  SettingsView.swift         # System Settings UI
  AppDockPolicy.swift        # Show/hide Dock while Settings is open
  PasteService.swift         # ⌘V via Accessibility
  …                          # hotkeys, drag, ignore list, L10n

Packages/NimbusCore/         # SPM library (core + tests)
  Sources/NimbusCore/
    ClipboardStore.swift     # Persist + dedupe + pins
    ClipboardMonitor.swift   # Poll NSPasteboard
    ClipboardSnapshot.swift  # Fingerprints (text / pixel hash)
    ScreenshotWatcher.swift  # FSEvents + pasteboard/drag + Spotlight
    OCRService.swift         # Vision OCR
  Tests/NimbusCoreTests/     # Unit tests for the core
```

## Architecture

```
NSPasteboard ──► ClipboardMonitor ──► ClipboardStore ──► HistoryPanel
⌘⇧3/4/5     ──► ScreenshotWatcher ─┘        │
                                            ▼
                         ~/Library/Application Support/Nimbus/
                           history.json + images/*.png
```

- **Nimbus** — UI and lifecycle; business logic lives in **NimbusCore**.
- Images are **always** copied into Application Support (never store only a temp/Desktop path).
- Screenshot save folder comes from `com.apple.screencapture` `location` (not hardcoded to Desktop).
- Drag-away ⌘⇧4 often never writes a Desktop file and never hits the general pasteboard — capture via drag pasteboard + temp staging (best-effort; TemporaryItems is often TCC-locked).

## Permissions

| Permission | Why |
|---|---|
| App Sandbox + home-relative read `/` | Read the user’s screenshot folder |
| Accessibility | Paste via ⌘V |
| Screen Recording (optional) | Capture floating thumbnail; skipped without access to avoid Console spam |
| LSUIElement = YES | No permanent Dock icon |

## Development

### Open and build

1. Open `Nimbus.xcodeproj` in Xcode.
2. Scheme **Nimbus** · Destination **My Mac (Apple Silicon)**.
3. Run (⌘R).

Or via CLI:

```bash
xcodebuild -scheme Nimbus -destination 'platform=macOS,arch=arm64' -configuration Debug build
```

### Tests

Unit tests live in the package (isolated temp root — does not touch live history):

```bash
cd Packages/NimbusCore && swift test
```

Coverage: ingest, dedupe, pins, clear, history limit, image files on disk, OCR text, edit, persistence.

### User data

- History: `~/Library/Application Support/Nimbus/history.json`
- Images: `~/Library/Application Support/Nimbus/images/`
- Settings: `UserDefaults` via `AppSettings`

## Legal & trust

| Doc | Purpose |
|-----|---------|
| [LICENSE](./LICENSE) | MIT |
| [PRIVACY.md](./PRIVACY.md) | What data stays local; permissions |
| [TERMS.md](./TERMS.md) | Terms of use |
| [SECURITY.md](./SECURITY.md) | Vulnerability reporting + checksum verification |

In the app: **Settings → About** opens the bundled copies. First launch shows a short welcome / permissions sheet.

## Release (notarized DMG)

Positioning: **open source + notarized installer**.

```bash
export NOTARY_PROFILE="nimbus-notary"
./scripts/release.sh
```

Details: [`docs/RELEASE.md`](./docs/RELEASE.md). Artifacts land in `dist/` with a SHA-256 file for the GitHub Release.

## Docs for AI

Conventions and “where to change what” → [`AGENTS.md`](./AGENTS.md).  
Always-on Cursor rule → [`.cursor/rules/nimbus.mdc`](./.cursor/rules/nimbus.mdc).

## Product principles

- Menu-bar first: history panel is transient floating UI.
- Settings uses the system SwiftUI `Settings` scene (separate window), not inside the panel.
- Battery-friendly: FSEvents / Spotlight for screenshots; sensible pasteboard poll interval; no Screen Recording unless granted.
- Localization: keys in `AppSettings` / `L10n`. Prefer adding all language tables when adding strings; at minimum keep **en** + **uk** in sync (other locales currently fall back to en).
