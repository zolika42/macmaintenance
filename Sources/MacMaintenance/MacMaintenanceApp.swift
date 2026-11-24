#if os(macOS)
import SwiftUI
import AppKit
import Darwin
import MaintenanceCore
import CryptoKit

private enum Page: String, CaseIterable, Identifiable {
    case overview, monitor, clean, apps, advanced, developer, storage, startup, security, history, updates, settings
    var id: String { rawValue }
    var icon: String {
        switch self { case .overview: "gauge.with.dots.needle.33percent"; case .monitor: "waveform.path.ecg"; case .updates: "arrow.triangle.2.circlepath"; case .clean: "sparkles"; case .advanced: "wand.and.stars"; case .startup: "power"; case .developer: "terminal"; case .storage: "internaldrive"; case .security: "shield"; case .apps: "square.grid.2x2"; case .history: "clock.arrow.circlepath"; case .settings: "gearshape" }
    }
    func label(_ hu: Bool) -> String {
        if !hu { return rawValue.capitalized }
        return switch self { case .overview: "Áttekintés"; case .monitor: "Rendszermonitor"; case .updates: "Frissítések"; case .clean: "Takarítás"; case .advanced: "Speciális takarítás"; case .startup: "Indítási elemek"; case .developer: "Fejlesztés"; case .storage: "Tárhely"; case .security: "Biztonság"; case .apps: "Alkalmazások"; case .history: "Előzmények"; case .settings: "Beállítások" }
    }
}
private func size(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
private struct HistoryItem: Codable, Identifiable, Sendable {
    var id = UUID(); var date = Date(); let event: String; let detail: String; var recovery: RecoveryReceipt? = nil; var privilegedTarget: String? = nil
}
private struct AppItem: Identifiable, Sendable {
    var id: String { path }; let path: String; let name: String; let bundle: String; let version: String; let executable: String?
}
private struct LargeFile: Identifiable, Sendable { var id: String { path }; let path: String; let bytes: Int64; let duplicate: String? }
private struct StorageResult: Sendable { var items: [LargeFile]; var notes: [String] }
private enum LocalAudit {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static func commands(_ page: Page) -> [Command] {
        switch page {
        case .overview: return [
            .init("Hardware", "/usr/sbin/sysctl", ["hw.model", "hw.ncpu", "hw.memsize"]),
            .init("macOS", "/usr/bin/sw_vers", []),
            .init("Storage", "/bin/df", ["-h", "/System/Volumes/Data"]),
            .init("Memory pressure", "/usr/bin/memory_pressure", ["-Q"]),
            .init("Swap", "/usr/sbin/sysctl", ["vm.swapusage"]),
            .init("CPU and processes", "/usr/bin/top", ["-l", "2", "-n", "10", "-o", "cpu", "-stats", "pid,command,cpu,mem"]),
            .init("Battery", "/usr/sbin/system_profiler", ["SPPowerDataType"]),
            .init("SSD / APFS", "/usr/sbin/diskutil", ["info", "/"]),
            .init("Thermal state", "/usr/bin/pmset", ["-g", "therm"])]
        case .developer:
            let dockerPaths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker", home.appendingPathComponent(".docker/bin/docker").path]
            let docker = dockerPaths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? dockerPaths[0]
            let socket = home.appendingPathComponent(".docker/run/docker.sock").path
            let host = "unix://" + socket
            return [.init("Docker Desktop disk usage (local socket only)", docker, ["--host", host, "system", "df", "-v"]),
                    .init("Docker containers", docker, ["--host", host, "ps", "-a", "--format", "{{.Names}}\t{{.Status}}\t{{.Image}}"]),
                    .init("Docker volumes (protected)", docker, ["--host", host, "volume", "ls"]),
                    .init("Homebrew packages", "/opt/homebrew/bin/brew", ["list", "--versions"]),
                    .init("Xcode simulators", "/usr/bin/xcrun", ["simctl", "list", "devices"]),
                    .init("Swift", "/usr/bin/swift", ["--version"]),
                    .init("Git", "/usr/bin/git", ["--version"])]
        case .security: return [
            .init("FileVault", "/usr/bin/fdesetup", ["status"]),
            .init("SIP", "/usr/bin/csrutil", ["status"]),
            .init("Gatekeeper", "/usr/sbin/spctl", ["--status"]),
            .init("Firewall", "/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]),
            .init("Listening TCP ports (visible to user)", "/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]),
            .init("Login and background items", "/usr/bin/sfltool", ["dumpbtm"]),
            .init("Installed updates (local history)", "/usr/sbin/softwareupdate", ["--history"])]
        case .storage: return [.init("Time Machine local snapshots", "/usr/bin/tmutil", ["listlocalsnapshots", "/"])]
        default: return []
        }
    }
    static func listing(_ paths: [URL]) -> String {
        paths.map { path in
            let files = (try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])) ?? []
            let lines = files.sorted { $0.path < $1.path }.prefix(500).map { file in
                let a = try? FileManager.default.attributesOfItem(atPath: file.path)
                let mode = (a?[.posixPermissions] as? NSNumber)?.intValue ?? 0
                let type = (a?[.type] as? FileAttributeType)?.rawValue ?? "unknown"
                return "\(String(mode, radix: 8))  \(type)  \(file.lastPathComponent)"
            }
            return path.path + "\n" + (lines.isEmpty ? "(empty, absent, or inaccessible)" : lines.joined(separator: "\n"))
        }.joined(separator: "\n\n")
    }
    static func applications() -> [AppItem] {
        let fm = FileManager.default
        var found: [AppItem] = []
        for root in [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), home.appendingPathComponent("Applications")] {
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in en {
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { en.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }; en.skipDescendants()
                let b = Bundle(url: url)
                found.append(.init(path: url.path, name: url.deletingPathExtension().lastPathComponent, bundle: b?.bundleIdentifier ?? "", version: b?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—", executable: b?.executableURL?.path))
                if found.count >= 1000 { break }
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func largeFiles(at root: URL) -> StorageResult {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { return .init(items: [], notes: ["Directory unavailable"]) }
        var largest = LargestCandidates(); var visited = 0, eligible = 0, unreadable = 0; var notes: [String] = []
        let end = ProcessInfo.processInfo.systemUptime + 20
        for case let url as URL in en {
            visited += 1
            if visited > 150_000 || ProcessInfo.processInfo.systemUptime >= end || Task.isCancelled { notes.append("Partial scan: time or item limit"); break }
            guard let r = try? url.resourceValues(forKeys: keys) else { unreadable += 1; continue }
            if r.isSymbolicLink == true { en.skipDescendants(); continue }
            if r.isRegularFile == true, let n = r.fileSize, n >= 1_000_000 { eligible += 1; largest.add(.init(url: url, bytes: Int64(n))) }
        }
        let items = largest.result.map { ($0.url, $0.bytes) }
        if eligible > items.count { notes.append("Candidate limit: retained largest \(items.count) of \(eligible) visible files.") }
        if unreadable > 0 { notes.append("Unreadable metadata: \(unreadable) items skipped.") }
        var hashes: [String: String] = [:], budget: Int64 = 256_000_000
        let bySize = Dictionary(grouping: items.prefix(2000), by: { $0.1 })
        for key in bySize.keys.sorted(by: >) {
            guard let group = bySize[key], group.count > 1 else { continue }
            for (url, n) in group where n <= 64_000_000 && n <= budget {
                guard ProcessInfo.processInfo.systemUptime < end, !Task.isCancelled else { break }
                budget -= n
                guard let fh = try? FileHandle(forReadingFrom: url) else { continue }
                defer { try? fh.close() }
                var sha = SHA256(); var read: Int64 = 0; var ok = true
                do { while let d = try fh.read(upToCount: 1_048_576), !d.isEmpty { sha.update(data: d); read += Int64(d.count); if read > n || Task.isCancelled || ProcessInfo.processInfo.systemUptime >= end { ok = false; break } } } catch { ok = false }
                if ok && read == n { hashes[url.path] = sha.finalize().map { String(format: "%02x", $0) }.joined() }
            }
        }
        let counts = Dictionary(grouping: hashes.values, by: { $0 }).mapValues(\.count)
        notes.append("Largest 500 files ≥ 1 MB; duplicate SHA-256 sampling up to 256 MB, files ≤ 64 MB; not exhaustive.")
        return .init(items: items.prefix(500).map { url, n in
            let h = hashes[url.path]; return LargeFile(path: url.path, bytes: n, duplicate: h.flatMap { (counts[$0] ?? 0) > 1 ? $0 : nil })
        }, notes: notes)
    }
}
@MainActor private final class Model: ObservableObject {
    @Published var page: Page = .overview
    @Published var busy = false
    @Published var commandResults: [Page: [CommandResult]] = [:]
    @Published var securityFiles = ""
    @Published var scan = ScanResult()
    @Published var selected = Set<String>()
    @Published var storage = ScanResult()
    @Published var large = StorageResult(items: [], notes: [])
    @Published var apps: [AppItem] = []
    @Published var storageLocation = ""
    @Published var cachesScanned = false
    @Published var appsLoaded = false
    @Published var storageScanned = false
    @Published var history: [HistoryItem] = []
    @Published var message = ""
    @Published var confirm = false
    @Published var lastAudit: Date?
    @Published var browserScan = BrowserScan()
    @Published var browserSelected = Set<String>()
    @Published var browserScanned = false
    @Published var leftovers: [LeftoverCandidate] = []
    @Published var leftoversScanned = false
    @Published var startupItems: [StartupItem] = []
    @Published var startupLoaded = false
    @Published var dockerPlan: DockerCachePlan?
    @Published var dockerResult: CommandResult?
    @Published var brewPreview: CommandResult?
    private let historyURL = LocalAudit.home.appendingPathComponent("Library/Application Support/MacMaintenance/history.json")
    private let scanner = Scanner(roots: Scanner.cacheRoots(home: LocalAudit.home))
    init() { if let data = try? Data(contentsOf: historyURL), let old = try? JSONDecoder().decode([HistoryItem].self, from: data) { history = old } }
    func record(_ event: String, _ detail: String, recovery: RecoveryReceipt? = nil, privilegedTarget: String? = nil) {
        history.insert(.init(event: event, detail: detail, recovery: recovery, privilegedTarget: privilegedTarget), at: 0); history = Array(history.prefix(500))
        saveHistory()
    }
    private func saveHistory() {
        do { try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); try JSONEncoder().encode(history).write(to: historyURL, options: .atomic) } catch { message = "History save failed: \(error.localizedDescription)" }
    }
    func run(_ p: Page) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let result = await Task.detached(priority: .utility) { LocalAudit.commands(p).map { Runner.run($0) } }.value
        commandResults[p] = result
        if p == .security {
            securityFiles = await Task.detached(priority: .utility) { LocalAudit.listing([LocalAudit.home.appendingPathComponent(".ssh"), LocalAudit.home.appendingPathComponent("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchDaemons")]) }.value
        }
        if p == .overview { lastAudit = Date() }
        record("Audit", p.rawValue + ": \(result.count) checks; \(result.filter { $0.status == 0 }.count) exit zero")
    }
    func scanBrowserCaches() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        browserSelected = []
        browserScan = await Task.detached(priority: .utility) { AdvancedCleaner().scanBrowsers() }.value
        browserScanned = true; record("Browser scan", "\(browserScan.items.count) cache folders")
    }
    var chosenBrowsers: [BrowserCache] { browserScan.items.filter { $0.entry.cleanable && browserSelected.contains($0.id) } }
    func cleanBrowsers(_ items: [BrowserCache]) async {
        guard !busy, !items.isEmpty else { return }; busy = true; defer { busy = false }
        browserSelected = []
        let result = await Task.detached(priority: .utility) { () -> ([(String, String)], [String]) in
            var moved: [(String, String)] = [], errors: [String] = []
            for item in items {
                do {
                    let dest = try await AdvancedCleaner().trashBrowser(item, isRunning: {
                        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier?.lowercased().hasPrefix(item.bundleID.lowercased()) == true }
                    })
                    moved.append((item.id, dest?.path ?? "Trash"))
                } catch { errors.append(item.id + ": " + error.localizedDescription) }
            }
            return (moved, errors)
        }.value
        let movedIDs = Set(result.0.map { $0.0 }); browserScan.items.removeAll { movedIDs.contains($0.id) }
        for (path, dest) in result.0 { record("Browser cache Trash", path + " → " + dest) }
        for error in result.1 { record("Browser cache refused", error) }
        message = "Browser caches moved: \(result.0.count); refused: \(result.1.count)\n" + result.1.joined(separator: "\n")
    }
    func scanLeftovers() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        leftovers = await Task.detached(priority: .utility) {
            let ids = Set(LocalAudit.applications().map(\.bundle).filter { !$0.isEmpty })
            return AdvancedCleaner().leftoverHints(installedIDs: ids)
        }.value
        leftoversScanned = true; record("Leftover hints", "\(leftovers.count) read-only candidates")
    }
    func scanStartup() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        startupItems = await Task.detached(priority: .utility) { AdvancedCleaner().startupItems() }.value
        startupLoaded = true; record("Startup audit", "\(startupItems.count) visible plist files")
    }
    func reviewDocker(_ days: Int) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        dockerPlan = nil; dockerResult = nil
        dockerPlan = await Task.detached(priority: .utility) { DockerCacheManager().review(days: days) }.value
        record("Docker cache audit", "\(days) days; local audit exit \(dockerPlan?.audit.status.map { String($0) } ?? "unavailable")")
    }
    func pruneDocker(_ plan: DockerCachePlan) async {
        guard !busy, plan.eligible else { return }; busy = true; defer { busy = false }
        dockerPlan = nil
        let result = await Task.detached(priority: .utility) { () -> CommandResult? in try? DockerCacheManager().prune(plan) }.value
        dockerResult = result
        if let result {
            record("Docker cache prune", "exit \(result.status.map { String($0) } ?? "unknown"): " + String(result.output.prefix(1200)))
            message = result.status == 0 ? "Docker build cache prune completed. See Docker panel for the result." : "Docker operation failed or outcome is uncertain. Audit again before retrying."
        } else { record("Docker prune refused", "Local Desktop could not be reverified"); message = "Local Docker Desktop could not be reverified. Scan again." }
    }
    func previewBrew() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        brewPreview = await Task.detached(priority: .utility) { Runner.run(.init("Homebrew cleanup preview", "/opt/homebrew/bin/brew", ["cleanup", "--dry-run"]), timeout: 30) }.value
        record("Homebrew preview", "Read-only cleanup preview")
    }
    func scanCaches() async {
        guard !busy else { return }; busy = true; defer { busy = false }; selected = []
        let scanner = self.scanner
        scan = await Task.detached(priority: .utility) { scanner.scan(seconds: 60) }.value
        scan.entries.sort { $0.bytes > $1.bytes }; cachesScanned = true; record("Cache scan", "\(scan.entries.count) entries")
    }
    var chosen: [Entry] { scan.entries.filter { selected.contains($0.id) && $0.cleanable } }
    func cleanup() async {
        guard !busy else { return }; let items = chosen; guard !items.isEmpty else { return }
        busy = true; defer { busy = false }; let scanner = self.scanner
        let result = await Task.detached(priority: .utility) { () -> ([(String, String, RecoveryReceipt?)], [String]) in
            var done: [(String, String, RecoveryReceipt?)]=[], errors: [String]=[]
            for item in items {
                do {
                    let target = try scanner.trash(item)
                    let receipt = target.flatMap { try? CacheRecovery().capture(original: item, destination: $0) }
                    done.append((item.id, target?.path ?? "Trash", receipt))
                } catch { errors.append(item.path + ": " + error.localizedDescription) }
            }
            return (done, errors)
        }.value
        let moved = Set(result.0.map { $0.0 })
        scan.entries.removeAll { moved.contains($0.id) }; selected = []
        for (original, destination, receipt) in result.0 { record("Trash item", original + " → " + destination, recovery: receipt) }
        for error in result.1 { record("Trash refused", error) }
        message = "Moved to Trash: \(result.0.count). Failed: \(result.1.count).\n" + result.1.joined(separator: "\n")
        record("Trash", "\(result.0.count) moved; \(result.1.count) refused")
    }
    func restorePrivileged(_ item: HistoryItem) async {
        guard !busy, let target = item.privilegedTarget, history.contains(where: { $0.id == item.id && $0.privilegedTarget == target }) else { return }
        busy = true; defer { busy = false }
        let reply = await Task.detached(priority: .utility) { PrivilegedRecovery.restore(target) }.value
        if let reply, reply.status == 0 {
            if let i = history.firstIndex(where: { $0.id == item.id }) { history[i].privilegedTarget = nil }
            record("Privileged file restored", reply.output)
            message = "File restored. Services were not re-enabled; reinstall or review them separately."
        } else { message = "Restore refused or cancelled: " + (reply?.output ?? "Invalid receipt") }
    }
    func restoreCache(_ item: HistoryItem) async {
        guard !busy, let receipt = item.recovery, history.contains(where: { $0.id == item.id && $0.recovery != nil }) else { return }
        busy = true; defer { busy = false }
        let error = await Task.detached(priority: .utility) { () -> String? in
            do { try CacheRecovery().restore(receipt); return nil } catch { return error.localizedDescription }
        }.value
        if let error { record("Restore refused", receipt.original.path + ": " + error); message = error }
        else {
            if let i = history.firstIndex(where: { $0.id == item.id }) { history[i].recovery = nil }
            record("Cache restored", receipt.original.path)
            cachesScanned = false; scan = ScanResult(); selected = []
            message = "Restored: " + receipt.original.path
        }
    }
    func reviewFull(_ items: [AppItem]) async -> [FullRemovalReview] {
        guard !busy else { return [] }; busy = true; defer { busy = false }
        return await Task.detached(priority: .utility) { items.prefix(20).map { FullUninstaller().review(appPath: $0.path, bundleID: $0.bundle) } }.value
    }
    func removeFull(_ reviews: [FullRemovalReview], selected: Set<String>, dataOnly: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let result = await Task.detached(priority: .utility) { () -> FullRemovalResult in
            var result = FullRemovalResult()
            for review in reviews {
                let shared = Set(reviews.flatMap(\.items).map(\.path).filter { path in reviews.filter { $0.items.contains { $0.path == path } }.count > 1 })
                let paths = selected.intersection(Set(review.items.filter(\.allowed).map(\.path))).subtracting(shared)
                if !shared.isDisjoint(with: selected) { result.failures.append("Shared selection refused: " + review.appPath) }
                if paths.isEmpty { continue }
                if !dataOnly && (!review.canRemoveApp || !paths.contains(review.appPath)) { result.failures.append(review.appPath + ": application not selected or unsafe"); continue }
                var ids = Set(LocalAudit.applications().filter { $0.path != review.appPath }.map(\.bundle))
                let registered = await MainActor.run { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: review.bundleID).contains { $0.path != review.appPath && FileManager.default.fileExists(atPath: $0.path) } }
                if registered { ids.insert(review.bundleID) }
                let partial = await FullUninstaller().trash(review, selected: paths, otherIDs: ids, dataOnly: dataOnly, stop: { await Model.stopFull(review) }, isRunning: { Model.runningFull(review) })
                result.moved += partial.moved; result.failures += partial.failures
            }
            return result
        }.value
        for (source, target) in result.moved { record("Application / data removed", source + " → " + target, privilegedTarget: PrivilegedRecovery.validDestination(target) ? target : nil) }
        for failure in result.failures { record("Application removal refused", failure) }
        apps = await Task.detached(priority: .utility) { LocalAudit.applications() }.value
        message = "Removed to Trash/quarantine: \(result.moved.count); warnings/refusals: \(result.failures.count).\n" + result.failures.joined(separator: "\n")
    }
    // Match executable paths, not process names or vendor-wide prefixes.
    static func ownedRunningApps(_ review: FullRemovalReview) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard !app.isTerminated else { return false }
            let path = app.bundleURL?.path ?? ""
            let executable = app.executableURL?.path ?? ""
            return path == review.appPath || path.hasPrefix(review.appPath + "/") || executable.hasPrefix(review.appPath + "/")
        }
    }
    static func runningFull(_ review: FullRemovalReview) -> Bool {
        !ownedRunningApps(review).isEmpty || !(ServiceRemoval.userProcesses(in: review.appPath)?.isEmpty ?? false)
    }
    static func stopFull(_ review: FullRemovalReview) async -> Bool {
        for app in ownedRunningApps(review) { _ = app.terminate() }
        await Task.detached(priority: .utility) { ServiceRemoval.signalOwnedProcesses(in: review.appPath, force: false) }.value
        var quiet = 0
        for _ in 0..<20 {
            quiet = runningFull(review) ? 0 : quiet + 1
            if quiet >= 3 { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        // Explicitly approved full uninstall permits force-quit after graceful termination.
        for app in ownedRunningApps(review) { _ = app.forceTerminate() }
        await Task.detached(priority: .utility) { ServiceRemoval.signalOwnedProcesses(in: review.appPath, force: true) }.value
        quiet = 0
        for _ in 0..<16 {
            if runningFull(review) {
                quiet = 0
                for app in ownedRunningApps(review) { _ = app.forceTerminate() }
                await Task.detached(priority: .utility) { ServiceRemoval.signalOwnedProcesses(in: review.appPath, force: true) }.value
            } else {
                quiet += 1
                if quiet >= 4 { return true }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
    func scanStorage(_ folder: URL? = nil) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        storage = await Task.detached(priority: .utility) {
            let defaults = ["Projects", "Downloads", "Documents", "Desktop", "Library/Developer", "Library/Caches"].map { ScanRoot($0, $0, LocalAudit.home.appendingPathComponent($0), cleanable: false) } + [ScanRoot("Applications", "Applications", URL(fileURLWithPath: "/Applications"), cleanable: false)]
            let roots = folder.map { [ScanRoot("folder", $0.lastPathComponent, $0, cleanable: false)] } ?? defaults
            return Scanner(roots: roots).scan(seconds: 60)
        }.value
        storage.entries.sort { $0.bytes > $1.bytes }; storageLocation = folder?.path ?? ""; storageScanned = true; record("Storage", "\(storage.entries.count) entries")
    }
    func scanLarge(_ url: URL) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        large = await Task.detached(priority: .utility) { LocalAudit.largeFiles(at: url) }.value
        record("Large files", "\(large.items.count) displayed")
    }
    func loadApps() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        apps = await Task.detached(priority: .utility) { LocalAudit.applications() }.value; appsLoaded = true; record("Apps", "\(apps.count) applications")
    }

}
@main struct MacMaintenanceApp: App {
    @StateObject private var model = Model()
    @StateObject private var live = LiveMonitor()
    @StateObject private var updates = UpdateCenter()
    @AppStorage("hungarian") private var hu = true
    @AppStorage("scheduledAudit") private var schedule = false
    @AppStorage("menuBar") private var menuBar = false
    var body: some Scene {
        WindowGroup("MacMaintenance", id: "main") { MainView(model: model, live: live, updates: updates).frame(minWidth: 960, minHeight: 650) }
        .defaultSize(width: 1120, height: 760)
        .commands { UpdateCommands(model: model, updates: updates, hu: hu) }
        MenuBarExtra(isInserted: $menuBar) {
            MenuView(model: model, live: live, updates: updates, hu: hu)
        } label: {
            Label("MacMaintenance", systemImage: updates.available == nil && updates.onlineRelease == nil ? "gauge.with.dots.needle.33percent" : "arrow.down.circle.fill")
        }
    }
}
private struct UpdateCommands: Commands {
    @ObservedObject var model: Model
    @ObservedObject var updates: UpdateCenter
    let hu: Bool
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu(hu ? "Frissítések" : "Updates") {
            Button(hu ? "Frissítések keresése…" : "Check for updates…") {
                model.page = .updates; openWindow(id: "main"); Task { await updates.check() }
            }.disabled(updates.checking)
            Button(hu ? "Frissítési beállítások" : "Update settings") { model.page = .updates; openWindow(id: "main") }
        }
    }
}
private struct MenuView: View {
    @ObservedObject var model: Model
    @ObservedObject var live: LiveMonitor
    @ObservedObject var updates: UpdateCenter
    let hu: Bool
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(hu ? "Megnyitás" : "Open") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(hu ? "Rendszeraudit" : "System audit") { Task { await model.run(.overview) } }.disabled(model.busy)
        Divider()
        if let latest = live.latest {
            Text("CPU: " + (latest.cpu.map { String(format: "%.0f%%", $0) } ?? "—") + " · RAM: " + (latest.memoryPercent.map { String(format: "%.0f%%", $0) } ?? "—"))
            Text((live.running ? "" : (hu ? "Szünet · " : "Paused · ")) + latest.date.formatted(date: .omitted, time: .standard))
        }
        Button(hu ? "Rendszermonitor" : "Live monitor") { model.page = .monitor; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(live.running ? (hu ? "Monitor szüneteltetése" : "Pause monitor") : (hu ? "Monitor indítása" : "Start monitor")) { if live.running { live.stop() } else { live.start() } }
        Divider()
        if let release = updates.available { Text((hu ? "Új kiadás: " : "New release: ") + release.version.description) }; if let release = updates.onlineRelease { Text((hu ? "Új online kiadás: " : "New online release: ") + release.version) }
        Button(hu ? "Frissítések keresése…" : "Check for updates…") { model.page = .updates; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true); Task { await updates.check() } }.disabled(updates.checking)
        Button(hu ? "Kilépés" : "Quit") { NSApp.terminate(nil) }
    }
}
private struct MainView: View {
    @ObservedObject var model: Model
    @ObservedObject var live: LiveMonitor
    @ObservedObject var updates: UpdateCenter
    @AppStorage("hungarian") private var hu = true
    @AppStorage("scheduledAudit") private var schedule = false
    @AppStorage("menuBar") private var menuBar = false
    @AppStorage("maintenance.profile") private var profileRaw = MaintenanceProfile.conservative.rawValue
    @AppStorage("permissions.reviewedVersion") private var reviewedPermissionVersion = ""
    @State private var showPermissionSetup = false
    @State private var batchPaths = Set<String>()
    @State private var batchReviews: [FullRemovalReview] = []
    @State private var fullSelected = Set<String>()
    @State private var showBatch = false
    @State private var pendingRecovery: HistoryItem?
    @State private var showRecovery = false
    @State private var showPrivilegedRecovery = false
    @State private var query = ""
    @State private var onlyCleanable = false
    @State private var cacheGroup = "all"
    @State private var showRawAudit = false
    @State private var storageDuplicatesOnly = false
    @State private var appSort = "name"
    @State private var advancedTab = "browser"
    @State private var dockerDays = 7
    @State private var browserReview: [BrowserCache] = []
    @State private var showBrowserConfirm = false
    @State private var showDockerConfirm = false
    @State private var pendingDockerPlan: DockerCachePlan?
    private func t(_ a: String, _ b: String) -> String { hu ? a : b }
    private func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    var body: some View {
        NavigationSplitView {
            List { ForEach(Page.allCases) { p in
                Button { model.page = p; query = "" } label: { Label(p.label(hu), systemImage: p.icon).frame(maxWidth: .infinity, alignment: .leading).padding(6).background(model.page == p ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain)
            } }.navigationSplitViewColumnWidth(min: 175, ideal: 205)
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text(model.page.label(hu)).font(.largeTitle.bold()); Spacer(); if model.busy { ProgressView().controlSize(.small); Text(t("Vizsgálat folyamatban", "Working…")).foregroundStyle(.secondary) } }
                if let release = updates.available, model.page != .updates {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                        Text(t("Új MacMaintenance kiadás érhető el: ", "New MacMaintenance release: ") + release.version.description).fontWeight(.medium)
                        Spacer()
                        Button(t("Frissítések", "Updates")) { model.page = .updates }
                    }.padding(10).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                switch model.page {
                case .overview: overview
                case .monitor: MonitorPanel(live: live, hu: hu)
                case .updates: UpdatesPanel(updates: updates, hu: hu)
                case .clean: clean
                case .advanced: advanced
                case .startup: startup
                case .developer: developer
                case .storage: storage
                case .security: security
                case .apps: apps
                case .history: history
                case .settings: settings
                }
                Spacer(minLength: 0)
            }.padding(24)
        }
        .alert(t("Karbantartási eredmény", "Maintenance result"), isPresented: Binding(get: { !model.message.isEmpty }, set: { if !$0 { model.message = "" } })) { Button("OK") { model.message = "" } } message: { Text(model.message) }
        .confirmationDialog(t("A kijelölt cache-elemek kukába helyezése?", "Move selected caches to Trash?"), isPresented: $model.confirm, titleVisibility: .visible) {
            Button(t("Áthelyezés a Kukába", "Move to Trash"), role: .destructive) { Task { await model.cleanup() } }
            Button(t("Mégse", "Cancel"), role: .cancel) {}
        } message: { Text(t("Zárd be az érintett alkalmazásokat és buildfolyamatokat. A Kuka ürítése külön művelet. A módosult elemeket nem helyezzük át.", "Close related apps and build processes. Emptying Trash is separate. Changed items are refused.") + "\n\(model.chosen.count) · \(size(model.chosen.reduce(0) { $0 + $1.bytes }))") }
        .sheet(isPresented: $showPermissionSetup) {
            PermissionSetup(hu: hu, updates: updates) {
                reviewedPermissionVersion = updates.installed; showPermissionSetup = false
                Task { if model.lastAudit == nil { await model.run(.overview) } }
            }
        }
        .sheet(isPresented: $showBatch) { batchSheet }
        .confirmationDialog(t("Adminisztrátori fájl visszaállítása?", "Restore administrator item?"), isPresented: $showPrivilegedRecovery, titleVisibility: .visible) {
            Button(t("Visszaállítás", "Restore")) { if let item = pendingRecovery { Task { await model.restorePrivileged(item) } } }
            Button(t("Mégse", "Cancel"), role: .cancel) {}
        } message: { Text(t("Hitelesítés szükséges. Meglévő fájlt nem írunk felül; a szolgáltatásokat nem engedélyezzük újra automatikusan.", "Authentication required. Existing files are not overwritten; services are not automatically re-enabled.")) }
        .confirmationDialog(t("Cache visszaállítása?", "Restore cache?"), isPresented: $showRecovery, titleVisibility: .visible) {
            Button(t("Visszaállítás", "Restore")) { if let item = pendingRecovery { Task { await model.restoreCache(item) } } }
            Button(t("Mégse", "Cancel"), role: .cancel) {}
        } message: { Text(t("Zárd be az érintett alkalmazásokat. A meglévő fájlokat nem írjuk felül.", "Close related apps. Existing files will not be overwritten.") + "\n" + (pendingRecovery?.recovery?.original.path ?? "")) }
        .sheet(isPresented: $showBrowserConfirm) { browserConfirmation }
        .sheet(isPresented: $showDockerConfirm) { dockerConfirmation }
        .task {
            if PermissionSetupPolicy.needsReview(installedVersion: updates.installed, reviewedVersion: reviewedPermissionVersion) { showPermissionSetup = true }
            else if model.lastAudit == nil { await model.run(.overview) }
        }
        .task(id: schedule) { guard schedule else { return }; while !Task.isCancelled { do { try await Task.sleep(for: .seconds(3600)) } catch { return }; if !Task.isCancelled { await model.run(.overview) } } }
    }
    private var diskStats: (total: Int64, free: Int64) {
        let a = try? FileManager.default.attributesOfFileSystem(forPath: LocalAudit.home.path)
        let total = (a?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (a?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return (max(0, total), min(max(0, free), max(0, total)))
    }
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("MacMaintenance").font(.title2.bold()); Spacer(); Text("v" + updates.installed + " · ARM64").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 14) {
                    diskCard
                    VStack(spacing: 10) {
                        metric("RAM", size(Int64(ProcessInfo.processInfo.physicalMemory)), "memorychip")
                        metric("CPU", "\(ProcessInfo.processInfo.activeProcessorCount) " + t("mag", "cores"), "cpu")
                    }
                }
                HStack(spacing: 10) {
                    Button { model.page = .monitor } label: { Label(t("Élő rendszermonitor", "Live monitor"), systemImage: "waveform.path.ecg") }
                    Button { model.page = .updates; Task { await updates.check() } } label: { Label(t("Frissítések keresése", "Check updates"), systemImage: "arrow.clockwise") }.disabled(updates.checking)
                    Spacer()
                }.buttonStyle(.bordered)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("Vizsgálat, kijelölés, jóváhagyás. Automatikus törlés nélkül.", "Scan, select, approve. No automatic deletion.")).foregroundStyle(.secondary)
                        HStack { Button { model.page = .clean; query = ""; Task { await model.scanCaches(); model.selected = currentProfile.selection(model.scan.entries) } } label: { Label(t("Intelligens vizsgálat és kijelölés", "Smart scan and select"), systemImage: "sparkles") }.buttonStyle(.borderedProminent).disabled(model.busy)
                            Spacer(); if model.cachesScanned { Text(size(model.scan.entries.filter(\.cleanable).reduce(0) { $0 + $1.bytes }) + " · " + t("takarítható becslés", "eligible estimate")).font(.headline) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(7)
                } label: { Label(t("Intelligens karbantartás", "Smart maintenance"), systemImage: "sparkles") }
                HStack(spacing: 10) {
                    Button { model.page = .apps; query = ""; Task { await model.loadApps() } } label: { Label(t("Alkalmazások", "Applications"), systemImage: "square.grid.2x2") }.disabled(model.busy)
                    Button { model.page = .storage; query = ""; Task { await model.scanStorage() } } label: { Label(t("Tárhelyelemző", "Storage analyzer"), systemImage: "chart.bar.xaxis") }.disabled(model.busy)
                    Button { model.page = .advanced } label: { Label(t("Speciális takarítás", "Advanced cleaning"), systemImage: "wand.and.stars") }.disabled(model.busy)
                    Button { model.page = .security; Task { await model.run(.security) } } label: { Label(t("Biztonság", "Security"), systemImage: "shield") }.disabled(model.busy)
                }.buttonStyle(.bordered)
                HStack { Button(t("Rendszeraudit frissítése", "Refresh system audit")) { Task { await model.run(.overview) } }.disabled(model.busy); if let last = model.lastAudit { Text(last.formatted()).foregroundStyle(.secondary) }; Spacer() }
                DisclosureGroup(t("Részletes rendszerjelentés", "Detailed system report"), isExpanded: $showRawAudit) { report(.overview).frame(minHeight: 260) }
            }.padding(.bottom, 12)
        }
    }
    private var diskCard: some View {
        let stats = diskStats
        let used = max(0, stats.total - stats.free)
        let fraction = stats.total > 0 ? Double(used) / Double(stats.total) : 0
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 13)
                Circle().trim(from: 0, to: fraction).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 3) { Text(stats.total > 0 ? "\(Int(fraction * 100))%" : "—").font(.title.bold()).monospacedDigit(); Text("SSD").font(.caption).foregroundStyle(.secondary) }
            }.frame(width: 105, height: 105)
            VStack(alignment: .leading, spacing: 6) {
                Text(t("Szabad tárhely", "Free space")).font(.subheadline).foregroundStyle(.secondary)
                Text(stats.total > 0 ? size(stats.free) : "—").font(.title.bold())
                Text(size(used) + " / " + size(stats.total)).font(.caption).foregroundStyle(.secondary)
                Text(t("Kötetszintű becslés", "Volume-level estimate")).font(.caption2).foregroundStyle(.secondary)
            }; Spacer(minLength: 0)
        }.padding(18).frame(maxWidth: .infinity, minHeight: 155, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 15))
    }
    private func metric(_ label: String, _ value: String, _ image: String) -> some View {
        HStack { Image(systemName: image).font(.title2).foregroundStyle(Color.accentColor); VStack(alignment: .leading, spacing: 4) { Text(label).foregroundStyle(.secondary); Text(value).font(.title2.bold()) }; Spacer() }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
    private var currentProfile: MaintenanceProfile { MaintenanceProfile(rawValue: profileRaw) ?? .conservative }
    private func profileName(_ p: MaintenanceProfile) -> String {
        switch p { case .conservative: t("Óvatos (npm naplók)", "Conservative (npm logs)"); case .development: t("Fejlesztői cache", "Developer caches"); case .allEligible: t("Minden engedélyezett", "All eligible") }
    }
    private var visibleCaches: [Entry] {
        model.scan.entries.filter { e in
            (query.isEmpty || e.path.localizedCaseInsensitiveContains(query)) && (!onlyCleanable || e.cleanable) && (cacheGroup == "all" || e.rootID == cacheGroup)
        }
    }
    private var clean: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                metric(t("Vizsgált méret", "Scanned size"), size(model.scan.entries.reduce(0) { $0 + $1.bytes }), "internaldrive")
                metric(t("Takarítható", "Eligible"), size(model.scan.entries.filter(\.cleanable).reduce(0) { $0 + $1.bytes }), "sparkles")
                metric(t("Kijelölve", "Selected"), size(model.chosen.reduce(0) { $0 + $1.bytes }), "checkmark.circle")
            }
            HStack {
                Button { Task { await model.scanCaches() } } label: { Label(t("Vizsgálat", "Scan"), systemImage: "magnifyingglass") }.buttonStyle(.borderedProminent).disabled(model.busy)
                Button(t("Látható biztonságosak", "Select visible eligible")) { model.selected.formUnion(visibleCaches.filter(\.cleanable).map(\.id)) }.disabled(model.busy || !visibleCaches.contains(where: \.cleanable))
                Button(t("Kijelölés törlése", "Clear selection")) { model.selected = [] }.disabled(model.busy || model.selected.isEmpty)
                Spacer()
                Button(t("Takarítás…", "Review cleanup…")) { model.confirm = true }.buttonStyle(.borderedProminent).disabled(model.busy || model.chosen.isEmpty)
            }
            HStack {
                Picker(t("Mentett profil", "Saved profile"), selection: $profileRaw) {
                    ForEach(MaintenanceProfile.allCases, id: \.rawValue) { p in Text(profileName(p)).tag(p.rawValue) }
                }.frame(maxWidth: 320).disabled(model.busy)
                Button(t("Profil alkalmazása", "Apply profile")) { model.selected = currentProfile.selection(model.scan.entries) }.disabled(model.busy || !model.cachesScanned)
                Spacer()
            }
            HStack {
                TextField(t("Szűrés útvonalra", "Filter by path"), text: $query)
                Picker(t("Kategória", "Category"), selection: $cacheGroup) {
                    Text(t("Mind", "All")).tag("all")
                    ForEach(Scanner.cacheRoots(home: LocalAudit.home)) { root in Text(root.title).tag(root.id) }
                }.frame(maxWidth: 280)
                Toggle(t("Csak takarítható", "Eligible only"), isOn: $onlyCleanable).toggleStyle(.checkbox)
            }
            if !model.cachesScanned && !model.busy { ContentUnavailableView(t("Kezdd egy vizsgálattal", "Start with a scan"), systemImage: "sparkles", description: Text(t("A vizsgálat nem töröl semmit.", "Scanning does not remove anything."))) }
            else {
                List {
                    ForEach(Scanner.cacheRoots(home: LocalAudit.home)) { root in
                        let entries = visibleCaches.filter { $0.rootID == root.id }
                        if !entries.isEmpty {
                            Section(root.title + " · " + size(entries.reduce(0) { $0 + $1.bytes })) {
                                ForEach(entries) { e in cacheRow(e) }
                            }
                        }
                    }
                }
            }
            if !model.scan.notes.isEmpty { Text(model.scan.notes.joined(separator: "\n")).font(.caption).foregroundStyle(.orange).lineLimit(4) }
            Text(t("Csak ellenőrzött fejlesztői cache-ek helyezhetők a Kukába. A méretek logikai becslések, nem garantált APFS-nyereség.", "Only verified developer caches can move to Trash. Logical estimates, not guaranteed APFS savings.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func cacheRow(_ e: Entry) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { model.selected.contains(e.id) }, set: { if $0 { model.selected.insert(e.id) } else { model.selected.remove(e.id) } })).labelsHidden().disabled(!e.cleanable || model.busy)
            VStack(alignment: .leading) { Text(URL(fileURLWithPath: e.path).lastPathComponent).fontWeight(.medium); Text(e.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1) }
            Spacer(); Text(size(e.bytes)).monospacedDigit(); if !e.complete { Label(t("Részleges", "Partial"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption) } else if !e.cleanable { Image(systemName: "lock").foregroundStyle(.secondary) }
            Button { reveal(e.path) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help(t("Megnyitás Finderben", "Reveal in Finder"))
        }.padding(.vertical, 3)
    }
    private var developer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Docker, Homebrew, Xcode és toolchain leltár. Docker volume, konténer, image és repository nem törölhető automatikusan.", "Docker, Homebrew, Xcode and toolchain inventory. No automatic removal of Docker volumes, containers, images or repositories.")).foregroundStyle(.secondary)
            HStack { Button(t("Fejlesztői audit", "Developer audit")) { Task { await model.run(.developer) } }.disabled(model.busy); Button(t("Cache-takarítás", "Cache cleanup")) { model.page = .clean }; Button(t("Projektméretek", "Project sizes")) { model.page = .storage }; Button("Docker / Homebrew") { advancedTab = "docker"; model.page = .advanced } }
            report(.developer)
        }
    }
    private var advanced: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(t("Modul", "Module"), selection: $advancedTab) {
                Text(t("Böngészők", "Browsers")).tag("browser")
                Text(t("Maradványok", "Leftovers")).tag("leftovers")
                Text("Docker").tag("docker")
                Text("Homebrew").tag("brew")
            }.pickerStyle(.segmented)
            switch advancedTab {
            case "leftovers": leftoverPanel
            case "docker": dockerPanel
            case "brew": brewPanel
            default: browserPanel
            }
        }
    }
    private var browserPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                metric(t("Vizsgált cache", "Scanned cache"), size(model.browserScan.items.reduce(0) { $0 + $1.entry.bytes }), "globe")
                metric(t("Kijelölve", "Selected"), size(model.chosenBrowsers.reduce(0) { $0 + $1.entry.bytes }), "checkmark.circle")
            }
            Text(t("Chrome, Edge, Brave és Firefox ismert cache-mappái. A sütik, jelszavak, előzmények és profiladatok nem részei a takarításnak. Zárd be a böngészőt és háttérfolyamatait.", "Known Chrome, Edge, Brave and Firefox cache folders only. Cookies, passwords, history and profile data are excluded. Quit browsers and background processes.")).foregroundStyle(.secondary)
            HStack {
                Button { Task { await model.scanBrowserCaches() } } label: { Label(t("Vizsgálat", "Scan"), systemImage: "magnifyingglass") }.buttonStyle(.borderedProminent).disabled(model.busy)
                Button(t("Takaríthatók kijelölése", "Select eligible")) { model.browserSelected = Set(model.browserScan.items.filter { $0.entry.cleanable }.map(\.id)) }.disabled(model.busy)
                Button(t("Kijelölés törlése", "Clear")) { model.browserSelected = [] }.disabled(model.busy)
                Spacer()
                Button(t("Takarítás…", "Review cleanup…")) { browserReview = model.chosenBrowsers; showBrowserConfirm = true }.buttonStyle(.borderedProminent).disabled(model.busy || model.chosenBrowsers.isEmpty)
            }
            if !model.browserScanned && !model.busy { ContentUnavailableView(t("Böngészőcache vizsgálata", "Scan browser caches"), systemImage: "globe") }
            else {
                List(model.browserScan.items) { item in
                    HStack {
                        Toggle("", isOn: Binding(get: { model.browserSelected.contains(item.id) }, set: { if $0 { model.browserSelected.insert(item.id) } else { model.browserSelected.remove(item.id) } })).labelsHidden().disabled(model.busy || !item.entry.cleanable)
                        VStack(alignment: .leading) { Text(item.browser + " · " + URL(fileURLWithPath: item.id).lastPathComponent).font(.headline); Text(item.id).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled) }
                        Spacer(); Text(size(item.entry.bytes)).monospacedDigit(); if !item.entry.cleanable { Image(systemName: "lock").foregroundStyle(.orange) }
                        Button { reveal(item.id) } label: { Image(systemName: "folder") }.buttonStyle(.borderless)
                    }.padding(.vertical, 4)
                }
            }
            ForEach(Array(model.browserScan.notes.enumerated()), id: \.offset) { note in Text(note.element).font(.caption).foregroundStyle(.orange) }
            Text(t("A Kuka ürítése külön művelet. Safari és egyedi profilútvonalak nem támogatottak.", "Emptying Trash is separate. Safari and custom profile paths are not supported.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var browserConfirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(t("Böngészőcache a Kukába", "Move browser caches to Trash"), systemImage: "trash").font(.title2.bold())
            Text(t("A felsorolt cache-mappák kerülnek a Kukába. Zárd be a böngészőket. A módosult vagy futó böngészőhöz tartozó elemeket a motor elutasítja.", "Listed cache folders move to Trash. Quit browsers. Changed items or running browsers are refused."))
            List(browserReview) { item in HStack { Text(item.id).font(.caption).textSelection(.enabled); Spacer(); Text(size(item.entry.bytes)) } }
            HStack { Button(t("Mégse", "Cancel")) { showBrowserConfirm = false }; Spacer(); Button(t("Áthelyezés a Kukába", "Move to Trash"), role: .destructive) { let items = browserReview; showBrowserConfirm = false; Task { await model.cleanBrowsers(items) } }.buttonStyle(.borderedProminent).tint(.red).disabled(model.busy) }
        }.padding(22).frame(minWidth: 640, minHeight: 350)
    }
    private var leftoverPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Lehetséges maradványok: bundle ID-szerű cache- és naplónevek, amelyek nem szerepelnek a látható alkalmazásleltárban. Ez nem bizonyítja, hogy törölhetők; csak Finderben ellenőrizhetők.", "Possible leftovers: bundle-ID-like cache and log names absent from the visible app inventory. This does not prove they are safe to delete; inspect in Finder.")).foregroundStyle(.secondary)
            HStack { Button { Task { await model.scanLeftovers() } } label: { Label(t("Maradványok keresése", "Find leftovers"), systemImage: "magnifyingglass") }.buttonStyle(.borderedProminent).disabled(model.busy); Spacer(); Text("\(model.leftovers.count)").monospacedDigit() }
            if !model.leftoversScanned && !model.busy { ContentUnavailableView(t("Maradványok felderítése", "Discover leftovers"), systemImage: "shippingbox") }
            else { List(model.leftovers) { item in HStack { Image(systemName: "lock.shield").foregroundStyle(.secondary); VStack(alignment: .leading) { Text(item.bundleID).font(.headline); Text(item.id).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled) }; Spacer(); Text(size(item.entry.bytes)); if !item.entry.complete { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }; Button(t("Finder", "Finder")) { reveal(item.id) }.buttonStyle(.borderless) }.padding(.vertical, 4) } }
        }
    }
    private var dockerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(t("Docker Desktop · lokális build cache", "Docker Desktop · local build cache")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Csak a helyi Docker Desktop socket. A művelet a Docker által kiválasztott régi, lógó build cache-re vonatkozik, nem konténerekre, image-ekre vagy volume-okra. Nem visszavonható, a következő build lassabb lehet.", "Local Docker Desktop socket only. Removes Docker-selected old dangling build cache, not containers, images or volumes. Irreversible; later builds may be slower.")).foregroundStyle(.secondary)
                    HStack {
                        Picker(t("Korhatár", "Age threshold"), selection: $dockerDays) { ForEach([7,14,30], id: \.self) { d in Text("\(d) " + t("nap", "days")).tag(d) } }.frame(maxWidth: 210).disabled(model.busy)
                        Button(t("Tárhelyvizsgálat", "Review storage")) { Task { await model.reviewDocker(dockerDays) } }.buttonStyle(.borderedProminent).disabled(model.busy)
                        Spacer()
                        Button(t("Build cache takarítása…", "Prune build cache…"), role: .destructive) { pendingDockerPlan = model.dockerPlan; showDockerConfirm = true }.disabled(model.busy || model.dockerPlan?.eligible != true || model.dockerPlan?.days != dockerDays)
                    }
                }.padding(5)
            }
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                if let plan = model.dockerPlan { GroupBox(t("Docker teljes tárhelyleltár (nem pontos törlési előnézet)", "Docker disk inventory (not an exact deletion preview)")) { Text(plan.audit.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
                if let result = model.dockerResult { GroupBox(t("Művelet eredménye", "Operation result")) { Text(result.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
            } }
        }
    }
    private var dockerConfirmation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(t("Végleges Docker build cache takarítás", "Irreversible Docker build cache prune"), systemImage: "exclamationmark.triangle").font(.title2.bold()).foregroundStyle(.orange)
            if let plan = pendingDockerPlan {
                Text(t("Korhatár: ", "Age threshold: ") + "\(plan.days) " + t("nap", "days"))
                Text(t("Állítsd le az aktív buildfolyamatokat. A Docker a futtatáskor választja ki a törlendő cache-rekordokat. Nincs pontos dry-run vagy visszaállítás. Nem törlünk volume-ot, image-et vagy konténert.", "Stop active builds. Docker selects cache records at execution time. There is no exact dry-run or recovery. No volume, image or container deletion."))
                HStack { Button(t("Mégse", "Cancel")) { showDockerConfirm = false }; Spacer(); Button(t("Build cache végleges törlése", "Permanently prune build cache"), role: .destructive) { showDockerConfirm = false; Task { await model.pruneDocker(plan) } }.buttonStyle(.borderedProminent).tint(.red).disabled(model.busy) }
            } else { Button(t("Bezárás", "Close")) { showDockerConfirm = false } }
        }.padding(24).frame(width: 560)
    }
    private var brewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("A Homebrew saját karbantartási előnézete. Csomagok és régi telepített verziók tényleges törlése nincs engedélyezve. A meglévő cache-takarítóban a Homebrew kategória külön kijelölhető.", "Homebrew native maintenance preview. Installed packages and old versions cannot be removed here. Select Homebrew in the existing cache cleaner." )).foregroundStyle(.secondary)
            HStack { Button(t("Homebrew előnézet", "Homebrew dry-run")) { Task { await model.previewBrew() } }.buttonStyle(.borderedProminent).disabled(model.busy); Button(t("Homebrew cache kezelése", "Manage Homebrew cache")) { cacheGroup = "brew"; model.page = .clean; Task { await model.scanCaches() } }.disabled(model.busy) }
            if let r = model.brewPreview { ScrollView { GroupBox("brew cleanup --dry-run") { Text(r.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } } }
        }
    }
    private var startup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Látható LaunchAgent és LaunchDaemon plist-ek. A lista nem mutatja biztosan az aktív állapotot vagy az összes modern login itemet. Módosításhoz használd a macOS beállításait; nem törlünk vagy állítunk le szolgáltatásokat.", "Visible LaunchAgent and LaunchDaemon plists. Not a definitive list of active services or modern login items. Use macOS settings to manage them; no service deletion or unloading.")).foregroundStyle(.secondary)
            HStack {
                Button { Task { await model.scanStartup() } } label: { Label(t("Frissítés", "Refresh"), systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent).disabled(model.busy)
                Button(t("Bejelentkezési elemek beállításai", "Login Items settings")) { if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) } }
                TextField(t("Szűrés", "Filter"), text: $query)
            }
            if !model.startupLoaded && !model.busy { ContentUnavailableView(t("Indítási elemek", "Startup items"), systemImage: "power") }
            else { List(model.startupItems.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) || $0.program.localizedCaseInsensitiveContains(query) }) { item in
                HStack { Image(systemName: "gearshape.2").foregroundStyle(Color.accentColor); VStack(alignment: .leading) { Text(item.label).font(.headline); Text(item.program).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled) }; Spacer(); Text(item.scope).font(.caption).foregroundStyle(.secondary); Button { reveal(item.path) } label: { Image(systemName: "folder") }.buttonStyle(.borderless) }.padding(.vertical, 4)
            } }
        }
    }
    private var storage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(t("Áttekintés", "Overview")) { Task { await model.scanStorage() } }.disabled(model.busy)
                Button(t("Mappa elemzése…", "Analyze folder…")) { chooseFolder(large: false) }.disabled(model.busy)
                Button(t("Nagy fájlok / duplikátumok…", "Large files / duplicates…")) { chooseFolder(large: true) }.disabled(model.busy)
                Button("Time Machine") { Task { await model.run(.storage) } }.disabled(model.busy)
            }
            if !model.storageLocation.isEmpty { Text(model.storageLocation).font(.caption).textSelection(.enabled) }
            if !model.storage.entries.isEmpty {
                StorageMap(entries: model.storage.entries, hu: hu, busy: model.busy, open: drill)
            }
            HStack { Text(t("A grafikon a vizsgált fájlok logikai méretét mutatja.", "Chart shows logical sizes of scanned items.")).font(.caption).foregroundStyle(.secondary); Spacer(); Toggle(t("Egyezések csoportosítva", "Group duplicates"), isOn: $storageDuplicatesOnly).toggleStyle(.checkbox) }
            List {
                Section(t("Könyvtárak (read-only)", "Folders (read-only)")) { ForEach(model.storage.entries) { e in HStack { Text(e.path).textSelection(.enabled).lineLimit(1); Spacer(); Text(size(e.bytes)); if !e.complete { Text("Partial").foregroundStyle(.orange) }; Button { drill(e.path) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).disabled(model.busy); Button { reveal(e.path) } label: { Image(systemName: "folder") }.buttonStyle(.borderless) } } }
                if storageDuplicatesOnly {
                    ForEach(duplicateGroups, id: \.key) { group in
                        Section(t("Egyezés", "Match") + " · \(group.value.count) · SHA256 " + String(group.key.prefix(12))) {
                            ForEach(group.value) { e in largeRow(e) }
                        }
                    }
                } else {
                    Section(t("Nagy fájlok", "Large files")) { ForEach(model.large.items) { e in largeRow(e) } }
                }
                ForEach(Array((model.storage.notes + model.large.notes).enumerated()), id: \.offset) { note in Text(note.element).font(.caption).foregroundStyle(.secondary) }
                ForEach(model.commandResults[.storage] ?? []) { r in Text(r.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            }
        }
    }
    private var duplicateGroups: [(key: String, value: [LargeFile])] {
        Dictionary(grouping: model.large.items.filter { $0.duplicate != nil }, by: { $0.duplicate ?? "" }).filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
    }
    private func largeRow(_ e: LargeFile) -> some View {
        HStack { Image(systemName: e.duplicate == nil ? "doc" : "doc.on.doc"); Text(e.path).textSelection(.enabled).lineLimit(1); Spacer(); Text(size(e.bytes)); Button { reveal(e.path) } label: { Image(systemName: "folder") }.buttonStyle(.borderless) }
    }
    private func drill(_ path: String) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { Task { await model.scanStorage(URL(fileURLWithPath: path, isDirectory: true)) } }
        else { reveal(path) }
    }
    private func chooseFolder(large: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { Task { if large { await model.scanLarge(url) } else { await model.scanStorage(url) } } }
    }
    private var security: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Read-only ellenőrzés. Nem változtat rendszerbeállításokat, nem olvas SSH-kulcstartalmat.", "Read-only audit. No security setting changes or SSH private key contents.")).foregroundStyle(.secondary)
            Button(t("Biztonsági audit", "Security audit")) { Task { await model.run(.security) } }.disabled(model.busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ProtectionSummary(results: model.commandResults[.security] ?? [], hu: hu)
                    PermissionsPanel(hu: hu)
                }
            }.frame(maxHeight: 290)
            report(.security, extra: model.securityFiles)
        }
    }
    private var filteredApps: [AppItem] {
        let apps = model.apps.filter { FullUninstaller().visibleLocation(appPath: $0.path, bundleID: $0.bundle) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundle.localizedCaseInsensitiveContains(query)) }
        if appSort == "path" { return apps.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending } }
        return apps
    }
    private var apps: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { Task { await model.loadApps() } } label: { Label(t("Frissítés", "Refresh"), systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent).disabled(model.busy)
                TextField(t("Név vagy bundle ID", "Name or bundle ID"), text: $query)
                Picker(t("Rendezés", "Sort"), selection: $appSort) { Text(t("Név", "Name")).tag("name"); Text(t("Útvonal", "Path")).tag("path") }.frame(maxWidth: 190)
                Text("\(filteredApps.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text(t("Kijelölve: ", "Selected: ") + "\(batchPaths.count) / 20").foregroundStyle(.secondary)
                Button(t("Kijelölés törlése", "Clear selection")) { batchPaths = [] }.disabled(model.busy || batchPaths.isEmpty)
                Spacer()
                Button(t("Kijelöltek áttekintése…", "Review selected…")) {
                    let selected = model.apps.filter { batchPaths.contains($0.path) && FullUninstaller().visibleLocation(appPath: $0.path, bundleID: $0.bundle) }
                    Task { await openFullReview(selected) }
                }.buttonStyle(.borderedProminent).disabled(model.busy || batchPaths.isEmpty)
            }
            if !model.appsLoaded && !model.busy {
                ContentUnavailableView(t("Alkalmazások felderítése", "Discover applications"), systemImage: "square.grid.2x2", description: Text(t("Kattints a Frissítés gombra.", "Click Refresh to scan.")))
            } else {
                List(filteredApps) { a in appRow(a) }
            }
            HStack {
                Text(t("Rendszeralkalmazások elrejtve. Jogosultsági hiba esetén az eltávolító adminisztrátori hitelesítést kér.", "System apps hidden. Permission errors on application bundles trigger administrator authorization.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(t("Alkalmazáskezelési engedély", "App Management permission")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") { NSWorkspace.shared.open(url) }
                }.disabled(model.busy)
            }
        }
        .task { if !model.appsLoaded && !model.busy { await model.loadApps() } }
        .onChange(of: model.apps.map(\.path)) { _, paths in batchPaths.formIntersection(Set(paths)) }
    }
    private func appRow(_ a: AppItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { batchPaths.contains(a.path) }, set: { if $0 { if batchPaths.count < 20 { batchPaths.insert(a.path) } } else { batchPaths.remove(a.path) } })).labelsHidden().disabled(model.busy || (!batchPaths.contains(a.path) && batchPaths.count >= 20))
            Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().aspectRatio(contentMode: .fit).frame(width: 43, height: 43)
            VStack(alignment: .leading, spacing: 4) { Text(a.name).font(.headline); Text(a.bundle + " · " + a.version).font(.caption).foregroundStyle(.secondary).lineLimit(1); Text(a.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            Button { Task { await openFullReview([a]) } } label: { Label(t("Áttekintés / eltávolítás", "Review / uninstall"), systemImage: "trash") }.disabled(model.busy)
            Button { reveal(a.path) } label: { Image(systemName: "folder") }.buttonStyle(.borderless)
        }.padding(.vertical, 4)
    }
    private func openFullReview(_ items: [AppItem]) async {
        batchReviews = await model.reviewFull(items)
        // Exact data is selected for complete uninstall; ambiguous name candidates stay off.
        fullSelected = Set(batchReviews.flatMap { $0.defaultSelection })
        if !batchReviews.isEmpty { showBatch = true }
    }
    private var fullEligible: [FullRemovalReview] { batchReviews.filter { $0.canRemoveApp && fullSelected.contains($0.appPath) } }
    private var fullSelectedBytes: Int64 {
        var seen = Set<String>()
        return batchReviews.flatMap(\.items).filter { fullSelected.contains($0.path) && seen.insert($0.path).inserted }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }
    private func fullItemRow(_ item: FullRemovalItem, blocked: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if item.allowed && !(blocked && [.application, .agent, .machineAgent, .daemon, .helper].contains(item.kind)) {
                Toggle("", isOn: Binding(get: { fullSelected.contains(item.path) }, set: { if $0 { fullSelected.insert(item.path) } else { fullSelected.remove(item.path) } })).labelsHidden()
                    .disabled([.agent, .machineAgent, .daemon, .helper].contains(item.kind))
            } else { Image(systemName: "lock.shield").foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(item.reason).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.bytes.map { size($0) } ?? t("Ismeretlen", "Unknown")).font(.caption).monospacedDigit()
            Button { reveal(item.path) } label: { Image(systemName: "folder") }.buttonStyle(.borderless)
        }.padding(.vertical, 3)
    }
    private var batchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Teljes alkalmazáseltávolítás", "Complete application uninstall")).font(.title.bold())
            Text(t("A program leállítja az alkalmazást és az igazolt szolgáltatásait (szükség esetén kényszerítve). A kijelölt adatok a Kukába, az adminisztrátori tételek védett karanténba kerülnek. Az adatbázisok és beállítások eltűnnek az alkalmazásból.", "The app and verified services are stopped, forcefully if needed. Selected data moves to Trash; administrator items move to protected quarantine. Databases and settings are removed from the app.")).foregroundStyle(.secondary)
            HStack {
                Button(t("Minden ellenőrzött adat kijelölése", "Select all verified data")) {
                    fullSelected = Set(batchReviews.flatMap { $0.defaultSelection })
                }
                Button(t("Csak alkalmazások és szükséges szolgáltatások", "Apps and required agents only")) {
                    fullSelected = Set(batchReviews.filter(\.canRemoveApp).flatMap { $0.items.filter { $0.allowed && [.application, .agent, .machineAgent, .daemon, .helper].contains($0.kind) }.map(\.path) })
                }
                Spacer(); Text(t("Kijelölt tételek: ", "Selected size: ") + size(fullSelectedBytes)).monospacedDigit()
            }
            List {
                ForEach(batchReviews, id: \.appPath) { review in
                    Section {
                        if !review.blockers.isEmpty {
                            ForEach(review.blockers, id: \.self) { reason in Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                            Text(t("Az ellenőrzött tételek eltávolíthatók. A nem igazolható szolgáltatások nem blokkolják a teljes műveletet; a megmaradt elemeket a jelentés felsorolja.", "Verified items can be removed. Unverified services do not block the whole operation; remaining items are reported.")).font(.caption).foregroundStyle(.secondary)
                            Button(t("Alkalmazás megjelenítése Finderben", "Reveal app in Finder")) { reveal(review.appPath) }.buttonStyle(.borderless)
                        }
                        ForEach(review.items) { item in fullItemRow(item, blocked: !review.canRemoveApp) }
                    } header: { Text(URL(fileURLWithPath: review.appPath).lastPathComponent).font(.headline) }
                }
            }
            Text(t("Az Eltávolítás gombbal jóváhagyod a kényszerített leállítást és a kijelölt adatok eltávolítását is.", "The Uninstall button confirms forced termination if needed and removal of selected data.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(t("Mégse", "Cancel")) { showBatch = false }
                Spacer()
                Button(t("Eltávolítás", "Uninstall") + " (\(fullEligible.count))", role: .destructive) {
                    let approved = fullEligible; let selected = fullSelected; showBatch = false; batchPaths = []
                    Task { await model.removeFull(approved, selected: selected) }
                }.buttonStyle(.borderedProminent).tint(.red).disabled(model.busy || fullEligible.isEmpty)
            }
        }.padding(22).frame(minWidth: 800, minHeight: 540)
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(t("A műveletek lokális naplója. Az ellenőrzött fejlesztői cache-ek és új karanténtételek itt visszaállíthatók; más Kukába helyezett elemekhez használd a Findert.", "Local operation log. Verified developer caches and new quarantine items can be restored here; use Finder for other Trash items.")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(t("Kuka megnyitása", "Open Trash")) { NSWorkspace.shared.open(LocalAudit.home.appendingPathComponent(".Trash")) } }
            List(model.history) { h in HStack { Image(systemName: h.event.contains("refused") ? "exclamationmark.triangle" : h.event.contains("Trash") ? "trash" : "clock").foregroundStyle(.secondary); VStack(alignment: .leading) { Text(h.event).fontWeight(.medium); Text(h.detail).foregroundStyle(.secondary).textSelection(.enabled) }; Spacer(); Text(h.date.formatted()).font(.caption); if h.recovery != nil { Button(t("Visszaállítás…", "Restore…")) { pendingRecovery = h; showRecovery = true }.disabled(model.busy) }; if h.privilegedTarget != nil { Button(t("Karantén visszaállítása…", "Restore quarantine…")) { pendingRecovery = h; showPrivilegedRecovery = true }.disabled(model.busy) } } }
        }
    }
    private var settings: some View {
        Form { Toggle(t("Magyar felület", "Hungarian interface"), isOn: $hu); Toggle(t("Menüsor ikon", "Menu bar icon"), isOn: $menuBar); Toggle(t("Óránkénti rendszerellenőrzés nyitott ablaknál", "Hourly read-only audit while window is open"), isOn: $schedule)
            Text(t("Nincs saját állandó háttérdaemon vagy telemetria. Az internetes frissítés opcionális. Adminisztrátori műveleteknél natív hitelesítés szükséges. A diagnosztikai parancsok kimenete angol lehet.", "No persistent background daemon or telemetry. Online updates are optional. Administrator operations require native authorization. Diagnostic command output may be English."))
            Button(t("Jogosultságok beállítása", "Permission setup")) { showPermissionSetup = true }.disabled(model.busy)
            Button(t("Frissítési beállítások", "Update settings")) { model.page = .updates }
            Text("MacMaintenance " + updates.installed + " · ARM64").foregroundStyle(.secondary)
            Text("Copyright © 2026 Zoltán Horváth · GPL-3.0-only").font(.caption)
            Text(t("A program garancia nélkül, a GPLv3 feltételei szerint terjeszthető.", "This software comes without warranty and may be redistributed under GPLv3.")).font(.caption)
            Button(t("Licenc megnyitása", "Open license")) { if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") { NSWorkspace.shared.open(url) } }
            Text(Bundle.main.bundleURL.path).font(.caption.monospaced()).textSelection(.enabled)
            Button(t("Futó alkalmazás megjelenítése Finderben", "Reveal running app in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
        }.formStyle(.grouped)
    }
    private func report(_ p: Page, extra: String = "") -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            ForEach(model.commandResults[p] ?? []) { r in
                GroupBox { Text(r.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } label: { HStack { Text(r.title); Spacer(); Text(r.status.map { "exit \($0)" } ?? "Unavailable / timeout").font(.caption).foregroundStyle(.secondary) } }
            }
            if !extra.isEmpty { GroupBox("SSH / Launch items (metadata only)") { Text(extra).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
        } }
    }
}
#else
import Foundation
@main struct MacMaintenanceApp { static func main() { print("MacMaintenance UI requires macOS.") } }
#endif
