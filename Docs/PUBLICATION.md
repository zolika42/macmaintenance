# MacMaintenance 2.0.1 — publication candidate

No Apple Developer ID; ad-hoc signing only. No paid services or GitHub Actions. Public GPL-3.0-only source repository: zolika42/macmaintenance. Publisher private key remains local. This document is not publication approval.

## Gate before publication
- `make quality`, `make release`, `make verify-release`, `make verify-install`: all pass. Keep DMG/checksum unchanged after verification.
- `make native-acceptance`: run the disposable KeepAlive fixture in the logged-in GUI session; verify no job or fixture process remains. Separately test actual root-owned application/daemon removal and quarantine restoration, denied/cancelled authorization, root-path race cases, service reinstall, service registration and permissions revoked. No real user data.
- Validate a downloaded/quarantined copy on a clean macOS test machine/account, with system protection unchanged, and verify the claimed OS range. Fresh ad-hoc builds may require permission review again. No Xcode on end-user machine.
- Test real Ed25519 signed manifest fetch, tampered manifest/payload rejection, notifications and the verified DMG download (no auto-install). Verify publisher key fingerprint and secure offline backup; never upload private key.
- Review the GPLv3 license/privacy and all code/assets for distribution rights; obtain explicit publisher approval. Complete independent privileged-operation review; shell path checks and mv -n are not a proof of race-free native behavior. Unverified services/extensions and shared data can remain; new removal operations do not persist disable overrides, and file restoration does not start or re-enable vendor jobs. A stopped service may need manual review/reinstall; old disabled overrides are not automatically changed. Legacy quarantines without identity receipts cannot be restored automatically. Group-writable application ancestors remain a privileged-move blocker.
- Only then make the public repo/Release. If any test fails, do not publish or mark stable.

## Local artifacts
`make prepare-public-release` verifies the DMG, generates the Ed25519-signed release.json and checks the embedded public key against the local private key. It never uploads. Files for release v2.0.1 only:
- Releases/MacMaintenance-2.0.1-arm64.dmg
- Releases/MacMaintenance-2.0.1-arm64.dmg.sha256
- Releases/release.json
Publish corresponding source under GPLv3; never upload private keys, private Git history, logs, caches or receipts.

Use the official public source repository `zolika42/macmaintenance`. Publish an audited source snapshot and create a draft release with the three versioned assets above. Only after all acceptance gates, publish the release and mark it latest; the signed updater uses the GitHub latest endpoint. Label it Public Beta in its title and notes (not GitHub prerelease, which is excluded from latest). Verify the public download and manifest before activating portfolio links. Never replace assets of a published version; bump the version instead.

## Portfolio site
Use the existing KampányMűvek Engine workflow; no site-specific build mechanism or binary on the server. Planned route /macmaintenance/ on horvathzoltanlajos.hu. Publish copy in PORTFOLIO_COPY.md only after the actual asset URLs return the correct files. Add real screenshots from the installed version. Do not claim Intel support, full removal of every service, notarization or production certification.

## Hardening phase 4 (candidate only)
The native descriptor-relative exclusive rename is exercised for user-cache recovery; it is not yet the privileged implementation. A source identity comparison followed by rename is not an atomic compare-and-rename on writable parents. Never execute an untrusted helper as root. The authenticated, read-only History quarantine scan can rediscover valid completed file receipts after lost UI history; it does not recover an unloaded service whose file was never moved, or start vendor code. Root-owned integration, recovery of interrupted operations, safe privileged native-helper trust and compatibility remain publication gates.

## Limited-scope release proposal (requires explicit publisher approval)
For 2.0.1, privileged mutations are disabled at the runtime authorization boundary and system-level services are manual inventory only. Normal user Trash, user launchd removal and user-cache recovery remain supported. Root mutation acceptance remains an open development gate for any later version that enables these features; it must not be reported PASS for this beta. Before approving the restricted beta, verify refusal tests, native user removal/reinstall, complete local build and installer QA, optional read-only authorization and receipt discovery, clean download/launch, signed updater, offline key backup, documentation and explicit scope approval. Keep the original v2.0.0 tag and draft assets unchanged and unpublished. Use a new 2.0.1 tag only after the exact source is accepted. No public binary until all applicable gates and explicit approval.
