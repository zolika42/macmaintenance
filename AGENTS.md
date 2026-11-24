# MacMaintenance engineering contract

- Swift 6, SwiftUI, ARM64, macOS 14+ deployment target, current local Xcode SDK.
- Local builds and tests only. The public source remote is zolika42/macmaintenance; no paid services, Actions, telemetry or new dependencies. Never commit publisher private keys, logs or personal data.
- All diagnostics are read-only by default. No `sudo`, privileged daemon, SIP changes or shell commands built from input.
- Protected: system files, SSH/signing keys, user documents, repositories, Docker volumes/images/containers, databases, app support and preferences. No automatic Trash emptying.
- Only explicit developer-cache allowlist or eligible direct third-party .app bundles under Applications can move to Trash after review and a fresh fingerprint check. Cache symlinks, external bundle links, unreadable, changed and incomplete entries fail closed. Related app data remains protected except an exact bundle-ID cache explicitly opted into during a verified standalone app removal; revalidate after bundle removal and refuse known duplicate installs or running apps. Exact Chrome/Edge/Brave cache paths and Firefox cache2 only, with browser process checks. Unknown leftover hints are read-only. Vendor uninstallers take precedence for detected complex apps. Do not extend allowlist without tests and documented risks.
- Docker builder prune only for verified local Desktop Unix socket, fixed 7/14/30-day filter, fresh inventory and explicit separate irreversible confirmation. No system/image/volume/container prune. Homebrew installed-package removal remains prohibited. Startup inventory and System Settings navigation only.
- No automatic cleanup, no background cleanup. No fake health scores, no memory purge, no unsupported SSD/temperature claims. Logical bytes are not APFS reclaim guarantees.
- All new functionality requires deterministic tests and documented macOS integration checks. Use `make quality` before committing. Do not claim native tests passed without evidence.
- Keep UI responsive: filesystem scans/commands off the main actor, bounded work, no shell evaluation.

- Updates remain local and read-only: strict version/ARM64 DMG naming, SHA-256 sidecar match, explicit Finder reveal; never execute update scripts or install automatically. A sidecar is not publisher authentication. Monitoring uses bounded samples and no daemon.

- Batch uninstall must reuse Uninstaller review and fresh revalidation for each app, maximum 20, app bundles only, no batch related-data cleanup. Profiles only select already eligible entries; confirmation remains mandatory. Duplicate and storage views remain read-only. Recovery uses typed receipts for newly trashed developer caches only, original allowlisted immediate-child destination, same device, no symlinks, no overwrite, no copy/delete fallback. Do not derive restore actions from historical free-text paths.

- Release candidate gates: `make quality`, `make release`, `make verify-release`. Do not infer Full Disk Access from probes or label unknown security output as enabled. No remote updates without an authenticated release policy.

- Install/rollback must stage and verify the bundle; exclusive same-volume rename, private persistent backups, no automatic deletion of user data or backups. Test installer in isolated HOME. Stable promotion requires native acceptance; ad-hoc signatures and checksums are not publisher authentication.

- v1.1.0 explicitly supersedes the prior app-data/batch-only restriction for the new FullUninstaller: reviewed exact app-ID user data (including databases) can be moved to Trash, name-only candidates need individual opt-in, verified user agents are unloaded first. System/shared/unverified resources remain manual; no privileged execution. Old Uninstaller tests remain as regression coverage of legacy APIs. No general file deletion.

- Service-aware uninstall: explicit confirmation for process termination and data removal; use exact executable paths, verified launchd labels, matching signing teams and root-owned non-writable paths. Never run third-party code as root or recursively delete privileged resources. Root quarantine is not free disk space. Unsupported or uncertain resources must be reported, not bypassed.

- v1.2.1: distinguish application eligibility from residual-service warnings; never route an installed app into leftovers-only cleanup. Preserve explicit failure reporting and do not delete unverified system resources.

- Public GPL-3.0-only source; signed GitHub Releases are maintainer-only. Community PRs must never access signing secrets. Online checking and automatic DMG download are opt-in; installation is manual. Historical constraints above are superseded only where a later explicit requirement says so.
