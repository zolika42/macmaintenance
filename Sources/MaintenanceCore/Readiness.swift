import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum ProtectionState: String, Sendable { case enabled, disabled, unknown }
public enum ProtectionCheck: String, CaseIterable, Sendable {
    case fileVault = "FileVault", sip = "SIP", gatekeeper = "Gatekeeper", firewall = "Firewall"
    public func evaluate(output: String, status: Int32?) -> ProtectionState {
        guard status == 0, !output.contains("[output truncated]"), !output.contains("[timeout") else { return .unknown }
        let lines = Set(output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let on: String, off: String
        switch self {
        case .fileVault: on = "filevault is on."; off = "filevault is off."
        case .sip: on = "system integrity protection status: enabled."; off = "system integrity protection status: disabled."
        case .gatekeeper: on = "assessments enabled"; off = "assessments disabled"
        case .firewall: on = "firewall is enabled. (state = 1)"; off = "firewall is disabled. (state = 0)"
        }
        guard lines.contains(on) != lines.contains(off) else { return .unknown }
        // Transitional or custom configurations must not be reported as a clean pass.
        guard !lines.contains(where: { $0.contains("in progress") || $0.contains("custom configuration") || $0.contains("deferred") }) else { return .unknown }
        return lines.contains(on) ? .enabled : .disabled
    }
}
public enum DirectoryAccess: String, Sendable { case accessible, denied, missing, unavailable }
public enum PermissionProbe {
    public static func classify(_ code: Int32) -> DirectoryAccess {
        switch code { case EACCES, EPERM: .denied; case ENOENT: .missing; default: .unavailable }
    }
    // Read-only, no contents or names are read. Not a definitive TCC entitlement check.
    public static func directory(_ url: URL) -> DirectoryAccess {
        guard url.isFileURL else { return .unavailable }
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return classify(errno) }
        _ = close(fd)
        return .accessible
    }
}
public struct FileCandidate: Sendable, Equatable {
    public let url: URL
    public let bytes: Int64
    public init(url: URL, bytes: Int64) { self.url = url; self.bytes = bytes }
}
// Bounded top-N with amortized sorting; keeps deterministic ordering for ties.
public struct LargestCandidates: Sendable {
    private var candidates: [FileCandidate] = []
    private let limit: Int
    public init(limit: Int = 2000) { self.limit = min(10_000, max(1, limit)) }
    private static func ordered(_ a: FileCandidate, _ b: FileCandidate) -> Bool {
        a.bytes == b.bytes ? a.url.path < b.url.path : a.bytes > b.bytes
    }
    public mutating func add(_ value: FileCandidate) {
        guard value.bytes >= 0 else { return }
        candidates.append(value)
        if candidates.count >= limit * 2 {
            candidates.sort(by: Self.ordered)
            candidates.removeLast(candidates.count - limit)
        }
    }
    public var result: [FileCandidate] { Array(candidates.sorted(by: Self.ordered).prefix(limit)) }
}

// Setup completion is a UI milestone, never an authorization decision.
public enum PermissionSetupPolicy {
    public static func needsReview(installedVersion: String, reviewedVersion: String) -> Bool {
        guard ReleaseVersion(installedVersion) != nil else { return true }
        return installedVersion != reviewedVersion
    }
    public static func installedPath(_ path: String, home: String) -> Bool {
        path == "/Applications/MacMaintenance.app" || path == home + "/Applications/MacMaintenance.app"
    }
}
