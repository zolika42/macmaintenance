# MacMaintenance 1.0.0 — local release candidate

## Start
Run `make quality`, then `make dev` in the project. For a normal installation use `make install` (or `make install INSTALL_DIR="$HOME/Applications"`) then open MacMaintenance from the corresponding Applications folder. `make release` builds an ARM64 DMG, signed ad hoc for local use; not notarized for distribution. No GitHub or Apple Developer subscription required for this local build. Do not bypass Gatekeeper or disable SIP.

## Modules
- Overview: hardware, macOS, disk space, memory pressure, swap, CPU and process report, battery, APFS and thermal status where available. Volume usage ring and maintenance shortcuts; snapshots, not continuous real-time graphs. Command failures and missing data are visible.
- Clean: scan known cache roots and logs. General application caches, general user logs and npm content cache are read-only (npm logs can be reviewed for Trash). Selected items under explicit developer cache roots can be moved to Trash after revalidation and confirmation. Close all affected apps/builds before cleanup. Explicit visible eligible bulk selection; no automatic selection or irreversible deletion. Trash must be emptied separately in Finder to reclaim space; inspect first. No promise that Finder can restore every item with Put Back; Trash is not a backup.
- Developer: Docker Desktop local socket usage, containers/volumes, Homebrew inventory, Xcode simulator inventory, Swift/Git versions. No image/container/volume prune, simulator deletion or removal of old Homebrew packages. See Advanced Cleaning for the separate local build-cache action. The cache scanner covers standard npm, Homebrew, Composer, pip, Yarn, pnpm and Xcode cache locations; absent/custom locations may not be found. No access to remote Docker contexts intended.
- Storage: Projects, Downloads, Documents, Desktop, Library/Developer, Library/Caches and Applications immediate-child recursive logical sizes; largest items visualized as relative bars. Drill into a directory or choose a folder. Choose a directory to inspect large files and sample duplicate hashes; read-only. Hidden files/packages excluded from large-file scan, partial results are possible. Duplicates not a deletion recommendation. Time Machine snapshot listing only.
- Security: FileVault, SIP, Gatekeeper, firewall, listening TCP ports, login items, SSH and launch item permissions/names, local installed update history. No live software update check. No SSH key content is read; no settings modified.
- Apps: standard app directories, versions, bundle identifiers, architecture via file command, likely exact bundle-ID remnants. Native icons and search. Review a third-party app to calculate bundle size and architecture; eligible direct app bundles in /Applications or ~/Applications may be explicitly moved to Trash. System and self apps, running apps, detected complex service apps, modified or incomplete bundles are refused. Internal relative bundle symlinks may be recorded but never traversed; external or dangling links are refused. Related data remains protected; only the exact reviewed bundle-ID cache can be explicitly opted into during removal, after revalidation and checks for visible duplicate installs and running apps. Logs and other data remain read-only. Vendor-specific uninstallers remain necessary for complex apps; detection is conservative but not exhaustive.
- History: local JSON summaries and per-item original/destination paths for Trash operations (500 most recent), plus bounded Docker operation output. Finder Trash can be opened from History. Settings: Hungarian/English interface, optional menu bar, hourly read-only system audit only while a main window is open. Some system outputs and technical labels remain English. No persistent background agent.

## Safety and limitations
Scan sizes are logical estimates, may double-count hard-linked files and do not guarantee APFS reclaimable bytes. Permission failures, time/node limits, symbolic links and special files can cause partial results; partial candidates cannot be cleaned. Snapshot fingerprint is metadata-based, not a filesystem transaction: avoid concurrent changes. Cleaning caches may cause downloads/rebuilds or temporarily degrade offline capabilities. Keep a backup. No automatic full disk access request; if needed, grant narrowly in System Settings and understand the implications. The app does not require administrator access. Some system utilities might return access errors, which are not treated as a pass. No network calls implemented by the app; external system utilities remain subject to their own behavior/configuration.

