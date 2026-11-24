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
    public struct DiscoveredReceipt: Equatable, Sendable {
        public let target: String
        public let original: String
    }
    static func validOriginal(_ path: String) -> Bool {
        if ServiceRemoval.child(path, of: "/Applications"), path.hasSuffix(".app"),
           !path.split(separator: "/").dropLast().contains(where: { $0.lowercased().hasSuffix(".app") }) { return true }
        let parent = (path as NSString).deletingLastPathComponent
        return ["/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/Logs"].contains(parent)
            && ServiceRemoval.child(path, of: parent) && FullUninstaller.validID((path as NSString).lastPathComponent)
    }
    static func parseDiscovery(_ output: String) -> [DiscoveredReceipt]? {
        if output == "MM_QUARANTINE_SCAN_V1" { return [] }
        let rows = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard rows.first == "MM_QUARANTINE_SCAN_V1", rows.count <= 501 else { return nil }
        var seen = Set<String>(), result: [DiscoveredReceipt] = []
        for row in rows.dropFirst() {
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2 else { return nil }
            let target = String(fields[0]), original = String(fields[1])
            guard validDestination(target), validOriginal(original), seen.insert(target).inserted else { return nil }
            result.append(.init(target: target, original: original))
        }
        return result
    }
    static func discoveryScript() -> String {
        (["set -eu", "export LC_ALL=C", "p=/private/var/root"] + ServiceRemoval.strictRootChecks + [
            "printf '%s\\n' MM_QUARANTINE_SCAN_V1", "count=0",
            "for d in /private/var/root/MacMaintenance-removed.*; do",
            "  case \"$d\" in /private/var/root/MacMaintenance-removed.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]) ;; *) continue;; esac",
            "  test -d \"$d\" && check_root_path \"$d\" && test \"$(/usr/bin/stat -f '%Lp' \"$d\")\" = 700 || continue",
            "  test -e \"$d/item\" && check_root_path \"$d/item\" || continue",
            "  ok=1; for f in original-path.txt identity.txt; do test -f \"$d/$f\" && check_root_path \"$d/$f\" && test \"$(/usr/bin/stat -f '%u:%Lp' \"$d/$f\")\" = 0:600 || ok=0; done; test \"$ok\" = 1 || continue",
            "  test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$d/item\")\" = \"$(/bin/cat \"$d/identity.txt\")\" || continue",
            "  original=$(/bin/cat \"$d/original-path.txt\"); case \"$original\" in *[[:cntrl:]]*) continue;; esac",
            "  count=$((count + 1)); test \"$count\" -le 500 || exit 45",
            "  printf '%s\\t%s\\n' \"$d/item\" \"$original\"",
            "done"]).joined(separator: "\n")
    }
    #if os(macOS)
    public static func discover() throws -> [DiscoveredReceipt] {
        let reply = ServiceRemoval.administrator(discoveryScript())
        guard reply.status == 0, let receipts = parseDiscovery(reply.output) else {
            throw RemovalError.refused("Quarantine inspection failed, cancelled or returned invalid receipts: " + reply.output)
        }
        return receipts
    }
    public static func restore(_ target: String) -> CommandResult? {
        guard let script = restoreScript(target) else { return nil }
        return ServiceRemoval.administrator(script)
    }
    #endif
}
