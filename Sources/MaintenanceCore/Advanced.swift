import Foundation

public struct BrowserCache: Identifiable, Sendable {
    public var id: String { entry.path }
    public let browser: String
    public let bundleID: String
    public let processPattern: String
    public let entry: Entry
}
public struct BrowserScan: Sendable {
    public var items: [BrowserCache] = []
    public var notes: [String] = []
    public init() {}
}
public struct StartupItem: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let label: String
    public let scope: String
    public let program: String
}
public struct LeftoverCandidate: Identifiable, Sendable {
    public var id: String { entry.path }
    public let bundleID: String
    public let entry: Entry
}
public struct AdvancedCleaner: Sendable {
    let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    private var fm: FileManager { .default }
    private struct Browser: Sendable {
        let name: String; let id: String; let folder: String; let pattern: String
    }
    private var browsers: [Browser] { [
        .init(name: "Chrome", id: "com.google.Chrome", folder: "Google/Chrome", pattern: "Google Chrome"),
        .init(name: "Edge", id: "com.microsoft.edgemac", folder: "Microsoft Edge", pattern: "Microsoft Edge"),
        .init(name: "Brave", id: "com.brave.Browser", folder: "BraveSoftware/Brave-Browser", pattern: "Brave Browser")
    ] }
    private func safeDirectory(_ url: URL) -> Bool {
        Scanner(roots: []).safeAncestors(url) && (try? fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory
    }
    private func directories(_ root: URL) -> [URL] {
        guard safeDirectory(root), let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return children.sorted { $0.path < $1.path }.prefix(100).filter { safeDirectory($0) }
    }
    private func targets() -> [(Browser, URL)] {
        var result: [(Browser, URL)] = []
        for b in browsers {
            for base in ["Library/Caches/", "Library/Application Support/"] {
                let folder = home.appendingPathComponent(base + b.folder)
                for profile in directories(folder) {
                    let name = profile.lastPathComponent
                    guard name == "Default" || name.range(of: #"^Profile [0-9]+$"#, options: .regularExpression) != nil else { continue }
                    for cache in ["Cache", "Code Cache", "GPUCache"] {
                        let target = profile.appendingPathComponent(cache)
                        if safeDirectory(target) { result.append((b, target)) }
                    }
                }
            }
        }
        let firefox = Browser(name: "Firefox", id: "org.mozilla.firefox", folder: "", pattern: "Firefox")
        for profile in directories(home.appendingPathComponent("Library/Caches/Firefox/Profiles")) {
            let target = profile.appendingPathComponent("cache2")
            if safeDirectory(target) { result.append((firefox, target)) }
        }
        return result.sorted { $0.1.path < $1.1.path }
    }
    private func root(for url: URL) -> ScanRoot { .init(url.deletingLastPathComponent().path, "Browser cache", url.deletingLastPathComponent()) }
    public func scanBrowsers(seconds: TimeInterval = 45) -> BrowserScan {
        var result = BrowserScan(); let deadline = Date().addingTimeInterval(seconds)
        for (b, url) in targets() {
            guard !Task.isCancelled, Date() < deadline else { result.notes.append("Partial scan: time limit"); break }
            let r = root(for: url)
            guard let entry = try? Scanner(roots: [r]).inspectChild(url, root: r, seconds: min(10, max(0, deadline.timeIntervalSinceNow))) else { result.notes.append("Skipped unsafe cache: " + url.path); continue }
            result.items.append(.init(browser: b.name, bundleID: b.id, processPattern: b.pattern, entry: entry))
        }
        return result
    }
    private func checkedRoot(_ item: BrowserCache) throws -> ScanRoot {
        guard let (_, url) = targets().first(where: { $0.0.id == item.bundleID && $0.0.pattern == item.processPattern && $0.1.path == item.entry.path }) else { throw ScanError.unsafePath }
        return root(for: url)
    }
    public func validateBrowser(_ item: BrowserCache) throws -> URL {
        let r = try checkedRoot(item)
        return try Scanner(roots: [r]).validate(item.entry)
    }
    public func trashBrowser(_ item: BrowserCache, isRunning: @MainActor @Sendable () -> Bool) async throws -> URL? {
        let r = try checkedRoot(item)
        guard !(await isRunning()) else { throw RemovalError.refused("Quit the browser and its background processes before cleanup.") }
        #if os(macOS)
        let runner = Runner.run(.init("Browser process check", "/usr/bin/pgrep", ["-if", item.processPattern]))
        guard runner.status == 1 else { throw RemovalError.refused("Browser process detected or process check unavailable.") }
        #endif
        return try Scanner(roots: [r]).trash(item.entry)
    }
    // Missing from an app inventory is not proof of abandonment; never grants deletion rights.
    public func leftoverHints(installedIDs: Set<String>, seconds: TimeInterval = 30) -> [LeftoverCandidate] {
        let known = Set(installedIDs.map { $0.lowercased() })
        let root = ScanRoot("leftover-cache", "Cache hints", home.appendingPathComponent("Library/Caches"), cleanable: false)
        let logRoot = ScanRoot("leftover-log", "Log hints", home.appendingPathComponent("Library/Logs"), cleanable: false)
        let scan = Scanner(roots: [root, logRoot]).scan(seconds: seconds)
        return scan.entries.compactMap { entry in
            let id = URL(fileURLWithPath: entry.path).lastPathComponent
            let lower = id.lowercased()
            guard id.range(of: #"^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2,}$"#, options: .regularExpression) != nil,
                  !lower.hasPrefix("com.apple."), lower != "local.macmaintenance.toolkit",
                  !known.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") }) else { return nil }
            return LeftoverCandidate(bundleID: id, entry: entry)
        }.sorted { $0.entry.bytes > $1.entry.bytes }
    }
    public func startupItems(systemFolders: Bool = true) -> [StartupItem] {
        var folders = [(home.appendingPathComponent("Library/LaunchAgents"), "User agent")]
        if systemFolders { folders += [(URL(fileURLWithPath: "/Library/LaunchAgents"), "System-wide agent"), (URL(fileURLWithPath: "/Library/LaunchDaemons"), "System-wide daemon")] }
        var results: [StartupItem] = []
        for (folder, scope) in folders {
            guard safeDirectory(folder), let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for url in files.sorted(by: { $0.path < $1.path }).prefix(500) where url.pathExtension == "plist" {
                guard Scanner(roots: []).safeAncestors(url), let attrs = try? fm.attributesOfItem(atPath: url.path), attrs[.type] as? FileAttributeType == .typeRegular,
                      let length = attrs[.size] as? NSNumber, length.intValue <= 1_000_000,
                      let data = try? Data(contentsOf: url), let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { continue }
                results.append(.init(path: url.path, label: plist["Label"] as? String ?? url.lastPathComponent, scope: scope, program: plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first ?? "—"))
            }
        }
        return results
    }
}

public struct DockerCachePlan: Sendable {
    public let days: Int
    public let audit: CommandResult
    public let eligible: Bool
    public let reviewedAt: Date = Date()
}
public struct DockerCacheManager: Sendable {
    let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    static let executable = "/Applications/Docker.app/Contents/Resources/bin/docker"
    var socket: URL { home.appendingPathComponent(".docker/run/docker.sock") }
    func command(_ title: String, _ arguments: [String]) -> Command { .init(title, Self.executable, ["--host", "unix://" + socket.path] + arguments) }
    func pruneCommand(days: Int) throws -> Command {
        guard [7, 14, 30].contains(days) else { throw ScanError.unsafePath }
        return command("Docker build cache prune", ["builder", "prune", "--filter", "until=\(days * 24)h", "--force"])
    }
    private func localEndpoint() -> Bool {
        let fm = FileManager.default
        guard Scanner(roots: []).safeAncestors(socket),
              (try? fm.attributesOfItem(atPath: socket.path)[.type] as? FileAttributeType) == .typeSocket,
              fm.isExecutableFile(atPath: Self.executable),
              URL(fileURLWithPath: Self.executable).resolvingSymlinksInPath().path.hasPrefix("/Applications/Docker.app/Contents/") else { return false }
        return true
    }
    private func desktopVerified() -> Bool {
        guard localEndpoint() else { return false }
        let result = Runner.run(command("Docker identity", ["info", "--format", "{{.OperatingSystem}}"]), timeout: 12)
        return result.status == 0 && result.output == "Docker Desktop"
    }
    public func review(days: Int) -> DockerCachePlan {
        guard (try? pruneCommand(days: days)) != nil, desktopVerified() else {
            return .init(days: days, audit: .init(title: "Docker Desktop", output: "Verified local Docker Desktop endpoint unavailable.", status: nil), eligible: false)
        }
        let audit = Runner.run(command("Docker disk usage", ["system", "df", "-v"]), timeout: 25)
        return .init(days: days, audit: audit, eligible: audit.status == 0)
    }
    public func prune(_ plan: DockerCachePlan) throws -> CommandResult {
        guard plan.eligible, plan.audit.status == 0, Date().timeIntervalSince(plan.reviewedAt) < 300, desktopVerified() else { throw RemovalError.refused("Local Docker Desktop not verified; scan again.") }
        // Explicit GUI confirmation is required; Docker determines eligible dangling records at execution.
        return Runner.run(try pruneCommand(days: plan.days), timeout: 180)
    }
}
