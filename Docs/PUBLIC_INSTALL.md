# MacMaintenance 2.0.1 — release candidate, not yet approved for public distribution

Apple Silicon (ARM64), macOS 14 or newer declared minimum; other versions require validation. No Xcode, shell script or source build is required on a user's Mac.

1. Download the DMG from the official website and compare its SHA-256 with the independently published checksum before opening it. A checksum is not a publisher signature.
2. Open the DMG, drag MacMaintenance.app to Applications, eject the image, then launch the installed copy.
3. This build uses ad-hoc signing, not Apple Developer ID or notarization. macOS may block or warn about it. Read Apple's official guide https://support.apple.com/en-us/102445. Only approve this particular app if you trust its source; never disable system-wide protections. Managed devices may prohibit opening it.
4. The permission setup guides you to Full Disk Access and App Management. These can expose sensitive personal data and enable removal of other apps; grant only if you accept these capabilities. The access checks are not a guarantee of full authorization. Administrator authentication is optional and read-only in this beta (authorization test and legacy quarantine inspection). System-level uninstall and privileged restoration are disabled. Notifications are optional.
5. Read the removal preview before confirming. Quarantine and Trash retain files; some shared, protected, inaccessible or unverified items may remain. Back up important data. This is not an exhaustive uninstaller and has not yet passed clean-machine acceptance.

Source code and GPLv3 license: https://github.com/zolika42/macmaintenance . No telemetry is implemented. Optional online update checking uses GitHub and verifies the publisher signature and DMG hash. Optional automatic download is available in Updates. No automatic installation. Do not run the app from the DMG. Do not disable SIP or Gatekeeper. If you change privacy permissions, restart if macOS requests it.
