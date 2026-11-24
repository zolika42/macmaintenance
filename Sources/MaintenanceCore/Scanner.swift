import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct ScanRoot: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let url: URL
    public let cleanable: Bool
    public init(_ id: String, _ title: String, _ url: URL, cleanable: Bool = true) {
        self.id = id; self.title = title; self.url = url; self.cleanable = cleanable
    }
}
public struct Entry: Sendable, Identifiable, Codable {
    public var id: String { path }
    public let rootID: String
    public let path: String
    public let bytes: Int64
    public let files: Int
    public let fingerprint: UInt64
    public let complete: Bool
    public let cleanable: Bool
}
public struct ScanResult: Sendable {
    public var entries: [Entry] = []
    public var notes: [String] = []
    public init() {}
}
public enum ScanError: Error, LocalizedError {
    case unsafePath, changed, incomplete, unsupported
    public var errorDescription: String? {
        switch self {
        case .unsafePath: "Path is outside the permitted cache boundary or contains a symbolic link."
        case .changed: "Item changed since the scan; scan again."
        case .incomplete: "Incomplete scan; cleanup refused."
        case .unsupported: "Trash is available only on macOS."
        }
    }
}
public struct Scanner: Sendable {
    public let roots: [ScanRoot]
    public init(roots: [ScanRoot]) { self.roots = roots }
    public static func cacheRoots(home: URL) -> [ScanRoot] {
        [ScanRoot("npm-logs", "npm logs", home.appendingPathComponent(".npm/_logs")),
         ScanRoot("xcode", "Xcode DerivedData", home.appendingPathComponent("Library/Developer/Xcode/DerivedData")),
         ScanRoot("brew", "Homebrew cache", home.appendingPathComponent("Library/Caches/Homebrew")),
         ScanRoot("composer", "Composer cache", home.appendingPathComponent("Library/Caches/composer")),
         ScanRoot("pip", "pip cache", home.appendingPathComponent("Library/Caches/pip")),
         ScanRoot("yarn", "Yarn cache", home.appendingPathComponent("Library/Caches/Yarn")),
         ScanRoot("pnpm", "pnpm cache", home.appendingPathComponent("Library/Caches/pnpm")),
         ScanRoot("npm", "npm content cache (inspection only)", home.appendingPathComponent(".npm/_cacache"), cleanable: false),
         ScanRoot("usercache", "Application caches", home.appendingPathComponent("Library/Caches"), cleanable: false),
         ScanRoot("logs", "User logs (inspection only)", home.appendingPathComponent("Library/Logs"), cleanable: false)]
    }
    private func attributes(_ url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }
    func safeAncestors(_ url: URL) -> Bool {
        guard url.isFileURL, url.path.hasPrefix("/"), url.path != "/" else { return false }
        let parts = url.path.split(separator: "/")
        guard !parts.isEmpty, !parts.contains("."), !parts.contains("..") else { return false }
        var path = ""
        for (index, part) in parts.enumerated() {
            path += "/" + part
            guard let a = try? FileManager.default.attributesOfItem(atPath: path),
                  let t = a[.type] as? FileAttributeType,
                  t != .typeSymbolicLink else { return false }
            if index < parts.count - 1 && t != .typeDirectory { return false }
        }
        return true
    }
    private func children(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []).sorted { $0.path < $1.path }
    }
    private func measure(_ url: URL, root: ScanRoot, deadline: Date, limit: Int, excluded: Set<String> = [], internalBundleLinks: Bool = false, opaqueBundleLinks: Bool = false) -> Entry {
        var stack = [url], count = 0, bytes: Int64 = 0, hash: UInt64 = 14695981039346656037
        var complete = true
        let rootDevice = (try? attributes(root.url)[.systemNumber] as? NSNumber)?.uint64Value
        func mix(_ s: String) { for b in s.utf8 { hash = (hash ^ UInt64(b)) &* 1099511628211 } }
        while let item = stack.popLast() {
            if Task.isCancelled || Date() >= deadline || count >= limit { complete = false; break }
            if excluded.contains(item.path) { continue }
            do {
                let a = try attributes(item)
                guard let type = a[.type] as? FileAttributeType else { complete = false; continue }
                count += 1
                let size = (a[.size] as? NSNumber)?.int64Value ?? 0
                let inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
                let dev = (a[.systemNumber] as? NSNumber)?.uint64Value ?? 0
                if rootDevice == nil || dev != rootDevice { complete = false; continue }
                let mtime = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                mix("\(item.path)\u{0}\(type.rawValue)\u{0}\(size)\u{0}\(dev)\u{0}\(inode)\u{0}\(mtime)\u{0}")
                if type == .typeDirectory {
                    guard safeAncestors(item) else { complete = false; continue }
                    stack.append(contentsOf: try children(item).reversed())
                }
                else if type == .typeRegular { bytes += max(0, size) }
                else if type == .typeSymbolicLink && opaqueBundleLinks {
                    // Moving a whole app bundle does not traverse any nested symlink.
                    // Record the link itself, not the file it points to.
                    mix(try FileManager.default.destinationOfSymbolicLink(atPath: item.path))
                }
                else if type == .typeSymbolicLink && internalBundleLinks {
                    // Only internal bundle links, never traversed. Cache mode remains strict.
                    let target = try FileManager.default.destinationOfSymbolicLink(atPath: item.path)
                    guard !target.hasPrefix("/"), let pointer = realpath(item.path, nil) else { complete = false; continue }
                    defer { free(pointer) }
                    guard let resolved = String(validatingCString: pointer), resolved.hasPrefix(url.path + "/") else { complete = false; continue }
                    mix(target)
                } else { complete = false } // Never traverse links or special files.
            } catch { complete = false }
        }
        return Entry(rootID: root.id, path: url.path, bytes: bytes, files: count, fingerprint: hash, complete: complete, cleanable: root.cleanable && complete)
    }
    public func scan(seconds: TimeInterval = 25, maxEntriesPerRoot: Int = 400, maxNodesPerEntry: Int = 100_000) -> ScanResult {
        var result = ScanResult()
        let deadline = Date().addingTimeInterval(seconds)
        let rootPaths = Set(roots.map { $0.url.path })
        for root in roots {
            if Task.isCancelled || Date() >= deadline { result.notes.append("Time limit reached; remaining roots not scanned."); break }
            guard FileManager.default.fileExists(atPath: root.url.path) else { continue }
            guard safeAncestors(root.url), (try? attributes(root.url)[.type] as? FileAttributeType) == .typeDirectory else { result.notes.append("Skipped unsafe/inaccessible root: \(root.url.path)"); continue }
            do {
                let items = try children(root.url)
                if items.count > maxEntriesPerRoot { result.notes.append("Entry limit: \(root.title)") }
                for item in items.prefix(maxEntriesPerRoot) {
                    if Task.isCancelled || Date() >= deadline { result.notes.append("Partial root: \(root.title)"); break }
                    // A nested configured root owns its own results. Never approve a parent containing another root.
                    if rootPaths.contains(item.path) { continue }
                    let nested = rootPaths.filter { $0.hasPrefix(item.path + "/") }
                    let entry = measure(item, root: root, deadline: deadline, limit: maxNodesPerEntry, excluded: Set(nested))
                    if nested.isEmpty { result.entries.append(entry) }
                    else { result.entries.append(Entry(rootID: entry.rootID, path: entry.path, bytes: entry.bytes, files: entry.files, fingerprint: entry.fingerprint, complete: entry.complete, cleanable: false)) }
                }
            } catch { result.notes.append("Cannot read \(root.url.path): \(error.localizedDescription)") }
        }
        return result
    }
    // Exact immediate child only; avoids scanning unrelated sibling applications.
    func inspectChild(_ url: URL, root: ScanRoot, seconds: TimeInterval = 20,
                      internalBundleLinks: Bool = false, opaqueBundleLinks: Bool = false) throws -> Entry {
        guard roots.count == 1, roots.first?.id == root.id,
              (url.path as NSString).deletingLastPathComponent == root.url.path,
              safeAncestors(url) else { throw ScanError.unsafePath }
        return measure(url, root: root, deadline: Date().addingTimeInterval(seconds),
                       limit: 100_000, internalBundleLinks: internalBundleLinks, opaqueBundleLinks: opaqueBundleLinks)
    }
    public func validate(_ entry: Entry, seconds: TimeInterval = 15) throws -> URL {
        guard entry.complete, entry.cleanable else { throw ScanError.incomplete }
        guard let root = roots.first(where: { $0.id == entry.rootID && $0.cleanable }) else { throw ScanError.unsafePath }
        let url = URL(fileURLWithPath: entry.path)
        guard url.path == entry.path, (entry.path as NSString).deletingLastPathComponent == root.url.path,
              !roots.contains(where: { $0.url.path == url.path || $0.url.path.hasPrefix(url.path + "/") }), safeAncestors(url) else { throw ScanError.unsafePath }
        let fresh = measure(url, root: root, deadline: Date().addingTimeInterval(seconds), limit: 100_000)
        guard fresh.complete else { throw ScanError.incomplete }
        guard fresh.fingerprint == entry.fingerprint, fresh.bytes == entry.bytes, fresh.files == entry.files else { throw ScanError.changed }
        return url
    }
    @discardableResult public func trash(_ entry: Entry) throws -> URL? {
        let url = try validate(entry)
        #if os(macOS)
        // Recheck immediately before moving. This is not an atomic filesystem snapshot.
        guard safeAncestors(url) else { throw ScanError.unsafePath }
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
        #else
        _ = url
        throw ScanError.unsupported
        #endif
    }
}