## Local verification
The core XCTest suite is portable. Native AppKit/SwiftUI build, code signing, DMG creation and interactive Trash/Finder behavior must be validated on Apple Silicon macOS. Test cleanup on a disposable cache fixture (not an active project); confirm changed candidates are refused and no data outside the allowlist is affected. Check UI in both languages, dark/light appearance, and denied permissions. Avoid production caches until these checks pass.

### v0.2.0 native acceptance
1. Verify `make quality` and `make release`, then open `build/MacMaintenance.app`.
2. Check Overview, cache filters, category totals and explicit selection; do not empty Trash.
3. Check Applications icons, search, architecture, review sizes, protected related files and blocked system/Docker apps.
4. Test actual removal ONLY with an expendable standalone test application (not a production tool). Close it first; verify it appears in Trash and that protected data remains. Try Finder Put Back if available. Verify running app refusal separately.
5. Check Storage folder drill-down, duplicate filter, partial warnings and History.
6. No background deletion or automatic Trash emptying. Fingerprints are metadata based, not atomic; avoid concurrent modifications.

### v0.3.0 advanced tools
- Advanced → Browsers: known Default/Profile N Chrome, Edge and Brave cache folders (Cache, Code Cache, GPUCache), and Firefox cache2 in standard user cache profiles only. Scan, select, review exact paths, quit browser and background processes, then Trash. No Safari, custom profiles, credentials, history, cookies or site storage cleanup. Process checks are conservative but not an atomic lock. Do not empty Trash until verified.
- Advanced → Leftovers: visible bundle-like cache/log names not matched by the sampled application inventory. Suggestions only; no deletion right inferred. Use Finder to investigate. The app review sheet separately offers opt-in to move its exact, unchanged cache after app removal. Duplicate installations outside standard scan locations may not be detected.
- Advanced → Docker: review the local Desktop inventory, choose 7/14/30 days. The fixed `docker builder prune --filter until=168h --force` command (7-day example) removes Docker-selected dangling cache; no `--all` or image/container/volume prune. Local app binary and Unix socket, Desktop identity and review age checked. Inventory is not exact deletion preview; irreversible, may require rebuilding. Stop active builds. If timeout/failure, outcome may be uncertain; audit before retry. No automatic Docker start.
- Advanced → Homebrew: native `brew cleanup --dry-run` and direct link to existing reviewed Homebrew cache cleanup; installed packages remain untouched.
- Startup: visible user/system launch plist labels and executable paths, not a complete active-service inventory. Open native Login Items settings to manage entries. No launchctl changes.

### Native v0.3.0 acceptance
1. `make quality` (20 XCTest cases expected), `make release`, and open the app. Check new navigation in both languages.
2. Inspect browser cache paths with browsers closed; test a small expendable cache first. Verify running browser and changed cache refusal. Inspect protected profile data afterward.
3. Test standalone expendable app removal with and without exact cache opt-in; confirm other data remains and duplicate visible app prevents cache removal.
4. Review Docker with Desktop stopped, then running; confirm only local Desktop inventory is eligible. Do not run prune until active builds are stopped and loss of build cache is acceptable. Validate images, containers and volumes before/after in a disposable development environment.
5. Check Homebrew preview and Startup settings shortcut; no automatic changes.

### v0.4.0 live monitor and updates

- Open Rendszermonitor / Live monitor. Sampling is read-only and continues while the app runs until paused. CPU uses the last of two top samples; RAM is active + wired + compressor physical pages, not the Activity Monitor exact value. en* network link counters exclude VPN/other virtual names and skip first/reset/interface-change samples. Thermal state is qualitative, not Celsius. Cycle count is a separate ioreg query. Up to 120 samples in memory; no persistent telemetry.
- Frissítések / Updates is in the sidebar and app menu. Checks run at startup and every 15 minutes while the app is running (enabled by default). Manual check and folder selection available. Default: ~/Projects/mac-maintenance/Releases. A newer numeric version requires a MacMaintenance-X.Y.Z-arm64.dmg and matching .dmg.sha256 in the folder. SHA-256 verifies integrity only; no publisher authentication. No internet requests; future ChatGPT artifacts are not detectable until a trusted release pair is placed in the folder. No auto-installation or script execution. Finder reveal rechecks the release first.
- New releases show a persistent in-app banner and menu-bar indicator; optional macOS notifications require permission and are attempted once per version. Menu-bar icon remains opt-in in Settings. No checks after the app quits.

