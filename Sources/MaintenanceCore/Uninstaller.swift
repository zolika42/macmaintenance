import Foundation

public struct RemovalItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable { case application, cache, logs, protectedData }
    public var id: String { path }
    public let path: String
    public let kind: Kind
    public let bytes: Int64
    public let allowed: Bool
    public let complete: Bool
    public let reason: String
    let fingerprint: UInt64
    let files: Int
}
public struct RemovalReview: Sendable {
    public let appPath: String
    public let bundleID: String
    public let items: [RemovalItem]
    public let reason: String?
}
public enum RemovalError: Error, LocalizedError {
    case refused(String)
    public var errorDescription: String? { switch self { case .refused(let reason): reason } }
}
public struct Uninstaller: Sendable {
    private let home: URL
    private let systemApplications: URL
    public init() { home = FileManager.default.homeDirectoryForCurrentUser; systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true) }
    // Internal injection for isolated unit tests only.
    init(home: URL, applications: URL) { self.home = home; self.systemApplications = applications }
    private var userApplications: URL { home.appendingPathComponent("Applications", isDirectory: true) }
    private func root(_ url: URL, cleanable: Bool = true) -> ScanRoot { .init(url.path, url.lastPathComponent, url, cleanable: cleanable) }
    private func validID(_ id: String) -> Bool {
        id.count <= 255 && id.split(separator: ".", omittingEmptySubsequences: false).count >= 2 &&
        id.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 } }
    }
    private func policy(_ path: String, _ id: String) -> String? {
        let lower = id.lowercased()
        guard validID(id), !lower.hasPrefix("com.apple."), lower != "local.macmaintenance.toolkit" else { return "System, self, or invalid bundle identifier." }
        let parent = (path as NSString).deletingLastPathComponent
        guard [systemApplications.path, userApplications.path].contains(parent), path.hasSuffix(".app") else { return "Only direct third-party apps in Applications are eligible." }
        let url = URL(fileURLWithPath: path)
        let r = root(URL(fileURLWithPath: parent, isDirectory: true))
        guard url.path == path, Scanner(roots: [r]).safeAncestors(url),
              (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeDirectory else { return "Unsafe or unavailable app path." }
        let info = url.appendingPathComponent("Contents/Info.plist")
        guard Scanner(roots: [r]).safeAncestors(info),
              let data = try? Data(contentsOf: info),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == id, plist["CFBundlePackageType"] as? String == "APPL" else { return "App identity could not be verified." }
        let vendor = ["com.docker.", "com.adobe.", "com.vmware.", "com.parallels.", "com.microsoft.office", "com.microsoft.teams", "com.microsoft.onedrive", "com.cisco.", "com.sophos.", "com.crowdstrike.", "com.oracle.virtualbox", "com.google.drivefs", "com.dropbox.", "org.virtualbox."]
        if vendor.contains(where: { lower.hasPrefix($0) }) { return "Complex app: use vendor uninstall instructions." }
        if plist["SMPrivilegedExecutables"] != nil || plist["SMLoginItem"] != nil { return "Privileged or background services: use vendor uninstall instructions." }
        let markers = ["Contents/Library/LaunchServices", "Contents/Library/LoginItems", "Contents/Library/LaunchAgents", "Contents/Library/LaunchDaemons", "Contents/Library/SystemExtensions", "Contents/Library/Extensions", "Contents/Library/HelperTools", "Contents/Library/PrivilegedHelperTools"]
        let fm = FileManager.default
        if markers.contains(where: { fm.fileExists(atPath: url.appendingPathComponent($0).path) }) { return "Embedded system or login services: use vendor uninstall instructions." }
        let services = [home.appendingPathComponent("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchDaemons"), URL(fileURLWithPath: "/Library/PrivilegedHelperTools")]
        for folder in services {
            if let names = try? fm.contentsOfDirectory(atPath: folder.path), names.contains(where: { $0 == id || $0.hasPrefix(id + ".") }) { return "Related background service detected: use vendor uninstall instructions." }
        }
        return nil
    }
    private func inspect(_ url: URL, kind: RemovalItem.Kind, permitted: Bool, reason: String, bundleLinks: Bool = false) -> RemovalItem {
        let parent = URL(fileURLWithPath: (url.path as NSString).deletingLastPathComponent, isDirectory: true)
        let r = root(parent, cleanable: permitted)
        let e = try? Scanner(roots: [r]).inspectChild(url, root: r, seconds: kind == .application ? 25 : 3, internalBundleLinks: bundleLinks)
        let complete = e?.complete == true
        return .init(path: url.path, kind: kind, bytes: e?.bytes ?? 0, allowed: permitted && complete, complete: complete, reason: !complete ? "Incomplete or unsafe scan; cannot remove." : reason, fingerprint: e?.fingerprint ?? 0, files: e?.files ?? 0)
    }
    public func review(appPath: String, bundleID: String) -> RemovalReview {
        let refusal = policy(appPath, bundleID)
        guard validID(bundleID) else { return .init(appPath: appPath, bundleID: bundleID, items: [], reason: refusal) }
        let fm = FileManager.default
        var items: [RemovalItem] = []
        if refusal == nil {
            items.append(inspect(URL(fileURLWithPath: appPath), kind: .application, permitted: true, reason: "Application bundle only.", bundleLinks: true))
        }
        let paths: [(String, RemovalItem.Kind)] = [("Caches/\(bundleID)", .cache), ("Logs/\(bundleID)", .logs), ("Preferences/\(bundleID).plist", .protectedData), ("Application Support/\(bundleID)", .protectedData), ("Containers/\(bundleID)", .protectedData), ("Saved Application State/\(bundleID).savedState", .protectedData)]
        for (suffix, kind) in paths {
            let url = home.appendingPathComponent("Library/" + suffix)
            guard fm.fileExists(atPath: url.path) else { continue }
            // Related files are read-only at review; exact cache is eligible only through the separate post-removal opt-in.
            items.append(inspect(url, kind: kind, permitted: false, reason: kind == .cache ? "Protected by default; optional exact cache cleanup after app removal." : "Related files are protected; inspect in Finder."))
        }
        return .init(appPath: appPath, bundleID: bundleID, items: items, reason: refusal)
    }
    public func validate(_ review: RemovalReview) throws -> URL {
        if let reason = policy(review.appPath, review.bundleID) { throw RemovalError.refused(reason) }
        guard let old = review.items.first(where: { $0.kind == .application && $0.path == review.appPath }), old.allowed, old.complete else { throw ScanError.incomplete }
        let current = inspect(URL(fileURLWithPath: review.appPath), kind: .application, permitted: true, reason: "", bundleLinks: true)
        guard current.complete, current.allowed else { throw ScanError.incomplete }
        guard current.fingerprint == old.fingerprint, current.bytes == old.bytes, current.files == old.files else { throw ScanError.changed }
        return URL(fileURLWithPath: review.appPath)
    }
    // Only the exact reviewed bundle-ID cache, after the reviewed app has been moved away.
    // This is a distinct opt-in; never touches preferences, containers or application support.
    private func cacheCandidate(_ review: RemovalReview, installedIDs: Set<String>) throws -> (Scanner, Entry) {
        let fm = FileManager.default
        let lower = review.bundleID.lowercased()
        guard review.reason == nil, validID(review.bundleID), !lower.hasPrefix("com.apple."), lower != "local.macmaintenance.toolkit",
              review.items.contains(where: { $0.kind == .application && $0.allowed && $0.complete && $0.path == review.appPath }),
              !fm.fileExists(atPath: review.appPath),
              !installedIDs.contains(where: { $0.lowercased() == lower }) else { throw RemovalError.refused("App is still installed or cache ownership is not established.") }
        let cacheRoot = home.appendingPathComponent("Library/Caches")
        let expected = cacheRoot.appendingPathComponent(review.bundleID).path
        guard let old = review.items.first(where: { $0.kind == .cache && $0.path == expected && $0.complete }) else { throw ScanError.incomplete }
        let r = root(cacheRoot)
        let scanner = Scanner(roots: [r])
        let entry = Entry(rootID: r.id, path: expected, bytes: old.bytes, files: old.files, fingerprint: old.fingerprint, complete: true, cleanable: true)
        return (scanner, entry)
    }
    public func validateRemovedAppCache(_ review: RemovalReview, installedIDs: Set<String>) throws -> URL {
        let (scanner, entry) = try cacheCandidate(review, installedIDs: installedIDs)
        return try scanner.validate(entry)
    }
    public func trashRemovedAppCache(_ review: RemovalReview, installedIDs: Set<String>, isRunning: @MainActor @Sendable () -> Bool) async throws -> URL? {
        let (scanner, entry) = try cacheCandidate(review, installedIDs: installedIDs)
        guard !(await isRunning()) else { throw RemovalError.refused("Related application is running.") }
        return try scanner.trash(entry)
    }
    // Caller must check running processes immediately before invocation. This operation removes only the bundle.
    public func trash(_ review: RemovalReview, isRunning: @MainActor @Sendable () -> Bool) async throws -> URL? {
        let url = try validate(review)
        #if os(macOS)
        if let reason = policy(review.appPath, review.bundleID) { throw RemovalError.refused(reason) }
        guard !(await isRunning()) else { throw RemovalError.refused("Application is running. Quit it before removal.") }
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
        #else
        _ = url; throw ScanError.unsupported
        #endif
    }
}
