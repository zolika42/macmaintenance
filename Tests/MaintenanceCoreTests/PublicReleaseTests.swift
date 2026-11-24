import Foundation
import XCTest
@testable import MaintenanceCore
#if canImport(CryptoKit)
import CryptoKit
#endif
final class PublicReleaseTests: XCTestCase {
    func envelope(version: String = "2.0.0", filename: String = "MacMaintenance-2.0.0-arm64.dmg", size: Int = 10, hash: String = String(repeating: "a", count: 64), signer: (Data) throws -> Data = { _ in Data(repeating: 1, count: 64) }) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: ["version":version,"filename":filename,"size":size,"sha256":hash], options: [.sortedKeys])
        return try JSONSerialization.data(withJSONObject: ["payload":payload.base64EncodedString(),"signature":try signer(payload).base64EncodedString()])
    }
    func testOfficialSourceRepositoryURLs() throws {
        XCTAssertEqual(OnlineUpdates.manifestURL.absoluteString, "https://github.com/zolika42/macmaintenance/releases/latest/download/release.json")
        let release = try XCTUnwrap(OnlineUpdates.verified(try envelope()) { _,_ in true })
        XCTAssertEqual(release.downloadURL?.absoluteString, "https://github.com/zolika42/macmaintenance/releases/download/v2.0.0/MacMaintenance-2.0.0-arm64.dmg")
    }
    func testManifestRejectsMalformedOrUntrusted() throws {
        XCTAssertNotNil(OnlineUpdates.verified(try envelope()) { _,_ in true })
        XCTAssertNil(OnlineUpdates.verified(try envelope()) { _,_ in false })
        for data in [try envelope(version: "02.0.0"), try envelope(filename: "../evil.dmg"), try envelope(size: 0), try envelope(size: 40*1024*1024), try envelope(hash: "bad")] { XCTAssertNil(OnlineUpdates.verified(data) { _,_ in true }) }
        XCTAssertNil(OnlineUpdates.verified(Data(repeating: 0, count: 16385)) { _,_ in true })
    }
    #if canImport(CryptoKit)
    func testRealPublisherSignature() throws {
        let key = Curve25519.Signing.PrivateKey(), other = Curve25519.Signing.PrivateKey()
        let data = try envelope(signer: { try key.signature(for: $0) })
        XCTAssertNotNil(OnlineUpdates.verified(data, publicKey: key.publicKey.rawRepresentation))
        XCTAssertNil(OnlineUpdates.verified(data, publicKey: other.publicKey.rawRepresentation))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        object["payload"] = Data("forged".utf8).base64EncodedString()
        XCTAssertNil(OnlineUpdates.verified(try JSONSerialization.data(withJSONObject: object), publicKey: key.publicKey.rawRepresentation))
    }
    #endif
    func testQuarantineReceiptScope() throws {
        let target = "/private/var/root/MacMaintenance-removed.aBc123XY/item"
        let script = try XCTUnwrap(PrivilegedRecovery.restoreScript(target))
        XCTAssertTrue(script.contains("identity.txt")); XCTAssertTrue(script.contains("/bin/mv -n")); XCTAssertTrue(script.contains("test ! -L \"$dest\"")); XCTAssertFalse(script.contains("launchctl enable"))
        XCTAssertTrue(script.contains("/bin/ls -lde")); XCTAssertTrue(script.contains("0022")); XCTAssertFalse(script.contains("= 80"))
        XCTAssertTrue(script.contains("stat -f '%d:%i:%m:%z' \"$dest\""))
        for path in ["/tmp/item", target + "/child", target.replacingOccurrences(of: "aBc123XY", with: "../root"), target.replacingOccurrences(of: "aBc123XY", with: "1234567")] { XCTAssertNil(PrivilegedRecovery.restoreScript(path)) }
    }
    func testPrivilegedChecksAndExactPlistName() throws {
        XCTAssertEqual(ServiceRemoval.knownPlistLabel("com.piriform.ccleaner.update.plist", bundleID: "com.piriform.ccleaner", folder: "LaunchAgents"), "com.piriform.ccleaner.update")
        XCTAssertNil(ServiceRemoval.knownPlistLabel("com.piriform.ccleaner.update.extra.plist", bundleID: "com.piriform.ccleaner", folder: "LaunchAgents"))
        let script = ServiceRemoval.rootMoveScript(path: "/Library/LaunchDaemons/com.example.app.plist", identity: "1:2:3:4", service: "system/com.example.app", program: nil)
        XCTAssertLessThan(try XCTUnwrap(script.range(of: "Print :Label")).lowerBound, try XCTUnwrap(script.range(of: "launchctl disable")).lowerBound)
        XCTAssertEqual(ServiceRemoval.rootMoveScript(path: "/System/Library/LaunchDaemons/com.apple.test.plist", identity: "1:2:3:4", service: "system/com.apple.test", program: nil), "exit 64")
        XCTAssertEqual(ServiceRemoval.rootMoveScript(path: "/Library/LaunchDaemons/com.example.app.plist", identity: "1:2:3:4", service: "system/org.other.app", program: nil), "exit 64")
        XCTAssertTrue(script.contains("0022")); XCTAssertTrue(script.contains("identity.txt")); XCTAssertTrue(script.contains("stat -f '%d'"))
    }
}
