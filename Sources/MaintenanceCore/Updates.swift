import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct ReleaseVersion: Sendable, Comparable, CustomStringConvertible {
    public let major: Int, minor: Int, patch: Int
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.utf8.allSatisfy { (48...57).contains($0) } && ($0.count == 1 || $0.first != "0") }), let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        major = a; minor = b; patch = c
    }
    public var description: String { "\(major).\(minor).\(patch)" }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch) }
}
public struct LocalRelease: Sendable, Equatable {
    public let version: ReleaseVersion
    public let file: URL
    public let digest: String
}
public enum ReleaseCheck: Sendable, Equatable {
    case current, unavailable(String), available(LocalRelease), invalid(String)
}
public enum LocalUpdates {
    private static let prefix = "MacMaintenance-", suffix = "-arm64.dmg"
    public static func version(of filename: String) -> ReleaseVersion? {
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix), filename.count > prefix.count + suffix.count else { return nil }
        return ReleaseVersion(String(filename.dropFirst(prefix.count).dropLast(suffix.count)))
    }
    private static func regular(_ url: URL, max: Int64) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), v.isRegularFile == true, v.isSymbolicLink == false, let size = v.fileSize, size > 0, Int64(size) <= max else { return false }; return true
    }
    public static func digest(from text: String, filename: String) -> String? {
        let line = text.trimmingCharacters(in: .newlines)
        guard !line.contains(where: \.isNewline) else { return nil }
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[0].count == 64, parts[0].utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }), parts[1] == filename || parts[1] == "*" + filename else { return nil }
        return parts[0].lowercased()
    }
    #if canImport(CryptoKit)
    public static func sha256(_ url: URL) -> String? {
        guard regular(url, max: 1_073_741_824), let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var digest = SHA256(); var count: Int64 = 0
        do {
            while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
                count += Int64(data.count)
                guard count <= 1_073_741_824, !Task.isCancelled else { return nil }
                digest.update(data: data)
            }
            return count > 0 ? digest.finalize().map { String(format: "%02x", $0) }.joined() : nil
        } catch { return nil }
    }
    #endif
    public static func check(folder: URL, current: ReleaseVersion, hash: @Sendable (URL) -> String?) -> ReleaseCheck {
        guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink == false else { return .unavailable("Release folder unavailable or symbolic link") }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return .unavailable("Cannot list release folder") }
        let newer = entries.compactMap { url -> (ReleaseVersion, URL)? in guard let v = version(of: url.lastPathComponent), v > current else { return nil }; return (v, url) }.sorted { $0.0 > $1.0 }
        guard let (version, file) = newer.first else { return .current }
        let checksum = file.appendingPathExtension("sha256")
        guard regular(file, max: 1_073_741_824), regular(checksum, max: 4096), let text = try? String(contentsOf: checksum, encoding: .utf8), let expected = digest(from: text, filename: file.lastPathComponent), hash(file)?.lowercased() == expected, regular(file, max: 1_073_741_824) else { return .invalid("Release \(version) has missing/invalid SHA-256 or is not a regular file") }
        return .available(.init(version: version, file: file, digest: expected))
    }
}
