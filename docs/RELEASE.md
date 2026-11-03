# Release & notarization

Nimbus is distributed as **open source + notarized DMG**.

## One-time Apple setup

1. Enroll in the [Apple Developer Program](https://developer.apple.com).
2. In Xcode → Settings → Accounts, add your team (`DEVELOPMENT_TEAM` is already set in the project).
3. Create a **Developer ID Application** certificate (Certificates, Identifiers & Profiles).
4. Store notary credentials (app-specific password from appleid.apple.com):

```bash
xcrun notarytool store-credentials "nimbus-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

5. Optional explicit identity:

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="nimbus-notary"
```

## Build a release

```bash
export NOTARY_PROFILE="nimbus-notary"
./scripts/release.sh
```

Local archive without Apple notarization:

```bash
./scripts/release.sh --skip-notarize
```

Outputs under `dist/`:

- `Nimbus-<version>.dmg`
- `Nimbus-<version>.SHA256.txt`

## Verify

```bash
shasum -a 256 dist/Nimbus-*.dmg
spctl --assess --type open --context context:primary-signature -v dist/Nimbus-*.dmg
```

## GitHub Release

```bash
VERSION=1.0.0
gh release create "v$VERSION" \
  "dist/Nimbus-$VERSION.dmg" \
  "dist/Nimbus-$VERSION.SHA256.txt" \
  --title "Nimbus $VERSION" \
  --notes-file <(printf '%s\n' \
    "## Nimbus $VERSION" \
    "" \
    "- Local clipboard history for macOS" \
    "- Verify: \`shasum -a 256 Nimbus-$VERSION.dmg\`" \
    "- See PRIVACY.md, TERMS.md, SECURITY.md, LICENSE")
```

Publish the checksum in the release body so users can confirm the binary matches git-adjacent policy docs.
