import Foundation
import CryptoKit

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }
let args = CommandLine.arguments
// Invoked with a private key path outside the repository. Never print the private key.
guard args.count >= 4 else { fail("Usage: keygen KEY PUBLIC, sign KEY DMG MANIFEST, or verify PUBLIC DMG MANIFEST") }
let keyURL = URL(fileURLWithPath: args[2])
func readKey() throws -> Curve25519.Signing.PrivateKey {
    let a = try FileManager.default.attributesOfItem(atPath: keyURL.path)
    guard a[.type] as? FileAttributeType == .typeRegular, (a[.posixPermissions] as? NSNumber)?.intValue == 0o600 else { fail("Private key must be a regular file with mode 0600") }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
}
do {
    switch args[1] {
    case "keygen":
        guard args.count == 4 else { fail("Bad keygen arguments") }
        if !FileManager.default.fileExists(atPath: keyURL.path) {
            let key = Curve25519.Signing.PrivateKey()
            try key.rawRepresentation.write(to: keyURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        }
        let key = try readKey()
        try (key.publicKey.rawRepresentation.base64EncodedString() + "\n").write(toFile: args[3], atomically: true, encoding: .utf8)
    case "sign":
        guard args.count == 5 else { fail("Bad sign arguments") }
        let key = try readKey(), dmg = URL(fileURLWithPath: args[3]), name = dmg.lastPathComponent
        let prefix = "MacMaintenance-", suffix = "-arm64.dmg"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { fail("Unexpected DMG name") }
        let version = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.utf8.allSatisfy { (48...57).contains($0) } && ($0.count == 1 || $0.first != "0") }) else { fail("Bad release version") }
        let attrs = try dmg.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard attrs.isRegularFile == true, attrs.isSymbolicLink == false, let size = attrs.fileSize, size > 0, size <= 32*1024*1024 else { fail("Unsupported DMG size/type") }
        let data = try Data(contentsOf: dmg); guard data.count == size else { fail("DMG changed") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let payload = try JSONSerialization.data(withJSONObject: ["version":version,"filename":name,"sha256":digest,"size":size], options: [.sortedKeys])
        let sig = try key.signature(for: payload)
        let manifest = try JSONSerialization.data(withJSONObject: ["payload":payload.base64EncodedString(),"signature":sig.base64EncodedString()], options: [.prettyPrinted,.sortedKeys])
        try manifest.write(to: URL(fileURLWithPath: args[4]), options: .atomic)
    case "verify":
        guard args.count == 5 else { fail("Bad verify arguments") }
        struct Envelope: Decodable { let payload: String; let signature: String }
        struct Payload: Decodable { let version: String; let filename: String; let size: Int; let sha256: String }
        let publicText = try String(contentsOf: keyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let publicData = Data(base64Encoded: publicText), publicData.count == 32 else { fail("Invalid public key") }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
        let manifestURL = URL(fileURLWithPath: args[4])
        let manifestAttributes = try manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard manifestAttributes.isRegularFile == true, manifestAttributes.isSymbolicLink == false,
              let manifestSize = manifestAttributes.fileSize, (1...16384).contains(manifestSize) else { fail("Invalid manifest file") }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: manifestURL))
        guard let payload = Data(base64Encoded: envelope.payload), let signature = Data(base64Encoded: envelope.signature),
              signature.count == 64, publicKey.isValidSignature(signature, for: payload) else { fail("Invalid publisher signature") }
        let release = try JSONDecoder().decode(Payload.self, from: payload)
        let dmg = URL(fileURLWithPath: args[3])
        let attrs = try dmg.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        let parts = release.version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.utf8.allSatisfy { (48...57).contains($0) } && ($0.count == 1 || $0.first != "0") }),
              release.filename == "MacMaintenance-\(release.version)-arm64.dmg", release.filename == dmg.lastPathComponent,
              attrs.isRegularFile == true, attrs.isSymbolicLink == false, attrs.fileSize == release.size,
              (1...32*1024*1024).contains(release.size) else { fail("Invalid signed asset metadata") }
        let data = try Data(contentsOf: dmg)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == release.size, digest == release.sha256 else { fail("Signed asset size/hash mismatch") }
        print("=== SIGNED_MANIFEST_AND_PAYLOAD_PASS ===")
    default: fail("Unknown action")
    }
} catch { fail(error.localizedDescription) }
