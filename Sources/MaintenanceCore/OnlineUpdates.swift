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
#if os(macOS)
private final class ReleaseRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, OnlineUpdates.allowedTransport(url) else { return nil }
        return request
    }
}
#endif

public enum OnlineUpdates {
    static func allowedTransport(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host else { return false }
        return ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(host)
    }
    #if canImport(CryptoKit)
    static func matchesPayload(_ data: Data, release: SignedRelease) -> Bool {
        guard release.valid, data.count == release.size else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == release.sha256
    }
    #endif
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
        try Task.checkCancellation()
        guard allowedTransport(url), maximum > 0, maximum <= 32 * 1024 * 1024 else { throw URLError(.badURL) }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config, delegate: ReleaseRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let final = http.url, allowedTransport(final), response.expectedContentLength <= Int64(maximum) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            if data.count % 65536 == 0 { try Task.checkCancellation() }
            guard data.count < maximum else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try Task.checkCancellation()
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
        guard matchesPayload(data, release: release) else { throw URLError(.cannotDecodeContentData) }
        try Task.checkCancellation()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacMaintenance-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let destination = root.appendingPathComponent(release.filename)
        do {
            try data.write(to: destination, options: [.withoutOverwriting])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            try Task.checkCancellation()
            return destination
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
    #endif
}
