import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum MaintenanceProfile: String, CaseIterable, Sendable {
    case conservative, development, allEligible
    public func selection(_ entries: [Entry]) -> Set<String> {
        let ids: Set<String> = switch self {
        case .conservative: ["npm-logs"]
        case .development: ["npm-logs", "xcode", "brew", "composer", "pip", "yarn", "pnpm"]
        case .allEligible: Set(entries.map(\.rootID))
        }
        return Set(entries.filter { $0.complete && $0.cleanable && ids.contains($0.rootID) }.map(\.id))
    }
}

public struct StorageSegment: Identifiable, Sendable {
    public let entry: Entry
    public var id: String { entry.id }
    public let share: Double
    public static func largest(_ entries: [Entry], limit: Int = 10) -> [Self] {
        let sorted = entries.filter { $0.bytes > 0 }.sorted { $0.bytes == $1.bytes ? $0.path < $1.path : $0.bytes > $1.bytes }
        let sum = sorted.reduce(0.0) { $0 + Double($1.bytes) }
        guard sum > 0 else { return [] }
        return sorted.prefix(max(0, limit)).map { .init(entry: $0, share: Double($0.bytes) / sum) }
    }
}

// Only developer-cache moves made by this app produce receipts. Old free-text history is never trusted.
public struct RecoveryReceipt: Codable, Sendable {
    public let original: Entry
    public let trashed: Entry
    public let device: UInt64
    public let inode: UInt64
}
public struct CacheRecovery: Sendable {
    private let roots: [ScanRoot]
    private let trash: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        roots = Scanner.cacheRoots(home: home); trash = home.appendingPathComponent(".Trash", isDirectory: true)
    }
    init(roots: [ScanRoot], trash: URL) { self.roots = roots; self.trash = trash }
    private var trashRoot: ScanRoot { .init("recovery-trash", "Trash", trash) }
    private func originalURL(_ e: Entry) throws -> URL {
        guard e.cleanable, e.complete, let root = roots.first(where: { $0.id == e.rootID && $0.cleanable }) else { throw ScanError.unsafePath }
        let url = URL(fileURLWithPath: e.path)
        guard url.path == e.path, (e.path as NSString).deletingLastPathComponent == root.url.path,
              !roots.contains(where: { $0.url.path == e.path || $0.url.path.hasPrefix(e.path + "/") }),
              Scanner(roots: roots).safeAncestors(root.url) else { throw ScanError.unsafePath }
        return url
    }
    private func identity(_ url: URL) throws -> (UInt64, UInt64) {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let d = a[.systemNumber] as? NSNumber, let i = a[.systemFileNumber] as? NSNumber else { throw ScanError.unsafePath }
        return (d.uint64Value, i.uint64Value)
    }
    private func vacant(_ url: URL) throws {
        // contentsOfDirectory catches dangling symlinks as well as existing files.
        let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        guard !names.contains(where: { $0.compare(url.lastPathComponent, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame }),
              !FileManager.default.fileExists(atPath: url.path) else { throw ScanError.changed }
    }
    public func capture(original: Entry, destination: URL) throws -> RecoveryReceipt {
        let target = try originalURL(original); try vacant(target)
        let e = try Scanner(roots: [trashRoot]).inspectChild(destination, root: trashRoot)
        guard e.complete, e.bytes == original.bytes, e.files == original.files else { throw ScanError.changed }
        let (device, inode) = try identity(destination)
        guard try identity(target.deletingLastPathComponent()).0 == device else { throw ScanError.unsafePath }
        return .init(original: original, trashed: e, device: device, inode: inode)
    }
    public func validate(_ receipt: RecoveryReceipt) throws -> (source: URL, target: URL) {
        let target = try originalURL(receipt.original); try vacant(target)
        let source = try Scanner(roots: [trashRoot]).validate(receipt.trashed)
        guard receipt.original.bytes == receipt.trashed.bytes, receipt.original.files == receipt.trashed.files else { throw ScanError.changed }
        let (device, inode) = try identity(source)
        guard device == receipt.device, inode == receipt.inode, try identity(target.deletingLastPathComponent()).0 == device else { throw ScanError.changed }
        return (source, target)
    }
    public func restore(_ receipt: RecoveryReceipt) throws {
        let paths = try validate(receipt)
        #if os(macOS)
        // Descriptor-relative exclusive rename; recheck the captured identity.
        try NativeExclusiveMove.move(source: paths.source.path, destination: paths.target.path,
                                     device: receipt.device, inode: receipt.inode)
        #else
        _ = paths; throw ScanError.unsupported
        #endif
    }
}
