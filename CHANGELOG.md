## 1.2.1 — Uninstall routing correction

- One full-uninstall action; no vendor-leftovers detour for installed apps. Unverified service warnings no longer veto independently verified application removal.
- Discover direct executable ownership and verified machine-wide LaunchAgents in the current GUI session. Preserve root authorization, protected files and explicit reporting.
- One final destructive button is the confirmation. Permit shutdown writes only within the same verified data root; nested app-bundle symlinks are recorded without following them. Add a native isolated uninstall workflow test.

## 1.1.0 — Full application removal

- Hide protected Apple/system apps and MacMaintenance from removal list.
- Single and batch uninstall use one reviewed workflow for app-specific data, settings, databases, and verified user launch agents.
- System-level services and shared data are listed for manual/vendor handling; no elevated or permanent deletion.
- Five new regression tests.

# 1.0.0 — Local stable release candidate

- Same-volume staged installation, exclusive rename (no destination overwrite), validated app identity/version/architecture/signature, persistent private installation backups and explicit rollback. Uninstall preserves the application as a backup; user data untouched.
- `make verify-install` exercises the installer in a disposable isolated home: foreign destination refusal, fresh install, replacement, invalid rollback ID refusal, rollback and uninstall.
- Settings displays the running bundle path and a Finder reveal action to distinguish development and installed copies.
- Local update checks unchanged; no remote feed, notarization, automatic installer or new cleanup permissions. Stable designation requires documented native UI and disposable-operation acceptance.

# 0.9.0 — Release candidate: readiness and packaging

- Conservative graphical FileVault, SIP, Gatekeeper and firewall status interpretation; unknown on failed or unrecognized output.
- Explicit read-only directory-access probes and Full Disk Access settings shortcut; no definitive entitlement claim or automated permission changes.
- Bounded top-2,000 large-file candidates with deterministic ties; existing 500-result and SHA-256 budgets retained; elapsed-time limits use monotonic uptime.
- Command runner rejects invalid timeouts and uses monotonic elapsed time; fixed C locale for predictable diagnostics.
- Release content verification mounts the local DMG read-only, verifies checksum, bundle ID, version, architecture, signature, icon and layout, then detaches. No app installation during verification.
- Seven additional portable regression tests. Native runtime and destructive-action acceptance are still required before stable release. No remote update endpoint.

# 0.5.0 — Advanced UX & Recovery

- Interactive proportional storage map for scanned logical bytes, grouped SHA-256 duplicate candidates (read-only), and a new app icon.
- Batch review and removal of up to 20 app bundles with existing fresh validation, explicit confirmation and associated data preserved.
- Persisted maintenance profile preference and smart scan/selection; no automatic deletion.
- Typed receipts for new developer-cache Trash moves only; same-volume exclusive restore to original path, revalidation, no overwrite. Other Trash items remain Finder-only. Receipts may be unavailable for inaccessible or changed paths.
- Existing local update checks and opt-in notification retained. No remote channel or automatic installer.
- Five additional portable tests and one macOS-only exclusive restore test. Native UI/runtime verification required.

# 0.4.0 — Live Monitoring & Local Updates

- Live CPU, physical memory estimate, swap, battery charge and state, thermal status, en* network throughput, cycle count query, and native Swift Charts. Read-only sampling starts on monitor visit or manually; pause available; 120 samples in memory.
- Menu-bar live summaries and update indicator; Updates menu, sidebar, dashboard shortcut, automatic checks at startup and every 15 minutes while running; user-selected local release directory; opt-in macOS notifications.
- Strict numeric ARM64 DMG version filtering, SHA-256 sidecar verification and Finder reveal only; no executable update or automatic installation. Integrity is not publisher authentication.
- Seven additional portable tests plus one native CryptoKit verification test. macOS GUI and notification acceptance pending.

# 0.3.0 — Advanced Cleaning

- Targeted browser cache review and Trash for Chrome, Edge, Brave and Firefox; no cookies, history, credentials or profile deletion.
- Optional exact reviewed app cache after standalone bundle removal; unknown leftover hints read-only.
- Local Docker Desktop build-cache age-filtered prune with separate irreversible confirmation; no image/container/volume deletion.
- Homebrew dry-run and direct access to existing cache scanner; graphical startup plist inventory and System Settings shortcut.
- Six new portable core regression cases; native UI and actual destructive operation acceptance pending.

# 0.2.0 — Professional GUI and reviewed app uninstall

- Real volume storage ring, maintenance shortcuts, grouped cache results, filter and explicit bulk selection.
- Native app icons, searchable inventory, bundle size and architecture on review, direct app bundle Trash where permitted.
- Related data listed read-only; detected complex, system, self, running and modified apps refused.
- Storage bars, folder drill-down, duplicate filter, detailed Trash history.
- Six additional core regression tests; native macOS acceptance pending.

# Changelog

## 0.1.0 — initial local candidate
- Native SwiftUI shell, eight pages, menu bar and read-only recurring audit.
- Core scanning/revalidation, bounded command runner, explicit developer-cache Trash flow.
- Read-only developer, security, storage and application reports; local JSON history.
- SwiftPM, local Makefile, test suite, .app and .dmg packaging scripts.
- macOS compilation and acceptance pending.

## 1.2.0 – Service-aware uninstall
- Gracefully terminate reviewed apps and executable-path-matched current-user helpers; force terminate after a bounded wait with explicit approval.
- Verify and unload eligible user agents and signed, root-owned legacy launch daemons. Use native administrator authorization; move verified privileged helpers and exact machine-wide data into private root quarantine instead of permanent deletion.
- Report unselected, unsupported, changed, and remaining paths. System extensions, ambiguous ownership, and unsupported registration types remain unresolved; no claim of universal uninstall coverage.

Vendor identity alone is no longer an uninstall blocker; unsupported services and extensions are assessed individually.

## 1.2.2
- Disable verified launchd relaunch before bootout; always stop application before moving files; revalidate same bundle object and report specific failed paths.

## 1.2.3
- Permission-aware application removal: if normal Trash fails with a permission error, request administrator authorization for verified third-party bundles under /Applications. Continue with selected data after successful move. No protection bypass.

## 1.3.0 — public release preparation (not approved for public distribution)
- Guided per-version first-launch permission review, read-only access probes, explicit App Management and Full Disk Access setup, optional administrator authorization test and notifications.
- Developer-specific local update directory no longer required for new installations. Online updates remain unimplemented. No privacy or system protection bypass.
- Added public installation guide and source review / release gates. Native clean-machine validation and privileged uninstaller audit remain pending.

## 2.0.0 — publication candidate
- Recheck privileged paths, actual plist label and same-volume move in elevated operation; support unreadable known CCleaner plist candidates only after exact elevated label verification.
- Root quarantine receipts and GUI restore with collision checks; no service re-enable.
- Opt-in Ed25519 authenticated release feed, size/hash checked DMG download, local publisher key generation, release-only packaging docs.
- Public beta candidate: native acceptance, privilege review, legal approval and clean machine test remain required.

- Public source release under GPL-3.0-only, contributor documentation, official repository feed and optional automatic verified DMG download.
