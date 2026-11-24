# MacMaintenance

Free, open-source native macOS maintenance for Apple Silicon. No ads, subscriptions or implemented telemetry.

**Public Beta** — under active development. ARM64 only; macOS 14 is the declared deployment target, not a verified support matrix. Ad-hoc signed, not notarized. Back up important data; app removal can be partial. In the 2.0.1 limited-scope beta, system-level uninstall and privileged quarantine restoration are disabled; use Finder or the vendor uninstaller. Normal user-authorized Trash and cache recovery remain available. Do not disable SIP or Gatekeeper.

- [Official releases](https://github.com/zolika42/macmaintenance/releases)
- [Installation instructions](Docs/PUBLIC_INSTALL.md)
- [User guide](Docs/USER_GUIDE.md)
- [Privacy notice](Docs/PRIVACY.txt)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## Build locally

On Apple Silicon with Xcode and Swift 6: `make quality`, `make release`, `make verify-release`. `make dev` launches a local development build. The DMG needs no Xcode to run. The official signing key is never distributed; a fork can build independently, but must configure its own trust key and feed or disable online updates. No paid CI is required.

## License

Copyright © 2026 Zoltán Horváth. GPL-3.0-only; see [LICENSE](LICENSE). Use, modify and redistribute under its terms. Please send improvements upstream via pull requests. Official release signing does not restrict building or running modified source.