### Native v0.4.0 acceptance

1. Run make quality and make release. Expect 28 XCTest cases on macOS (27 portable + real CryptoKit verification). Verify DMG SHA-256 and launch.
2. Visit monitor: observe CPU/RAM/swap/battery, wait for two or more samples and inspect charts. Compare trends against Activity Monitor, not exact memory values. Check network during ordinary traffic; pause and confirm sampling stops. Query cycle count and compare against System Information.
3. Enable menu bar icon; verify monitor summary, pause/start, and Updates shortcuts.
4. Open Updates; check that the current version is 0.4.0, no newer release is reported in the Releases folder if no later release exists. Choose a temporary folder for test fixtures rather than altering real Releases; verify unavailable folder and mismatched checksum states. To test a new version use a harmless text fixture named MacMaintenance-0.4.1-arm64.dmg with its real shasum sidecar (never mount/install this fixture). Verify banner and Finder reveal; tamper with it and recheck, then reset default folder. Enable optional notifications and verify permission-dependent behavior. Do not install untrusted artifacts.

## v0.5.0 — Advanced UX & Recovery

- Select a saved maintenance profile on the Cleaner page. Smart scan on Overview applies the selected profile after scanning; review the selection and explicitly confirm before moving anything. Conservative = npm logs only; Developer = allowlisted developer caches; All eligible = all complete eligible scan results. No automatic deletion.
- On Applications, select up to 20 items and choose Review selected. Protected, incomplete or complex apps are excluded; running apps are refused when executed. The batch preserves related caches and all other data.
- Storage: click a colored segment to drill down or reveal a file; faded segments are partial, gray remainder represents other measured entries. The map is not total disk occupancy. Duplicate grouping uses the full SHA-256 of the existing bounded sample; hard links and APFS clones may share space; inspect only, no deletion.
- History: Restore appears for new developer-cache moves when an accessible same-volume Trash receipt could be captured. Close related apps/builds. Existing targets, changed sources, missing parents and symlinks are refused. Old history, app bundles, browser cache and Docker prune do not support in-app restore. Finder Trash is the fallback for recoverable items. Receipt history is limited to 500 entries.
- Local Updates: unchanged, checks the selected Releases folder at startup and every 15 minutes while the app is running; optional notifications, no automatic install, no network endpoint.

## Release candidate (0.9.0)

In Security, run the audit for the four protection indicators. Open Permissions and use the explicit directory-access test if needed; no file contents are read. The result cannot prove Full Disk Access; grant it manually in System Settings only if needed and restart the app. The large-file view retains the largest 2,000 candidates and displays up to 500; it is not exhaustive. Use `make verify-release` for a read-only mounted DMG content check. Install separately with `make install` (or `make install INSTALL_DIR="$HOME/Applications"`) after quitting the app. Local updates and notifications are unchanged.

## Installation and rollback (1.0.0)

Quit all MacMaintenance copies first. `make install` uses /Applications; use `make install INSTALL_DIR="$HOME/Applications"` for a user-only installation. No sudo or permission bypass. The installer validates bundle metadata, architecture and ad-hoc signature, stages the copy, and uses a same-volume exclusive rename. Previous apps are stored under `.MacMaintenance-backups` in the chosen Applications directory, mode 700. These backups are outside the project build tree. Existing legacy backups in build/install-backups are left untouched. The installed application, not the project build copy, should be opened for normal use. Settings shows the actual bundle path. A local build is not a notarized distribution.

