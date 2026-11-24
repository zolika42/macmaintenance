import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct SignedRelease: Codable, Sendable, Equatable {
    public let version: String, filename: String, sha256: String
    public let size: Int
    public var releaseVersion: ReleaseVersion? { ReleaseVersion(version) }
    public var valid: Bool {
        releaseVersion != nil && filename == "MacMaintenance-\(version)-arm64.dmg" && size > 0 && size <= 32 * 1024 * 1024 && sha256.count == 64 && sha256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    public var downloadURL: URL? { valid ? URL(string: "https://github.com/zolika42/macmaintenance/releases/download/v\(version)/\(filename)") : nil }
}
public struct ReleaseEnvelope: Codable, Sendable {
    public let payload: String, signature: String
}
public enum OnlineUpdates {
    public static let manifestURL = URL(string: "https://github.com/zolika42/macmaintenance/releases/latest/download/release.json")!
    public static func verified(_ data: Data, verify: (Data, Data) -> Bool) -> SignedRelease? {
        guard data.count <= 16384, let envelope = try? JSONDecoder().decode(ReleaseEnvelope.self, from: data), let payload = Data(base64Encoded: envelope.payload), let signature = Data(base64Encoded: envelope.signature), signature.count == 64, verify(payload, signature), let release = try? JSONDecoder().decode(SignedRelease.self, from: payload), release.valid else { return nil }
        return release
    }
    #if canImport(CryptoKit)
    public static func verified(_ data: Data, publicKey: Data) -> SignedRelease? {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return nil }
        return verified(data) { key.isValidSignature($1, for: $0) }
    }
    #endif
    #if os(macOS)
    static func fetch(_ url: URL, maximum: Int) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config); defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let final = http.url, final.scheme == "https", let host = final.host, ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(host), response.expectedContentLength <= Int64(maximum) else { throw URLError(.badServerResponse) }
        var data = Data(); for try await byte in bytes { guard data.count < maximum else { throw URLError(.dataLengthExceedsMaximum) }; data.append(byte) }
        return data
    }
    public static func check(publicKey: Data) async throws -> SignedRelease {
        let data = try await fetch(manifestURL, maximum: 16384)
        guard let release = verified(data, publicKey: publicKey) else { throw URLError(.cannotDecodeContentData) }
        return release
    }
    public static func download(_ release: SignedRelease, publicKey: Data) async throws -> URL {
        // Re-verify the signed feed before fetching any payload; do not execute or mount it.
        guard try await check(publicKey: publicKey) == release, let url = release.downloadURL else { throw URLError(.cannotDecodeContentData) }
        let data = try await fetch(url, maximum: release.size)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == release.size, digest == release.sha256 else { throw URLError(.cannotDecodeContentData) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacMaintenance-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let destination = root.appendingPathComponent(release.filename)
        try data.write(to: destination, options: [.withoutOverwriting])
        return destination
    }
    #endif
}
