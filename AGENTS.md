# AGENTS.md — context for AI and contributors

Read this before changing Nimbus. Short overview: [`README.md`](./README.md).

**Docs and code comments are written in English.** Chat with the project owner may still be in Ukrainian.

## What this product is

Nimbus is a **menu-bar clipboard manager** for macOS (not a normal windowed document app).  
MVP: clipboard history (text/links/images), ⌘⇧V panel, screenshots, pins/filters/OCR/paste, Settings, multi-language UI.

### Languages (`AppLanguage`)

Picker options: **System**, English, Ukrainian, Spanish, Polish, Czech, Slovak, Hungarian, German, French.

Full `L10n` string tables today: **en** and **uk**. Other codes fall back to English in `L10n.string`. When adding UI copy, update **en** and **uk** at minimum; add other language dictionaries when filling those locales.

## Code map — where to put changes

| Task | Where |
|---|---|
| Persist / dedupe / pins / trim | `Packages/NimbusCore/.../ClipboardStore.swift` |
| Pasteboard polling | `ClipboardMonitor.swift` |
| Text / image fingerprints | `ClipboardSnapshot.swift` |
| Screenshots from disk / temp / drag PB | `ScreenshotWatcher.swift` |
| OCR | `OCRService.swift` |
| Wiring + panel + hotkeys | `Nimbus/ClipboardController.swift` |
| History UI | `HistoryPanel.swift` + `HistoryPanelController.swift` |
| Settings UI | `SettingsView.swift` + `Settings { }` in `NimbusApp.swift` |
| Dock while Settings open | `AppDockPolicy.swift` + `AppDelegate.swift` |
| Paste ⌘V | `PasteService.swift` |
| UI strings / languages | `AppSettings.swift` → `L10n` |
| Core unit tests | `Packages/NimbusCore/Tests/NimbusCoreTests/` |

**Layering:** non-UI logic → NimbusCore. SwiftUI/AppKit wiring → `Nimbus` target. Do not duplicate persistence in the app layer.

## Hard product decisions (do not break casually)

1. **Settings = separate system window** (`Settings` scene + `SettingsLink`). Do not embed the settings form in the history panel.
2. **LSUIElement / `.accessory`** — no permanent Dock icon. Dock only while Settings is open (`AppDockPolicy`).
3. **Images are always an owned copy** in Application Support. Never store only a path to Desktop/TemporaryItems.
4. **Screenshot folder** comes from `com.apple.screencapture` `location` — do not hardcode Desktop.
5. **TemporaryItems** is often TCC-locked; capture drag-away screenshots via `NSPasteboard.Name.drag` (+ general PB). Call `CGWindowListCreateImage` only if `CGPreflightScreenCaptureAccess()` is true (otherwise Console spam: `task name port right` / WindowServer).
6. **History panel** is an `NSPanel` with `isMovableByWindowBackground = false` (drag cards, not the window).
7. **Localization:** new UI strings → `L10n` keys; keep **en** and **uk** in sync; other languages fall back to en until catalogs exist.

## Code style

- Swift 5 / macOS 14+, `@MainActor` for UI and store/monitor.
- Minimal diffs: no drive-by refactors, no unsolicited markdown/docs in PRs.
- New core behavior → unit test in `NimbusCoreTests` with an **isolated** `ClipboardStore(rootURL:)`.
- Do not commit `.env`, secrets, or `Packages/NimbusCore/.build/`.
- Prefer English for comments and documentation.

## Tests

```bash
cd Packages/NimbusCore && swift test
```

App UI / Accessibility / real ⌘⇧4 — manual. Avoid mocking TCC in unit tests unless necessary.

## Build

```bash
xcodebuild -scheme Nimbus -destination 'platform=macOS,arch=arm64' -configuration Debug build
```

Agent sandboxes often break `xcodebuild` — run with full permissions.

## Common traps

- **Duplicate screenshots after clicking the thumbnail** → pixel fingerprint in `ClipboardSnapshot`, not bytes-only; `ignoreCurrentPasteboard` after internal copy.
- **⌘⇧4 → drag into Cursor, missing from history** → session burst + drag pasteboard; Desktop file may never appear.
- **WindowServer port-right log** → do not call window capture without Screen Recording preflight.
- **Flaky tests** → do not use live Application Support; only a temp `rootURL`.
- **`clearAll()`** defaults to `keepingPinned: true`.

## Versioning

`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `Nimbus.xcodeproj`. Shown in Settings via `AppVersion` (`CFBundleShortVersionString` + `CFBundleVersion`).

## Legal / release

- Keep root `LICENSE`, `PRIVACY.md`, `TERMS.md`, `SECURITY.md` in sync with `Nimbus/Legal/*.md` (bundled for in-app links).
- First-run onboarding: `hasCompletedOnboarding` in `AppSettings`; UI in `OnboardingView`.
- Ship via `./scripts/release.sh` + `docs/RELEASE.md` (Developer ID + notarize + SHA-256).
