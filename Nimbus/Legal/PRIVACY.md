# Privacy Policy — Nimbus

**Last updated:** 2026-11-02

Nimbus is a local macOS clipboard manager. This policy explains what data the app handles and what it does **not** do.

## Summary

- Clipboard history stays **on your Mac**.
- Nimbus does **not** create an account.
- Nimbus does **not** upload your clipboard, screenshots, or OCR text to any server.
- Nimbus does **not** include third-party analytics or advertising SDKs in the open-source build described in this repository.

## Data Nimbus stores locally

Stored under `~/Library/Application Support/Nimbus/`:

| Data | Purpose |
|------|---------|
| Clipboard text and links | History, search, paste |
| Screenshot / image copies | History, drag-and-drop, OCR |
| Optional OCR text from images | Search |
| App settings (UserDefaults) | Language, hotkey, limits, pause, ignore list |

You can clear history from the app (Clear All keeps pinned items unless you choose otherwise). Deleting the Application Support folder and app preferences removes local data.

## Permissions

| Permission | Why |
|------------|-----|
| **Clipboard access** | Read items you copy so they can appear in history |
| **Accessibility** | Optional Paste action (synthesizes ⌘V into the frontmost app). History and copy still work without it. |
| **Screen Recording** | Optional. Only used to capture the system screenshot preview bubble when already granted. Not required for normal use. |
| **Files (screenshot folder)** | Read screenshots saved by macOS (Desktop or your custom `screencapture` location) |
| **Login Item** | Optional “Launch at login” |

macOS may also show prompts for these. You can revoke them in **System Settings → Privacy & Security**.

## Sensitive clipboard content

Anything you copy can enter history (including secrets). Mitigations:

- Pause capture in Settings
- Ignore list for apps (password managers are ignored by default where listed)
- Clear or delete individual items
- Transient / confidential pasteboard marks are skipped when the system exposes them

Nimbus cannot guarantee that every password manager marks the pasteboard as confidential.

## Screenshots

If screenshot capture is enabled, Nimbus may copy screenshot images into its local store (including some drag-away captures). Originals on Desktop/temp are not required after ingest; Nimbus keeps its own file under Application Support.

## Network

The open-source Nimbus app does not need a network connection for core features. Opening documentation links (Privacy, Terms, Security) in a browser may use the network via macOS/`NSWorkspace`.

## Children

Nimbus is a general productivity utility, not directed at children under 13.

## Changes

We may update this policy in the repository. The “Last updated” date above will change when we do.

## Contact

Security or privacy reports: see [SECURITY.md](./SECURITY.md).  
Maintainer: [github.com/krmll4444](https://github.com/krmll4444)
