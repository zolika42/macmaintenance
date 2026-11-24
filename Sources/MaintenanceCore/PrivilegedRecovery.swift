import Foundation

public enum PrivilegedRecovery {
    public static func validDestination(_ path: String) -> Bool {
        let prefix = "/private/var/root/MacMaintenance-removed."
        guard path.hasPrefix(prefix), path.hasSuffix("/item") else { return false }
        let token = path.dropFirst(prefix.count).dropLast(5)
        return token.count == 8 && token.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
    }
    // Only root-created receipts from this release; no arbitrary source/destination arguments.
    public static func restoreScript(_ target: String) -> String? {
        guard validDestination(target) else { return nil }
        let q = ServiceRemoval.quote
        return (["set -eu", "item=" + q(target), "d=${item%/*}",
                "p=$d"] + ServiceRemoval.strictRootChecks + [
                "test -d \"$d\"; test ! -L \"$item\"; test -e \"$item\"",
                "for f in original-path.txt identity.txt; do test -f \"$d/$f\"; test ! -L \"$d/$f\"; test \"$(/usr/bin/stat -f '%u:%Lp' \"$d/$f\")\" = 0:600; done",
                "test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$item\")\" = \"$(/bin/cat \"$d/identity.txt\")\"",
                "p=$(/bin/cat \"$d/original-path.txt\")", "case \"$p\" in /Applications/*.app|/Library/LaunchAgents/*|/Library/LaunchDaemons/*|/Library/PrivilegedHelperTools/*|/Library/Application\\ Support/*|/Library/Caches/*|/Library/Preferences/*|/Library/Logs/*) ;; *) exit 42;; esac",
                "case \"$p\" in */../*|*/./*|*//*) exit 43;; esac",
                "dest=$p; p=${dest%/*}",
                "parent=$p", "while [ \"$parent\" != / ] && [ -n \"$parent\" ]; do",
                "test ! -L \"$parent\"; test -d \"$parent\"", "test \"$(/usr/bin/stat -f '%u' \"$parent\")\" = 0", "mode=$(/usr/bin/stat -f '%Lp' \"$parent\")", "test $((0$mode & 0002)) -eq 0",
                "if [ $((0$mode & 0020)) -ne 0 ]; then case \"$dest\" in /Applications/*.app) test \"$(/usr/bin/stat -f '%g' \"$parent\")\" = 80;; *) exit 44;; esac; fi", "parent=${parent%/*}", "done"] + [
                "test -d \"$p\"; test ! -e \"$dest\"; test ! -L \"$dest\"",
                "test \"$(/usr/bin/stat -f '%d' \"$p\")\" = \"$(/usr/bin/stat -f '%d' \"$item\")\"",
                "/bin/mv -n \"$item\" \"$dest\"", "test ! -e \"$item\"; test ! -L \"$item\"; test -e \"$dest\"", "printf '%s\\n' \"$dest\""]).joined(separator: "\n")
    }
    #if os(macOS)
    public static func restore(_ target: String) -> CommandResult? {
        guard let script = restoreScript(target) else { return nil }
        return ServiceRemoval.administrator(script)
    }
    #endif
}
