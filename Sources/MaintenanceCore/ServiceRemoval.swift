import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Only literal paths and labels enter privileged commands; no vendor scripts are run as root.
public enum ServiceRemoval {
    static func belongs(_ value: String, to id: String) -> Bool {
        let v = value.lowercased(), i = id.lowercased()
        return v == i || v.hasPrefix(i + ".")
    }
    static func knownJob(_ label: String, bundleID: String, folder: String) -> Bool {
        guard bundleID == "com.piriform.ccleaner" else { return false }
        switch folder {
        case "LaunchAgents": return ["com.piriform.ccleaner", "com.piriform.ccleaner.update"].contains(label)
        case "LaunchDaemons": return ["com.piriform.ccleaner.engine.xpc", "com.piriform.ccleaner.services.submit", "com.piriform.ccleaner.services.xpc", "com.piriform.ccleaner.uninstall", "com.piriform.ccleaner.update.xpc", "com.piriform.ccleaner.CCleanerAgent"].contains(label)
        default: return false
        }
    }
    static func knownPlistLabel(_ filename: String, bundleID: String, folder: String) -> String? {
        guard filename.hasSuffix(".plist") else { return nil }
        let label = String(filename.dropLast(6))
        return knownJob(label, bundleID: bundleID, folder: folder) ? label : nil
    }
    static func child(_ path: String, of root: String) -> Bool {
        path.hasPrefix(root + "/") && !path.hasSuffix("/") && !path.contains("//") && !path.split(separator: "/").contains("..") && !path.split(separator: "/").contains(".") && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    // Match the reviewed object, not a fresh identity from an unrelated replacement.
    static func validStatIdentity(_ value: String) -> Bool {
        let fields = value.split(separator: ":", omittingEmptySubsequences: false)
        return fields.count == 4 && fields.allSatisfy { field in
            !field.isEmpty && field.utf8.allSatisfy { (48...57).contains($0) } && UInt64(field) != nil
        }
    }
    static func matchesStatIdentity(_ value: String, device: UInt64?, inode: UInt64?) -> Bool {
        guard let device, let inode, validStatIdentity(value) else { return false }
        let fields = value.split(separator: ":")
        return UInt64(fields[0]) == device && UInt64(fields[1]) == inode
    }
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func rootOwned(_ path: String) -> Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path), let owner = a[.ownerAccountID] as? NSNumber, let mode = a[.posixPermissions] as? NSNumber else { return false }
        guard owner.intValue == 0, mode.intValue & 0o022 == 0, Scanner(roots: []).safeAncestors(URL(fileURLWithPath: path)) else { return false }
        #if os(macOS)
        let listing = Runner.run(.init("Inspect path ACL", "/bin/ls", ["-lde", path]))
        return listing.status == 0 && aclFreeListing(listing.output)
        #else
        return false
        #endif
    }
    // macOS ls -e prints ACL entries on additional lines. Reject all ACLs.
    static func aclFreeListing(_ listing: String) -> Bool {
        guard !listing.isEmpty, !listing.contains("\n"), !listing.contains("\r"),
              let mode = listing.split(separator: " ", maxSplits: 1).first,
              mode.count >= 10, mode.first == "d" || mode.first == "-" else { return false }
        return !mode.contains("+")
    }
    // Only actual permission failures warrant escalation; never retry arbitrary I/O errors as root.
    static func permissionDenied(_ error: Error) -> Bool {
        var current = error as NSError
        for _ in 0..<8 {
            if current.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(current.code) { return true }
            if current.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(current.code) { return true }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError, underlying !== current else { return false }
            current = underlying
        }
        return false
    }
    static func moveWithPermissionFallback(_ url: URL, trash: (URL) throws -> URL?, authorized: () throws -> URL?) throws -> URL? {
        do { return try trash(url) }
        catch { guard permissionDenied(error) else { throw error }; return try authorized() }
    }
    // Root escalation is limited to approved third-party application bundles under /Applications.
    // At privilege time verify every ancestor, the original inode, and the exact bundle identifier.
    static func applicationMoveScript(path: String, bundleID: String, identity: String) -> String? {
        guard child(path, of: "/Applications"), path.hasSuffix(".app"), !path.split(separator: "/").dropLast().contains(where: { $0.lowercased().hasSuffix(".app") }), FullUninstaller.validID(bundleID), !bundleID.lowercased().hasPrefix("com.apple."), bundleID.lowercased() != "local.macmaintenance.toolkit", validStatIdentity(identity) else { return nil }
        let q = quote
        return (["set -eu", "export LC_ALL=C", "p=" + q(path)] + strictRootChecks + [
                "test -d \"$p/Contents\"; test -f \"$p/Contents/Info.plist\"",
                "check_root_path \"$p/Contents\"; check_root_path \"$p/Contents/Info.plist\"",
                "test -d \"$p\"; test ! -L \"$p\"",
                "test ! -L \"$p/Contents\"; test ! -L \"$p/Contents/Info.plist\"",
                "test \"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \"$p/Contents/Info.plist\")\" = " + q(bundleID),
                "test \"$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' \"$p/Contents/Info.plist\")\" = APPL",
                "check_root_path /private; check_root_path /private/var; check_root_path /private/var/root", "umask 077", "d=$(/usr/bin/mktemp -d /private/var/root/MacMaintenance-removed.XXXXXXXX)", "check_root_path \"$d\"; test \"$(/usr/bin/stat -f '%Lp' \"$d\")\" = 700",
                "printf '%s\\n' \"$p\" > \"$d/original-path.txt\"", "printf '%s\\n' " + q(identity) + " > \"$d/identity.txt\"",
                "test \"$(/usr/bin/stat -f '%d' \"$p\")\" = \"$(/usr/bin/stat -f '%d' \"$d\")\"",
                "test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$p\")\" = " + q(identity),
                "/bin/mv -n \"$p\" \"$d/item\"", "test ! -e \"$p\"; test ! -L \"$p\"", "test -d \"$d/item\"; test ! -L \"$d/item\"", "test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$d/item\")\" = " + q(identity),
                "printf '%s\\n' \"$d/item\""]).joined(separator: "\n")
    }
    public enum ProcessScan: Equatable, Sendable {
        case verified([Int32])
        case unavailable(String)
        public var pids: [Int32]? { if case .verified(let pids) = self { return pids }; return nil }
    }
    // Darwin ps may render uid_t values such as nobody (0xfffffffe) as -2.
    // Preserve the unsigned bit pattern; never interpret a foreign UID as our own.
    static func processUID(_ field: Substring) -> UInt32? {
        if let value = UInt32(field) { return value }
        if let signed = Int32(field), signed < 0 { return UInt32(bitPattern: signed) }
        return nil
    }
    static func parseUserProcesses(_ result: CommandResult, appPath: String, uid: UInt32, selfPID: Int32) -> ProcessScan {
        guard result.status == 0 else { return .unavailable("ps failed (status \(result.status.map(String.init) ?? "unavailable"))") }
        guard !result.output.contains("[output truncated]"), !result.output.contains("[output limit reached]") else { return .unavailable("Process list exceeded its output limit") }
        guard result.output != "(no output)", !result.output.isEmpty else { return .unavailable("Empty process listing") }
        var pids: [Int32] = []
        for line in result.output.split(separator: "\n") {
            let fields = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
            guard fields.count == 3, let pid = Int32(fields[0]), let owner = processUID(fields[1]) else { return .unavailable("Malformed process listing") }
            if pid > 1, pid != selfPID, owner == uid, child(String(fields[2]), of: appPath) { pids.append(pid) }
        }
        return .verified(pids.sorted())
    }
    // APFS exposes the same writable volume at / and /System/Volumes/Data.
    static func processPath(_ path: String) -> String {
        let prefix = "/System/Volumes/Data/"
        let p = path.hasPrefix(prefix) ? "/" + String(path.dropFirst(prefix.count)) : path
        return p.hasPrefix("/var/") ? "/private" + p : p
    }
    static func matchesExecutable(_ path: String, appPath: String) -> Bool {
        child(processPath(path), of: processPath(appPath))
    }
    // BSD ps treats everything after '=' as the header for that column.
    // Each headerless column therefore needs its own -o argument.
    static let processIdentityArguments = ["-axww", "-o", "pid=", "-o", "uid=", "-o", "state="]
    static func parseProcessIdentities(_ result: CommandResult, uid: UInt32, selfPID: Int32) -> ProcessScan {
        guard result.status == 0, !result.output.contains("[output truncated]"), !result.output.contains("[output limit reached]"), result.output != "(no output)" else { return .unavailable("Process identity listing failed: status \(result.status.map(String.init) ?? "unavailable")") }
        var pids: [Int32] = []
        var foundSelf = false
        for line in result.output.split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.isEmpty { continue }
            guard fields.count == 3, let pid = Int32(fields[0]), let owner = processUID(fields[1]), pid >= 0 else { return .unavailable("Malformed process identity listing: \(String(line.prefix(120)))") }
            if pid == selfPID && owner == uid { foundSelf = true }
            guard pid > 1, pid != selfPID, owner == uid, !fields[2].hasPrefix("Z") else { continue }
            pids.append(pid)
        }
        guard foundSelf else { return .unavailable("Process listing does not contain the current process") }
        return .verified(pids.sorted())
    }
    #if os(macOS)
    // ps comm is not an authoritative executable path (it may be a short name).
    // Ask the kernel for the actual executable path of each same-user process.
    static func executablePath(_ pid: Int32) -> String? {
        var bytes = [CChar](repeating: 0, count: 4096)
        let count = bytes.withUnsafeMutableBytes { raw in
            proc_pidpath(pid, raw.baseAddress!, UInt32(raw.count))
        }
        guard count > 0, let end = bytes.firstIndex(of: 0), end > 0 else { return nil }
        return String(decoding: bytes[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    public static func scanUserProcesses(in appPath: String) -> ProcessScan {
        let r = Runner.run(.init("List local process identities", "/bin/ps", processIdentityArguments), outputLimit: 1_000_000)
        let identities = parseProcessIdentities(r, uid: getuid(), selfPID: getpid())
        guard let candidates = identities.pids else { return identities }
        var pids: [Int32] = []
        for pid in candidates {
            if let path = executablePath(pid) {
                if matchesExecutable(path, appPath: appPath) { pids.append(pid) }
            } else {
                // A process can exit between enumeration and lookup. Do not confuse a
                // live process whose path is unreadable with a verified empty result.
                if kill(pid, 0) != 0 && errno == ESRCH { continue }
                return .unavailable("Executable path unavailable for PID \(pid)")
            }
        }
        return .verified(pids.sorted())
    }
    public static func userProcesses(in appPath: String) -> [Int32]? { scanUserProcesses(in: appPath).pids }
    public static func signalOwnedProcesses(in appPath: String, force: Bool) {
        for pid in userProcesses(in: appPath) ?? [] {
            let r = Runner.run(.init("Recheck process owner", "/bin/ps", ["-p", String(pid), "-o", "uid="]))
            guard r.status == 0, processUID(Substring(r.output)) == getuid(), let path = executablePath(pid), matchesExecutable(path, appPath: appPath) else { continue }
            _ = kill(pid, force ? SIGKILL : SIGTERM)
        }
    }
    static func team(_ path: String) -> String? {
        let checked = Runner.run(.init("Verify signature", "/usr/bin/codesign", ["--verify", "--strict", path]), timeout: 30)
        guard checked.status == 0 else { return nil }
        let info = Runner.run(.init("Read signature", "/usr/bin/codesign", ["-dv", "--verbose=4", path]))
        guard info.status == 0, let line = info.output.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else { return nil }
        let id = String(line.dropFirst("TeamIdentifier=".count))
        return id.count == 10 && id.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) } ? id : nil
    }
    static func sameTeam(_ a: String, _ b: String) -> Bool { guard let first = team(a) else { return false }; return team(b) == first }
    // Explicit first-run test; never modifies a file or grants persistent authority.
    public static func testAdministratorAuthorization() -> CommandResult { administrator("/usr/bin/id -u") }
    static func administrator(_ script: String) -> CommandResult {
        Runner.run(.init("Administrator authorization", "/usr/bin/osascript", ["-e", "on run argv", "-e", "do shell script (item 1 of argv) with administrator privileges", "-e", "end run", "--", script]), timeout: 300)
    }
    // A root-owned, non-group/world-writable ancestor chain prevents user-side path substitution.
    static func rootChain(_ path: String) -> Bool {
        var p = path
        while p != "/" && !p.isEmpty {
            guard rootOwned(p) else { return false }; p = (p as NSString).deletingLastPathComponent
        }
        return true
    }
    static func statIdentity(_ path: String) -> String? {
        let r = Runner.run(.init("File identity", "/usr/bin/stat", ["-f", "%d:%i:%m:%z", path]))
        guard r.status == 0, validStatIdentity(r.output) else { return nil }; return r.output
    }
    #endif
    // Recheck in the elevated shell, not just in the unprivileged caller.
    static let strictRootChecks = [
        "check_root_path() {",
        "  test ! -L \"$1\" || return 1",
        "  test \"$(/usr/bin/stat -f '%u' \"$1\")\" = 0 || return 1",
        "  mode=$(/usr/bin/stat -f '%Lp' \"$1\") || return 1",
        "  test $((0$mode & 0022)) -eq 0 || return 1",
        "  listing=$(/bin/ls -lde \"$1\") || return 1",
        "  printf '%s\\n' \"$listing\" | /usr/bin/awk 'NR == 1 { if ($1 !~ /^[-d]/ || $1 ~ /\\+/) bad=1 } END { exit (NR != 1 || bad) }'",
        "}",
        "parent=$p", "while [ \"$parent\" != / ] && [ -n \"$parent\" ]; do",
        "  check_root_path \"$parent\"",
        "  parent=${parent%/*}", "done"
    ]
    static func rootMoveScript(path: String, identity: String, service: String?, program: String?) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let leaf = (path as NSString).lastPathComponent
        let allowedParents = ["/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/Logs"]
        guard allowedParents.contains(parent), child(path, of: parent), FullUninstaller.validID(leaf), validStatIdentity(identity) else { return "exit 64" }
        if let service {
            let parts = service.split(separator: "/", omittingEmptySubsequences: false)
            let expectedLabel = parent == "/Library/PrivilegedHelperTools" ? leaf : (leaf.hasSuffix(".plist") ? String(leaf.dropLast(6)) : "")
            let domainOK = (parent == "/Library/LaunchAgents" && parts.count == 3 && parts[0] == "gui" && UInt32(parts[1]) != nil) || (["/Library/LaunchDaemons", "/Library/PrivilegedHelperTools"].contains(parent) && parts.count == 2 && parts[0] == "system")
            guard domainOK, FullUninstaller.validID(expectedLabel), (parts.last.map(String.init) ?? "") == expectedLabel,
                  let program, program.hasPrefix("/"), !program.contains("//"),
                  !program.split(separator: "/").contains(".."), !program.split(separator: "/").contains("."),
                  !program.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return "exit 64" }
            if parent == "/Library/PrivilegedHelperTools", program != path { return "exit 64" }
        } else if ["/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools"].contains(parent) { return "exit 64" }
        let q = quote
        var commands = ["set -eu", "export LC_ALL=C", "p=" + q(path), "test ! -L \"$p\"", "test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$p\")\" = " + q(identity)]
        commands += strictRootChecks
        // Establish the rollback location before mutating launchd state.
        commands += ["test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$p\")\" = " + q(identity), "check_root_path /private; check_root_path /private/var; check_root_path /private/var/root", "umask 077", "d=$(/usr/bin/mktemp -d /private/var/root/MacMaintenance-removed.XXXXXXXX)", "check_root_path \"$d\"; test \"$(/usr/bin/stat -f '%Lp' \"$d\")\" = 700", "printf '%s\\n' \"$p\" > \"$d/original-path.txt\"", "printf '%s\\n' " + q(identity) + " > \"$d/identity.txt\"", "test \"$(/usr/bin/stat -f '%d' \"$p\")\" = \"$(/usr/bin/stat -f '%d' \"$d\")\""]
        if let service {
            let label = String(service.split(separator: "/").last ?? "")
            if parent != "/Library/PrivilegedHelperTools" {
                commands += ["test -f \"$p\"", "test \"$(/usr/libexec/PlistBuddy -c 'Print :Label' \"$p\")\" = " + q(label),
                             "if actual=$(/usr/libexec/PlistBuddy -c 'Print :Program' \"$p\" 2>/dev/null); then :; else actual=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' \"$p\"); fi",
                             "test \"$actual\" = " + q(program ?? "")]
            }
            // Never persist a disable override: uninstall must not poison a later reinstall.
            // Record the observed state before bootout. Recovery restores files, not vendor execution.
            commands += ["job=" + q(service), "program=" + q(program ?? ""),
                         "printf '%s\\n' \"$job\" > \"$d/service.txt\"",
                         "if status=$(/bin/launchctl print \"$job\" 2>&1); then",
                         parent == "/Library/PrivilegedHelperTools"
                            ? "  printf '%s\\n' \"$status\" | MM_PROGRAM=\"$program\" /usr/bin/awk '{ sub(/^[[:space:]]+/, \"\"); if ($0 == \"program = \" ENVIRON[\"MM_PROGRAM\"]) found=1 } END { exit !found }'"
                            : "  printf '%s\\n' \"$status\" | MM_PROGRAM=\"$program\" MM_PLIST=\"$p\" /usr/bin/awk '{ sub(/^[[:space:]]+/, \"\"); if ($0 == \"program = \" ENVIRON[\"MM_PROGRAM\"]) prog=1; if ($0 == \"path = \" ENVIRON[\"MM_PLIST\"]) path=1 } END { exit !(prog && path) }'",
                         "  printf '%s\\n' loaded > \"$d/service-state.txt\"",
                         "  /bin/launchctl bootout \"$job\"",
                         "else code=$?; test \"$code\" = 113; printf '%s\\n' \"$status\" | /usr/bin/grep -qi 'Could not find service'; printf '%s\\n' absent > \"$d/service-state.txt\"; fi",
                         "if status=$(/bin/launchctl print \"$job\" 2>&1); then exit 31; else code=$?; test \"$code\" = 113; printf '%s\\n' \"$status\" | /usr/bin/grep -qi 'Could not find service'; fi"]
        }
        // No recursive root deletion. A private root-owned quarantine preserves a rollback copy.
        commands += ["check_root_path \"$p\"; test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$p\")\" = " + q(identity), "/bin/mv -n \"$p\" \"$d/item\"", "test ! -e \"$p\"; test ! -L \"$p\"", "test ! -L \"$d/item\"", "test \"$(/usr/bin/stat -f '%d:%i:%m:%z' \"$d/item\")\" = " + q(identity), "printf '%s\\n' \"$d/item\""]
        return commands.joined(separator: "\n")
    }
}
