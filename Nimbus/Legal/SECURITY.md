# Security Policy

## Supported versions

Security fixes are accepted against the latest `main` branch and the newest GitHub Release.

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Older releases | Best-effort |

## What to report

Please report:

- Unauthorized access to clipboard history on disk
- Sandbox / TCC bypasses that expose other users’ data
- Remote code execution or privilege escalation in Nimbus
- Supply-chain issues in release artifacts (failed notarization, mismatched checksums)

Please **do not** file public GitHub issues for unfixed critical vulnerabilities.

## How to report

Contact: [github.com/krmll4444](https://github.com/krmll4444)

Include:

1. Nimbus version (`Settings → About`)
2. macOS version
3. Clear reproduction steps
4. Impact assessment (what an attacker gains)
5. Proof-of-concept if available (keep it minimal)

You should receive an acknowledgement within **7 days**.

## Safe harbor

Good-faith research that follows this policy and avoids privacy violations of third parties is appreciated. Do not access other people’s machines or data.

## Release integrity

Official binaries (when published) should be:

- Signed with Apple Developer ID
- Notarized by Apple
- Accompanied by a **SHA-256** checksum on the GitHub Release

Verify before installing:

```bash
shasum -a 256 Nimbus-x.y.z.dmg
# compare to the checksum published on the Release page
```

## Clipboard reality check

Any clipboard manager can see secrets you copy. Prefer Pause capture / ignore lists when handling passwords. Transient pasteboard items are skipped when macOS marks them; not all apps do.
