import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct FullRemovalItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable { case application, data, candidate, agent, machineAgent, daemon, machineData, helper, manual }
    public var id: String { path }
    public let path: String
    public let kind: Kind
    public let bytes: Int64?
    public let allowed: Bool
    public let reason: String
    let fingerprint: UInt64
    let files: Int
    let device: UInt64?
    let inode: UInt64?
    let label: String?
    let program: String?
}
public struct FullRemovalReview: Sendable {
    public let appPath: String
    public let bundleID: String
    public let items: [FullRemovalItem]
    public let blockers: [String]
    // Service inventory warnings must not route a real uninstall into the leftovers-only path.
    public var canRemoveApp: Bool { items.contains { $0.kind == .application && $0.allowed && $0.path == appPath } }
    public var defaultSelection: Set<String> {
        guard canRemoveApp else { return [] }
        return Set(items.filter { $0.allowed && $0.kind != .candidate }.map(\.path))
    }
    public var requiredServices: Set<String> {
        Set(items.filter { $0.allowed && [.agent, .machineAgent, .daemon, .helper].contains($0.kind) }.map(\.path))
    }
}
public struct FullRemovalResult: Sendable {
    public init() {}
    public var moved: [(String, String)] = []
    public var failures: [String] = []
}
public struct FullUninstaller: Sendable {
    let home: URL
    let applications: URL
    let systemLibrary: URL
    public init() { home = FileManager.default.homeDirectoryForCurrentUser; applications = URL(fileURLWithPath: "/Applications"); systemLibrary = URL(fileURLWithPath: "/Library") }
    init(home: URL, applications: URL, systemLibrary: URL) { self.home = home; self.applications = applications; self.systemLibrary = systemLibrary }
    var appRoots: [URL] { [applications, home.appendingPathComponent("Applications")] }
    static func validID(_ id: String) -> Bool {
        id.count <= 255 && id.split(separator: ".", omittingEmptySubsequences: false).count >= 2 && id.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 } }
    }
    public func visible(appPath: String, bundleID: String) -> Bool {
        guard visibleLocation(appPath: appPath, bundleID: bundleID) else { return false }
        return Scanner(roots: []).safeAncestors(URL(fileURLWithPath: appPath))
    }
    public func visibleLocation(appPath: String, bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return Self.validID(bundleID) && !id.hasPrefix("com.apple.") && id != "local.macmaintenance.toolkit" && appPath.hasSuffix(".app") && appRoots.contains { appPath.hasPrefix($0.path + "/") }
    }
    private func identity(_ path: String, _ id: String) -> [String: Any]? {
        guard visible(appPath: path, bundleID: id) else { return nil }
        let u = URL(fileURLWithPath: path)
        // No nested app bundles: folder-organized apps are allowed, embedded apps are not.
        guard !u.deletingLastPathComponent().pathComponents.contains(where: { $0.lowercased().hasSuffix(".app") }), (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeDirectory else { return nil }
        let info = u.appendingPathComponent("Contents/Info.plist")
        guard let p = plist(info), p["CFBundleIdentifier"] as? String == id, p["CFBundlePackageType"] as? String == "APPL" else { return nil }
        return p
    }
    private func plist(_ url: URL) -> [String: Any]? {
        guard Scanner(roots: []).safeAncestors(url), let a = try? FileManager.default.attributesOfItem(atPath: url.path), a[.type] as? FileAttributeType == .typeRegular, let n = a[.size] as? NSNumber, n.intValue <= 1_000_000, let d = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any]
    }
    private func exists(_ path: String) -> Bool { (try? FileManager.default.attributesOfItem(atPath: path)) != nil }
    private func inspect(_ url: URL, _ kind: FullRemovalItem.Kind, _ reason: String, label: String? = nil, program: String? = nil) -> FullRemovalItem {
        let parent = url.deletingLastPathComponent()
        let root = ScanRoot(parent.path, parent.lastPathComponent, parent)
        let e = try? Scanner(roots: [root]).inspectChild(url, root: root, seconds: kind == .application ? 25 : 5, opaqueBundleLinks: kind == .application)
        let ok = e?.complete == true && kind != .manual
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return .init(path: url.path, kind: kind, bytes: e?.complete == true ? e?.bytes : nil, allowed: ok, reason: ok ? reason : (kind == .manual ? reason : "Incomplete or unsafe scan; review manually."), fingerprint: e?.fingerprint ?? 0, files: e?.files ?? 0, device: (attrs?[.systemNumber] as? NSNumber)?.uint64Value, inode: (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value, label: label, program: program)
    }
    private func related(_ path: String, _ id: String) -> [FullRemovalItem] {
        let lib = home.appendingPathComponent("Library")
        let exact = ["Caches/\(id)", "Logs/\(id)", "Preferences/\(id).plist", "Application Support/\(id)", "Containers/\(id)", "Saved Application State/\(id).savedState", "HTTPStorages/\(id)", "HTTPStorages/\(id).binarycookies", "WebKit/\(id)", "Cookies/\(id).binarycookies", "Application Scripts/\(id)", "Preferences/\(id).plist.lockfile", "Autosave Information/\(id)"]
        var out = exact.compactMap { suffix -> FullRemovalItem? in
            let u = lib.appendingPathComponent(suffix)
            return exists(u.path) ? inspect(u, .data, "Exact bundle-ID match; may contain databases, sessions and personal data.") : nil
        }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        // Name-only matches are never preselected; no broad vendor or substring matching.
        if name.count >= 4 && !["data", "support", "cache", "logs", "shared", "applications", "preferences", "database", "documents", "macmaintenance"].contains(name.lowercased()) {
            for folder in ["Application Support", "Caches", "Logs", "WebKit", "HTTPStorages"] {
                let u = lib.appendingPathComponent(folder).appendingPathComponent(name)
                if exists(u.path) && !out.contains(where: { $0.path == u.path }) { out.append(inspect(u, .candidate, "Exact app-name match only. Confirm ownership yourself; may be shared.")) }
            }
        }
        let byHost = lib.appendingPathComponent("Preferences/ByHost")
        if Scanner(roots: []).safeAncestors(byHost), let names = try? FileManager.default.contentsOfDirectory(atPath: byHost.path) {
            for n in names.prefix(4000) where n.hasPrefix(id + ".") && n.hasSuffix(".plist") {
                let middle = String(n.dropFirst(id.count + 1).dropLast(6))
                if UUID(uuidString: middle) != nil { out.append(inspect(byHost.appendingPathComponent(n), .data, "Exact bundle-ID host preference.")) }
            }
        }
        // Shared and machine-wide data is shown, not modified without a dedicated authorization path.
        for suffix in ["Application Support/\(id)", "Caches/\(id)", "Preferences/\(id).plist", "Logs/\(id)", "Application Support/\(name)"] {
            let u = systemLibrary.appendingPathComponent(suffix)
            if exists(u.path), !out.contains(where: { $0.path == u.path }) { var kind: FullRemovalItem.Kind = .manual
                #if os(macOS)
                if !suffix.hasSuffix("/" + name), ServiceRemoval.team(path) != nil, ServiceRemoval.rootChain(u.path) { kind = .machineData }
                #endif
                out.append(inspect(u, kind, kind == .machineData ? "Exact application ID; administrator authorization and private quarantine." : "Machine-wide data; ownership not verified.")) }
        }
        // Shared group containers are intentionally never auto-removable.
        let group = lib.appendingPathComponent("Group Containers")
        if Scanner(roots: []).safeAncestors(group), let names = try? FileManager.default.contentsOfDirectory(atPath: group.path) {
            for n in names.prefix(2000) where n.lowercased().hasSuffix("." + id.lowercased()) || n.lowercased() == "group." + id.lowercased() { out.append(inspect(group.appendingPathComponent(n), .manual, "Potential shared group container; verify ownership manually.")) }
        }
        return out
    }
    private func services(_ path: String, _ id: String) -> [FullRemovalItem] {
        var out: [FullRemovalItem] = []
        let declaredIDs = Set((identity(path, id)?["SMPrivilegedExecutables"] as? [String: Any])?.keys.map { $0 } ?? [])
        let folders = [(home.appendingPathComponent("Library/LaunchAgents"), true), (systemLibrary.appendingPathComponent("LaunchAgents"), false), (systemLibrary.appendingPathComponent("LaunchDaemons"), false), (systemLibrary.appendingPathComponent("PrivilegedHelperTools"), false)]
        for (folder, user) in folders {
            if !exists(folder.path) { continue }
            guard Scanner(roots: []).safeAncestors(folder), let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path), names.count <= 4000 else {
                out.append(inspect(folder, .manual, "Service inventory incomplete or inaccessible; cannot safely uninstall.")); continue
            }
            for name in names.sorted() {
                let u = folder.appendingPathComponent(name)
                let p = name.hasSuffix(".plist") ? plist(u) : nil
                var label = p?["Label"] as? String ?? ""
                #if os(macOS)
                // An unreadable known plist is only a candidate for privileged verification.
                // The elevated operation must read and match its real Label before touching it.
                if p == nil, !user, ServiceRemoval.rootChain(u.path), ServiceRemoval.team(path) != nil,
                   let expected = ServiceRemoval.knownPlistLabel(name, bundleID: id, folder: folder.lastPathComponent) { label = expected }
                #endif
                let program = (p?["Program"] as? String) ?? (p?["ProgramArguments"] as? [String])?.first ?? ""
                let inside = program.hasPrefix(path + "/") && !program.split(separator: "/").contains("..") && !program.split(separator: "/").contains(".")
                let lower = id.lowercased()
                let matches = name.lowercased() == lower || name.lowercased().hasPrefix(lower + ".") || label.lowercased() == lower || label.lowercased().hasPrefix(lower + ".") || inside || declaredIDs.contains(name.replacingOccurrences(of: ".plist", with: ""))
                guard matches else { continue }
                let declared = declaredIDs.contains(label)
                let named = ServiceRemoval.belongs(label, to: id) || declared
                let direct = inside && Scanner(roots: []).safeAncestors(URL(fileURLWithPath: program))
                var verifiedProgram = direct
                #if os(macOS)
                let known = ServiceRemoval.knownJob(label, bundleID: id, folder: folder.lastPathComponent) && name == label + ".plist"
                if !direct && (program == systemLibrary.appendingPathComponent("PrivilegedHelperTools/" + label).path || ServiceRemoval.child(program, of: systemLibrary.appendingPathComponent("Application Support/" + id).path)) && ServiceRemoval.rootChain(program) && ServiceRemoval.sameTeam(path, program) { verifiedProgram = true }
                #endif
                let verified = name == label + ".plist" && Self.validID(label) && (named || direct) && verifiedProgram
                var kind: FullRemovalItem.Kind = user && verified && direct ? .agent : .manual
                #if os(macOS)
                if user && known { kind = .agent }
                if !user && ["LaunchDaemons", "LaunchAgents"].contains(folder.lastPathComponent) && ServiceRemoval.rootChain(u.path) && ((verified && ServiceRemoval.sameTeam(path, program)) || (known && ServiceRemoval.team(path) != nil)) {
                    kind = folder.lastPathComponent == "LaunchDaemons" ? .daemon : .machineAgent
                }
                if folder.lastPathComponent == "PrivilegedHelperTools", Self.validID(name), ServiceRemoval.belongs(name, to: id) || declaredIDs.contains(name), ServiceRemoval.rootChain(u.path), ServiceRemoval.sameTeam(path, u.path) { kind = .helper }
                #endif
                out.append(inspect(u, kind, kind == .manual ? "Unverified service: label=\(label.isEmpty ? name : label), program=\(program.isEmpty ? "unknown" : program). No automatic privileged removal." : "Verified service/helper; stopped before removal, administrator authorization if required.", label: kind == .helper ? name : ([.agent, .machineAgent, .daemon].contains(kind) ? label : nil), program: kind == .helper ? u.path : ([.agent, .machineAgent, .daemon].contains(kind) ? program : nil)))
            }
        }
        return out
    }
    public func review(appPath: String, bundleID: String) -> FullRemovalReview {
        guard let p = identity(appPath, bundleID) else { return .init(appPath: appPath, bundleID: bundleID, items: [], blockers: ["System, self, or unverifiable application identity."]) }
        let app = URL(fileURLWithPath: appPath)
        let item = inspect(app, .application, "Application bundle", label: nil)
        let service = services(appPath, bundleID)
        var blockers: [String] = []
        if !item.allowed { blockers.append("Application scan incomplete or unsafe.") }
        let markers = ["Contents/Library/SystemExtensions", "Contents/Library/Extensions", "Contents/Library/LaunchAgents", "Contents/Library/LaunchDaemons"]
        if markers.contains(where: { exists(app.appendingPathComponent($0).path) }) { blockers.append("System extensions or embedded launchd registrations may remain; unsupported registrations will be reported.") }
        if let declared = p["SMPrivilegedExecutables"] as? [String: Any] {
            for label in declared.keys where !service.contains(where: { $0.kind == .daemon && $0.label == label }) {
                #if os(macOS)
                let status = Runner.run(.init("Check declared service", "/bin/launchctl", ["print", "system/" + label]))
                if status.status == 113 && status.output.localizedCaseInsensitiveContains("Could not find service") { continue }
                #endif
                blockers.append("Declared privileged service not verified: " + label)
            }
        }

        if service.contains(where: { !$0.allowed }) { blockers.append("Some background services could not be verified; only verified resources will be removed. Remaining paths will be reported.") }
        return .init(appPath: appPath, bundleID: bundleID, items: [item] + service + related(appPath, bundleID), blockers: blockers)
    }
    // The approved bundle/data object may change during shutdown. Its root identity
    // must remain identical and the new inspection must still be safe.
    static func sameApprovedData(_ a: FullRemovalItem, _ b: FullRemovalItem) -> Bool {
        [.application, .data, .candidate, .machineData].contains(a.kind) && a.kind == b.kind && a.path == b.path && a.allowed && b.allowed && a.device != nil && a.inode != nil && a.device == b.device && a.inode == b.inode
    }
    // Inventory of every visible app (including non-removable apps) must be provided by caller.
    public func validate(_ old: FullRemovalReview, selected: Set<String>, otherIDs: Set<String>, dataOnly: Bool = false, allowDataChanges: Bool = false) throws -> [FullRemovalItem] {
        guard !otherIDs.contains(where: { $0.caseInsensitiveCompare(old.bundleID) == .orderedSame }) else { throw RemovalError.refused("Another installation shares this bundle ID.") }
        guard Self.validID(old.bundleID), !old.bundleID.lowercased().hasPrefix("com.apple."), old.bundleID.lowercased() != "local.macmaintenance.toolkit", old.items.contains(where: { $0.kind == .application && $0.path == old.appPath }) else { throw ScanError.unsafePath }
        let current: [FullRemovalItem]
        if dataOnly {
            guard !exists(old.appPath), Scanner(roots: []).safeAncestors(URL(fileURLWithPath: old.appPath).deletingLastPathComponent()), services(old.appPath, old.bundleID).isEmpty else { throw RemovalError.refused("Leftovers-only cleanup requires the application and its related services to be absent.") }
            current = related(old.appPath, old.bundleID)
        } else {
            let fresh = review(appPath: old.appPath, bundleID: old.bundleID)
            guard old.canRemoveApp, fresh.canRemoveApp else { throw RemovalError.refused(fresh.blockers.joined(separator: " ")) }
            guard selected.contains(old.appPath), fresh.requiredServices.isSubset(of: selected) else { throw RemovalError.refused("Application and all verified services must be selected.") }
            current = fresh.items
        }
        guard !selected.isEmpty else { return [] }
        return try selected.sorted().map { path in
            guard let a = old.items.first(where: { $0.path == path }), let b = current.first(where: { $0.path == path }), a.allowed, b.allowed, (a == b || (allowDataChanges && Self.sameApprovedData(a, b))), !dataOnly || [.data, .candidate].contains(a.kind) else { throw RemovalError.refused("Selection changed or unsafe: " + path) }
            return b
        }
    }
    #if os(macOS)
    public static func authorizedAppMove(_ item: FullRemovalItem, _ bundleID: String) throws -> URL? {
        guard item.kind == .application, item.allowed, let device = item.device, let inode = item.inode,
              let stat = ServiceRemoval.statIdentity(item.path), stat.hasPrefix("\(device):\(inode):"),
              let script = ServiceRemoval.applicationMoveScript(path: item.path, bundleID: bundleID, identity: stat) else {
            throw RemovalError.refused("Cannot safely authorize this application path. Check System Settings > Privacy & Security > App Management for MacMaintenance.")
        }
        let reply = ServiceRemoval.administrator(script)
        guard reply.status == 0, reply.output.hasPrefix("/private/var/root/MacMaintenance-removed."), reply.output.hasSuffix("/item"), !reply.output.contains("\n") else {
            throw RemovalError.refused("Administrator removal failed or cancelled: " + reply.output + ". If macOS denies access, enable MacMaintenance in System Settings > Privacy & Security > App Management and retry.")
        }
        return URL(fileURLWithPath: reply.output)
    }
    public func trash(_ old: FullRemovalReview, selected: Set<String>, otherIDs: Set<String>, dataOnly: Bool = false, stop: @MainActor @Sendable () async -> Bool, isRunning: @MainActor @Sendable () -> Bool, moveToTrash: @Sendable (URL) throws -> URL? = { url in
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }, authorizedAppMove: @Sendable (FullRemovalItem, String) throws -> URL? = FullUninstaller.authorizedAppMove) async -> FullRemovalResult {
        var result = FullRemovalResult()
        do {
            let items = try validate(old, selected: selected, otherIDs: otherIDs, dataOnly: dataOnly, allowDataChanges: !dataOnly)
            for agent in items where agent.kind == .agent {
                guard let label = agent.label, inspect(URL(fileURLWithPath: agent.path), .agent, agent.reason, label: label, program: agent.program) == agent else { throw RemovalError.refused("Agent file changed before stop: " + agent.path) }
                let service = "gui/\(getuid())/\(label)"
                let status = Runner.run(.init("Inspect agent", "/bin/launchctl", ["print", service]))
                if status.status == 0 {
                    // The live job must also point into the reviewed app, not just share a label.
                    guard status.output.split(separator: "\n").contains(where: { line in
                        let value = line.trimmingCharacters(in: .whitespaces)
                        return (agent.program.map { !$0.isEmpty && value == "program = " + $0 } ?? false) || value == "path = " + agent.path
                    }) else { throw RemovalError.refused("Loaded agent executable could not be verified: \(label)") }
                } else if status.status != 113 || !status.output.localizedCaseInsensitiveContains("Could not find service") { throw RemovalError.refused("Cannot verify agent state: \(status.output)") }
                let disabled = Runner.run(.init("Disable agent", "/bin/launchctl", ["disable", service]))
                guard disabled.status == 0 else { throw RemovalError.refused("Cannot disable " + label + ": " + disabled.output) }
                if status.status == 0 {
                    let unload = Runner.run(.init("Unload agent", "/bin/launchctl", ["bootout", service]))
                    guard unload.status == 0 else { throw RemovalError.refused("Cannot unload \(label): \(unload.output)") }
                }
                let after = Runner.run(.init("Verify stopped agent", "/bin/launchctl", ["print", service]))
                guard after.status == 113, after.output.localizedCaseInsensitiveContains("Could not find service") else { throw RemovalError.refused("Agent still registered: " + label) }
                guard inspect(URL(fileURLWithPath: agent.path), .agent, agent.reason, label: label, program: agent.program) == agent else { throw RemovalError.refused("Agent file changed: " + agent.path) }
                let dest = try moveToTrash(URL(fileURLWithPath: agent.path))
                result.moved.append((agent.path, dest?.path ?? "Trash"))
            }
            // Stop privileged daemons first, then quarantine their verified files.
            for kind in [FullRemovalItem.Kind.daemon, .machineAgent, .helper] {
                for item in items where item.kind == kind {
                    let latest = inspect(URL(fileURLWithPath: item.path), kind, item.reason, label: item.label, program: item.program)
                    guard ServiceRemoval.rootChain(item.path), (latest == item || Self.sameApprovedData(item, latest)), let identity = ServiceRemoval.statIdentity(item.path) else { throw RemovalError.refused("Privileged item changed or unsafe: " + item.path) }
                    let job = item.label.map { (kind == .machineAgent ? "gui/\(getuid())/" : "system/") + $0 }
                    let reply = ServiceRemoval.administrator(ServiceRemoval.rootMoveScript(path: item.path, identity: identity, service: job, program: item.program))
                    guard reply.status == 0, reply.output.hasPrefix("/private/var/root/MacMaintenance-removed."), !exists(item.path) else { throw RemovalError.refused("Administrator step failed or cancelled: " + item.path + " — " + reply.output) }
                    result.moved.append((item.path, reply.output))
                }
            }
            if !dataOnly {
                guard await stop(), !(await isRunning()) else { throw RemovalError.refused("Could not verify application stopped after service shutdown: " + old.appPath + "; unresolved service candidates: " + old.items.filter { $0.kind == .manual }.map(\.path).joined(separator: ", ")) }
            }
            // Validate each item again; never permanently delete. Stop on a partial failure.
            let order: [FullRemovalItem.Kind] = [.application, .data, .candidate]
            for kind in order {
                for item in items where item.kind == kind {
                    let url = URL(fileURLWithPath: item.path)
                    let fresh = inspect(url, kind, item.reason, label: item.label, program: item.program)
                    if await isRunning() {
                        guard !dataOnly, await stop(), !(await isRunning()) else { throw RemovalError.refused("Could not verify process stopped while removing: " + item.path) }
                    }
                    let latest = inspect(url, kind, item.reason, label: item.label, program: item.program)
                    guard kind != .application || identity(item.path, old.bundleID) != nil else { throw RemovalError.refused("Application identity changed: " + item.path) }
                    guard latest == item || (!dataOnly && Self.sameApprovedData(item, latest)), latest == fresh || (!dataOnly && Self.sameApprovedData(fresh, latest)) else { throw RemovalError.refused("File changed or unsafe: " + item.path) }
                    let destination: URL?
                    if kind == .application && !dataOnly {
                        destination = try ServiceRemoval.moveWithPermissionFallback(url, trash: moveToTrash) {
                            let checked = inspect(url, kind, item.reason, label: item.label, program: item.program)
                            guard identity(item.path, old.bundleID) != nil, checked == latest || Self.sameApprovedData(latest, checked) else { throw RemovalError.refused("Application identity changed before administrator authorization: " + item.path) }
                            return try authorizedAppMove(checked, old.bundleID)
                        }
                    } else {
                        destination = try moveToTrash(url)
                    }
                    guard !exists(item.path) else { throw RemovalError.refused("Removal reported success but item remains: " + item.path) }
                    result.moved.append((item.path, destination?.path ?? "Trash"))
                }
            }
            for item in items where item.kind == .machineData {
                let latest = inspect(URL(fileURLWithPath: item.path), .machineData, item.reason)
                guard !(await isRunning()), ServiceRemoval.rootChain(item.path), latest == item || Self.sameApprovedData(item, latest), let fileIdentity = ServiceRemoval.statIdentity(item.path) else { throw RemovalError.refused("Machine data changed or unsafe: " + item.path) }
                let reply = ServiceRemoval.administrator(ServiceRemoval.rootMoveScript(path: item.path, identity: fileIdentity, service: nil, program: nil))
                guard reply.status == 0, reply.output.hasPrefix("/private/var/root/MacMaintenance-removed."), !exists(item.path) else { throw RemovalError.refused("Administrator data step failed: " + item.path + " — " + reply.output) }
                result.moved.append((item.path, reply.output))
            }
            let remaining = items.filter { exists($0.path) }.map(\.path)
            if !remaining.isEmpty { result.failures.append("Selected paths remain: " + remaining.joined(separator: ", ")) }
            if await isRunning() { result.failures.append("Related process still running or process listing unavailable after removal.") }
            let unselected = old.items.filter { (!$0.allowed || !selected.contains($0.path)) && exists($0.path) }.map { $0.path + " — " + $0.reason }
            if !unselected.isEmpty { result.failures.append("Not removed (unselected or unverified): " + unselected.joined(separator: ", ")) }
            if !dataOnly { result.failures.append(contentsOf: old.blockers.map { old.appPath + ": " + $0 }) }
        } catch {
            result.failures.append(old.appPath + ": " + error.localizedDescription)
            let pending = old.items.filter { selected.contains($0.path) && exists($0.path) }.map(\.path)
            if !pending.isEmpty { result.failures.append("Selected paths still present: " + pending.joined(separator: ", ")) }
        }
        return result
    }
    #endif
}
