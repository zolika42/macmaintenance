# Roadmap

- 0.1.0: Core engine — native quality and release passed.
- 0.2.0: Professional GUI and uninstaller — native quality and release passed.
- 0.3.0: Advanced Cleaning — browser caches, optional exact app-cache removal, leftover hints, Docker build cache, Homebrew preview, startup inventory; native quality/release passed at 3e3085f; destructive-action QA still separate.
- 0.4.0: Live system monitoring, Charts, menu-bar summaries, local update checks and opt-in notifications; native quality and release passed at d331181; runtime UI acceptance remains separate.
- 0.5.0: Interactive storage map, batch app review/removal, read-only grouped duplicate inspection, persisted cache profiles, cache recovery receipts; native quality/release passed at b5cc90f (34 tests); runtime acceptance separate. Authenticated HTTPS distribution deferred until an endpoint and trust policy are explicitly chosen.
- 0.9.0: Security status and permission probes, bounded large-file scan, command timeout hardening, DMG content verification; native quality/release/content verification passed at ecdcf83 (41 tests); runtime acceptance remains separate.
- 1.0.0: Local release candidate with staged installation, rollback and isolated installer smoke test; stable local release after acceptance. Never trade data safety for a cleanup count. No GitHub dependency.
