import Foundation

public enum PrivilegedRecovery {
    public static func validDestination(_ path: String) -> Bool {
        let prefix = "/private/var/root/MacMaintenance-removed."
        guard path.hasPrefix(prefix), path.hasSuffix("/item") else { return false }
        let token = path.dropFirst(prefix.count).dropLast(5)
        return token.count == 8 && token.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
    }
    // Only root-created receipts; no arbitrary source/destination arguments.
    // Service metadata is diagnostic only; never bootstrap or enable vendor jobs here.
    public static func restoreScript(_ target: String) -> String? {
        guard validDestination(target) else { return nil }
        let q = ServiceRemoval.quote
        return (["set -eu", "export LC_ALL=C", "item=" + q(target), "d=${item%/*}",
                "p=$d"] + ServiceRemoval.strictRootChecks + [
                "test -d \"$d\"; test \"$(/usr/bin/stat -f '%Lp' \"$d\")\" = 700; check_root_path \"$item\"; test -e \"$item\"",
                "for f in original-path.txt identity.txt; do test -f \"$d/$f\"; test ! -L \"$d/$f\"; test \"$(/usr/bin/stat -f '%u:%Lp' \"$d/$f\")\" = 0:600; check_root_path \"$d/$f\"; done",
                "test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$item\")\" = \"$(/bin/cat \"$d/identity.txt\")\"",
                "p=$(/bin/cat \"$d/original-path.txt\")", "case \"$p\" in /Applications/*.app|/Library/LaunchAgents/*|/Library/LaunchDaemons/*|/Library/PrivilegedHelperTools/*|/Library/Application\\ Support/*|/Library/Caches/*|/Library/Preferences/*|/Library/Logs/*) ;; *) exit 42;; esac",
                "case \"$p\" in */../*|*/./*|*//*) exit 43;; esac",
                "dest=$p; p=${dest%/*}",
                "case \"$dest\" in /Applications/*.app) case \"$p\" in *.app|*.app/*) exit 44;; esac;; *) case \"$p\" in /Library/LaunchAgents|/Library/LaunchDaemons|/Library/PrivilegedHelperTools|/Library/Application\\ Support|/Library/Caches|/Library/Preferences|/Library/Logs) ;; *) exit 44;; esac;; esac",
                "case \"$dest\" in *[[:cntrl:]]*) exit 44;; esac"] + ServiceRemoval.strictRootChecks + [
                "test -d \"$p\"; test ! -e \"$dest\"; test ! -L \"$dest\"",
                "test \"$(/usr/bin/stat -f '%d' \"$p\")\" = \"$(/usr/bin/stat -f '%d' \"$item\")\"",
                "/bin/mv -n \"$item\" \"$dest\"", "test ! -e \"$item\"; test ! -L \"$item\"; test ! -L \"$dest\"; test -e \"$dest\"", "test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$dest\")\" = \"$(/bin/cat \"$d/identity.txt\")\"", "printf '%s\\n' \"$dest\""]).joined(separator: "\n")
    }
    #if os(macOS)
    public static func restore(_ target: String) -> CommandResult? {
        guard let script = restoreScript(target) else { return nil }
        return ServiceRemoval.administrator(script)
    }
    #endif
}
