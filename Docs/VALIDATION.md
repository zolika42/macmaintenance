# 1.0.0 local release acceptance

v0.9.0 on user Mac: 41/41 XCTest, quality, DMG checksum, mounted content verification PASS at ecdcf83. Existing hdiutil deprecation warnings are non-fatal; retain the compatible commands for macOS 14+ pending a verified replacement.

Automated gates: `make quality`, `make release`, `make verify-release`, `make verify-install`. Installer smoke test uses an isolated temporary home; no real installed app or user history is changed. It tests ordinary operation, not all possible interruption/race conditions. Expect 41 XCTest on macOS; the installer smoke is a separate gate.

Manual acceptance before declaring stable (record pass/fail in a dated local report):

- Install from the trusted local build to the chosen Applications directory; launch via Finder; confirm Settings path and 1.0.0 version. Restart and verify saved settings and existing history.
- Run Smart Scan and storage map on a disposable folder; verify partial results and cancellation/limits where available. Check UI in Hungarian/English and light/dark mode.
- Review a disposable standalone app, confirm a running or protected app is blocked, Trash only the disposable app. Check history and retained application data.
- Use disposable npm log/cache fixtures for cleanup and recovery; verify restored path and refusal to overwrite a recreated file. No active caches or personal files; do not empty Trash for QA.
- Check monitoring, menu bar, permissions and security states; compare with raw diagnostics. Do not alter system protection to test.
- From a retained trusted earlier app, use the local release directory to check 1.0.0 and optional notification; verify SHA-256 and Finder reveal. No remote updates or automatic installation.
- Test rollback on isolated install using `make verify-install`, then keep previous trusted app backups. Record any UI/runtime failures before stable promotion. Docker irreversible prune only on explicitly disposable local cache; otherwise leave untested and report it.

# v0.9.0 release candidate acceptance

Baseline v0.5.0: 34/34 XCTest, quality, ad-hoc signed ARM64 app, DMG and SHA-256 PASS at b5cc90f on the user Mac. Runtime acceptance is separate.

- Run `make quality`, `make release`, `make verify-release`; expect 41 XCTest cases on macOS (39 portable + 2 macOS-only). Verify the mounted bundle and detach result. Local ad-hoc signing is not publisher authentication or notarization.
- Security: run audit; compare the four interpreted results with raw reports. Unknown or unrecognized statuses must not display Enabled. Permission probe is voluntary and not proof of FDA; test before/after grant and restart. Never change SIP, FileVault or Gatekeeper to test.
- Storage: use disposable directory with known files and duplicates. Record elapsed wall time and peak memory with Activity Monitor; compare with v0.5.0 on same fixture. Bounded candidate selection is not an end-to-end benchmark. Directory enumeration and I/O may still block; no hard realtime guarantee.
- Repeat the v0.5.0 disposable app and cache recovery, browser, Docker and update UI tests below. Docker prune only on disposable local build cache after explicit approval; never touch active databases or volumes.
- Test installation with app quit: `make install INSTALL_DIR="$HOME/Applications"`; verify installed app launches from that path, check Settings and local history. Existing installed app is retained in build/install-backups by installer. Do not empty Trash to test.
- Release candidate does not automatically install, grant permissions, or perform cleanup. Stable v1.0.0 only after native acceptance.

# Verification evidence — v0.4.0 candidate

- v0.3.0 on user Mac: 20/20 XCTest, native quality, ad-hoc signed app, verified DMG and SHA-256, launch command PASS at 3e3085f (user log).
- v0.4.0 portable Swift 6.2.1: 27 XCTest cases, zero failures (20 existing + 7 new); additional CryptoKit test compiled and run only on macOS. macOS UI syntax parse only; native type checking, runtime metrics, notifications, signing, DMG and actual cleanup QA require Mac acceptance.
- Upgrade executes make quality, make release and checksum check before Git commit. No cleanup, automatic installation or network calls during update checks.

## v0.5.0 native acceptance (pending)

- `make quality` and `make release`; expect 34 tests on macOS (32 portable + 2 native-only). Confirm full previous regression suite and DMG SHA-256.
- Verify all profiles select only eligible entries; switch profile, restart, confirm persistence. Smart scan never moves data until confirmation.
- Use only disposable standalone test app bundles, including a protected/running app in a batch; verify refusal and data retention.
- Test storage map on disposable directory, drill into a segment, verify partial label and duplicate grouping with same-size nonidentical files. Do not delete duplicate candidates.
- Use disposable npm-log fixture only, verify Trash receipt, restore, then test collision by recreating original file; verify neither file is overwritten. Check changed/missing source and older history. Do not use active build caches.
- Confirm local update menu and notifications still operate. No remote release configuration.

## v1.1.0 native acceptance (pending)

Use a disposable app and test SQLite data in its exact Library/Application Support bundle-ID directory; verify review, opt-out, Trash and history. Verify Apple/system apps and self are hidden. Check a disposable user agent and a privileged-service app: only verified user jobs may be unloaded, privileged paths remain manual. Check duplicate installations, name-only matches, symlinks and modified entries. Do not use live business databases.
