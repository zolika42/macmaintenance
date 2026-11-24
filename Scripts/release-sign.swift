import Foundation
import CryptoKit

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }
let args = CommandLine.arguments
// Invoked with a private key path outside the repository. Never print the private key.
guard args.count >= 4 else { fail("Usage: keygen KEY PUBLIC or sign KEY DMG MANIFEST") }
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
    default: fail("Unknown action")
    }
} catch { fail(error.localizedDescription) }
