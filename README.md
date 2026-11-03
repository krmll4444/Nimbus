# Nimbus

Clipboard history for macOS — lives in the menu bar, stays on your Mac.

Copy text, links, or screenshots as usual. Press **⌘⇧V** to open your history, pick an item, and paste.

**Requires:** macOS 14+ · Apple Silicon · [MIT License](./LICENSE)

## What you get

- History of text, links, and images
- Floating panel from the menu bar (no permanent Dock icon)
- Screenshots from ⌘⇧3 / ⌘⇧4 / ⌘⇧5, including dragging the floating thumbnail
- Pins, filters, and search (including text found in images via OCR)
- Paste into other apps, or paste as plain text
- Pause capture, ignore certain apps, limit how much history to keep
- Settings in a normal macOS Settings window

## Install

1. Download the latest **DMG** from [Releases](https://github.com/krmll4444/nimbus/releases).
2. Open the DMG and drag **Nimbus** into Applications.
3. Launch Nimbus from Applications (or Spotlight).
4. Optional: allow **Accessibility** in System Settings if you want Paste (⌘V) into other apps. Copy and history work without it.

Verify a release build (optional):

```bash
shasum -a 256 Nimbus-x.y.z.dmg
# compare with the checksum on the Release page
```

## Everyday use

| Action | How |
|--------|-----|
| Open history | **⌘⇧V** (changeable in Settings) |
| Paste selected item | Click it, or use Paste when Accessibility is on |
| Pin important clips | Pin from the panel |
| Search | Type in the panel search field |
| Pause capturing | Settings → Pause capture |
| Clear history | From the panel (pins can be kept) |
| Welcome / permissions again | Settings → Permissions → Show welcome again |

The Dock icon appears only while **Settings** is open.

## Privacy

Everything stays **local** on your Mac. Nimbus does not upload your clipboard.

Anything you copy can enter history — pause capture or use the ignore list when handling passwords. See [PRIVACY.md](./PRIVACY.md).

## Languages

Choose a UI language in Settings: System, English, Ukrainian, Spanish, Polish, Czech, Slovak, Hungarian, German, or French.

English and Ukrainian are fully translated today; other choices fall back to English where needed.

## Permissions (plain language)

| Permission | Needed for |
|------------|------------|
| Accessibility | Pasting into other apps with ⌘V |
| Screen Recording (optional) | Capturing some floating screenshot thumbnails |
| Files in your home folder | Finding screenshots where macOS saves them |

You can review these anytime under **Settings → Permissions**.

## Trust & legal

| | |
|--|--|
| [PRIVACY.md](./PRIVACY.md) | What stays on your Mac |
| [TERMS.md](./TERMS.md) | Terms of use |
| [SECURITY.md](./SECURITY.md) | How to report security issues |
| [LICENSE](./LICENSE) | MIT |

In the app: **Settings → About**. First launch shows a short welcome sheet.

## Build from source

Open `Nimbus.xcodeproj` in Xcode, select scheme **Nimbus**, run on **My Mac**.

```bash
xcodebuild -scheme Nimbus -destination 'platform=macOS,arch=arm64' -configuration Debug build
```

Core tests:

```bash
cd Packages/NimbusCore && swift test
```

Maintainer: [github.com/krmll4444](https://github.com/krmll4444)