`make install-backups INSTALL_DIR="$HOME/Applications"` lists backup identifiers. `make rollback INSTALL_DIR="$HOME/Applications" BACKUP=backup.ID` explicitly restores the chosen app while retaining any current app as another backup. Use the same installation directory consistently. Rollback affects the app binary only, not preferences or history. `make uninstall` retains the installed app in a backup rather than permanently deleting it. A stale lock after forced interruption must be inspected manually; do not remove backups or locks blindly. The installer attempts recovery after ordinary failures but cannot guarantee recovery from power loss/forced termination. No automatic install or remote feed.

## v1.1.0 full uninstall

Select one or more apps in Applications and review. Exact bundle-ID user data is preselected; name-only candidates require individual selection. Databases and preferences may contain personal data and sessions. Confirm explicitly. The app and eligible items move to Trash; do not empty Trash until satisfied. System apps and MacMaintenance are hidden. User launch agents are eligible only with verified app-contained executables and labels. Privileged, shared or unverified items remain manual; use the official uninstaller and then the leftovers action in the open review (changed or missing files may require manual review). Discovery is not exhaustive and cannot prove ownership of every app-created file. No Keychain or shared-system database modifications.

### Service-aware uninstall (1.2.0)
Select an app, inspect its files and confirm termination/removal. The app attempts graceful quit, then forced termination if required, and unloads supported verified launchd services. System-level steps prompt for administrator authorization and move files to private `/private/var/root/MacMaintenance-removed.*` quarantine (the original path is recorded). User items go to Trash. Neither operation frees space until the retained files are removed. Unsupported system extensions, shared data, unsupported registration types and uncertain ownership are reported. A failed or cancelled step can leave a partial uninstall; see History before retrying. No password is collected or stored by the app.

Vendor identity alone is no longer an uninstall blocker; unsupported services and extensions are assessed individually.

### 1.2.1: Single uninstall action
The red Uninstall button approves stopping the selected apps (force-quit if required), verified services and selected app data. A warning about an unverified service does not block the removal of independently verified items; remaining paths and reasons are reported. An actual failure to stop a verified service, denied administrator authorization, or unsafe/changed identity can still prevent removal. Name-only candidates remain optional; shared/system resources are protected. Root quarantine is not permanent deletion.

### 1.2.2
The uninstaller disables verified launchd jobs before unloading them, then stops the app even if no machine-wide data was selected. Exact documented CCleaner service labels are supported when their local ownership and job identity are verified. Unknown jobs are reported, not blindly killed. Disabled jobs remain disabled after removal; reinstalling may require re-enabling them.

### 1.2.3: Application permissions
If Trash denies access, the uninstaller requests administrator authorization for a verified third-party application in /Applications and moves it into private quarantine. If macOS App Management still denies access, open Privacy & Security > App Management and grant MacMaintenance access. No SIP or privacy protection is disabled programmatically.

### 1.3.0: First launch permissions
Copy MacMaintenance.app to Applications and launch that installed copy. The setup screen opens on the first launch of each version. Open Full Disk Access and App Management in System Settings and decide whether to grant access. Read-only directory probes report observed access, not a TCC entitlement. An optional administrator authorization test reads only the effective root UID; administrator approval may still be required for real removals. Notification access is optional. Files and Folders access is requested only if a feature actually needs it. Continue with limited access if preferred, or reopen the setup from Settings. No password is collected, and SIP or Gatekeeper are not disabled. A new ad-hoc build may need renewed approval. Restart the app if macOS requests it. Internet releases are not yet supported by the in-app updater.

## 2.0.0 publication candidate
- Optional online update checks: enable in Updates, use Check for updates; automatic checks occur while the app runs if enabled. GitHub receives ordinary HTTPS connection data. Only a valid Ed25519 publisher signature, exact versioned asset name and SHA-256/size match permit a DMG download. Automatic DMG download is opt-in; installation remains manual.
- History: newly created privileged quarantine receipts offer a restore button; no existing destination may be overwritten. Restoration requires admin authorization, may be refused if the parent is unsafe, and does not re-enable launchd jobs. Older receipts without identity records are not automatically restored.
- System-level uninstaller validation is still required on real macOS; do not treat this as complete deletion of arbitrary apps.
