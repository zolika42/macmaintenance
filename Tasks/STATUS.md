# v1.0.0 — Local release candidate

v0.9.0 native quality and mounted DMG verification PASS at ecdcf83 (41 tests).

| Task | Scope | Status |
|---|---|---|
| MM-100 | Persistent staged installer and explicit rollback | Source ready; native smoke pending |
| MM-101 | Installed bundle path in Settings | Source ready; native UI pending |
| MM-102 | Release and isolated installer smoke gates | Native QA pending |
| MM-103 | Manual acceptance and stable promotion | Pending; see Docs/VALIDATION.md |
| MM-104 | Authenticated remote updates | Deferred; local notifications retained |

# v0.9.0 — Release candidate

v0.5.0 native quality/release PASS at b5cc90f, 34 XCTest cases, zero failures.

| Task | Scope | Status |
|---|---|---|
| MM-090 | Protection status and permissions panel | Source ready; native UI QA pending |
| MM-091 | Bounded candidate ranking and monotonic command deadlines | Portable tests pass |
| MM-092 | Read-only mounted DMG content verification | Source ready; native QA pending |
| MM-093 | Native acceptance and stable install | Pending on Mac; see validation guide |
| MM-094 | Authenticated remote updates | Deferred until trust policy and endpoint exist |

# v0.5.0 — Advanced UX & Recovery

| Task | Scope | Status |
|---|---|---|
| MM-050 | Interactive storage map, full hash duplicate grouping | Source ready; native QA pending |
| MM-051 | Batch app review/removal | Source ready; native QA pending |
| MM-052 | Maintenance profiles, smart selection | Portable tests passed; native QA pending |
| MM-053 | Typed cache recovery with exclusive restore | Portable tests passed; native restore test pending |
| MM-054 | New icon and release packaging | Native QA pending |
| MM-055 | Authenticated remote update channel | Deferred; local updates retained |

# v0.4.0 implementation status

v0.3.0 native quality/release PASS at 3e3085f. v0.4.0 portable core tests 27/27; native acceptance pending.

| Task | Scope | Status |
|---|---|---|
| MM-031 | Live CPU, memory, swap, battery, thermal and network samples | Core tests pass; native sampling QA pending |
| MM-032 | Swift Charts, monitor page, menu bar controls | Implemented; native QA pending |
| MM-033 | Local release selection, version and checksum validation | Core tests pass; native CryptoKit test pending |
| MM-034 | Update menu, periodic checks, banner, optional notifications | Implemented; native QA pending |
| MM-035 | Packaging and documentation | Local update candidate |

# v0.3.0 implementation status

v0.2.0 native quality/release/launch PASS at 97bf8b9. v0.3.0 portable core tests 20/20; native acceptance pending.

| Task | Scope | Status |
|---|---|---|
| MM-025 | Browser cache scanning, selection, revalidation | Implemented; native Trash QA pending |
| MM-026 | Exact app cache opt-in and read-only orphan hints | Implemented; native QA pending |
| MM-027 | Local Docker build cache review and explicit prune | Implemented; Desktop integration pending |
| MM-028 | Homebrew preview and cache shortcut | Implemented; native QA pending |
| MM-029 | Graphical startup inventory and Settings navigation | Implemented; native QA pending |
| MM-030 | Six regression cases, packaging | Portable tests pass; native pending |

# v0.2.0 implementation status

v0.1.0 native quality/release/launch PASS at c7e1bbc. v0.2.0 core tests 14/14 in Linux; native acceptance pending.

| Task | Scope | Status |
|---|---|---|
| MM-018 | Dashboard storage ring and shortcuts | Source implemented |
| MM-019 | Category-based cache review and bulk selection | Source implemented |
| MM-020 | Native app icons and reviewed standalone app Trash | Core tests pass; native acceptance pending |
| MM-021 | Related-file inventory and protected data | Read-only |
| MM-022 | Storage bars and folder drill-down | Source implemented |
| MM-023 | Per-item Trash history and Finder access | Source implemented |
| MM-024 | Native QA and packaging | Pending on Mac |

## Historical v0.1.0 implementation status

Source implementation present; Apple Silicon integration acceptance pending.

| Task | Initial scope | Status |
|---|---|---|
| MM-001 | SwiftPM, Makefile, local Git workflow | Implemented; native verification pending |
| MM-002 | SwiftUI navigation and bilingual main controls | Implemented; native verification pending |
| MM-003 | Hardware and system reports | Implemented; native verification pending |
| MM-004 | Allowlisted scanner with limits, symlink/metadata checks | Core tests passed on Linux (7 cases) |
| MM-005 | Reviewed developer cache Trash; general caches read-only | Native Trash acceptance pending |
| MM-006 | Docker disk/containers/volumes audit | Read-only; cleanup deferred |
| MM-007 | Homebrew inventory/cache scan | Old package removal deferred |
| MM-008 | Node/PHP/Python cache roots | Standard locations only |
| MM-009 | Xcode DerivedData, simulator list | Simulator deletion deferred |
| MM-010 | Folder sizes, large files, sampled duplicates | Read-only; native acceptance pending |
| MM-011 | Security reports | Read-only; native acceptance pending |
| MM-012 | App inventory/architecture/remnants | Manual Finder removal only |
| MM-013 | Local JSON history | Implemented; SQLite deferred |
| MM-014 | Optional menu bar | Native acceptance pending |
| MM-015 | Hourly read-only audit while window open | No daemon |
| MM-016 | Core regression tests and native acceptance guide | Core tests passed; native pending |
| MM-017 | Ad-hoc signed .app and .dmg scripts | Native packaging pending |

- MM-122: relaunch prevention, unconditional process stop, and same-object revalidation; native CCleaner acceptance pending.

- MM-123: permission-aware app move and App Management settings shortcut; real CCleaner acceptance pending.

- MM-130: first-launch permission setup and public distribution review. **Public release BLOCKED** pending the native acceptance and privileged removal gates in Docs/PUBLIC_RELEASE_AUDIT.md.
