import Foundation
import XCTest
@testable import MaintenanceCore
final class UpdateTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); return root
    }
    private func release(_ version: String, in root: URL) throws -> URL {
        let name = "MacMaintenance-\(version)-arm64.dmg", file = root.appendingPathComponent(name)
        try Data([1,2,3]).write(to: file)
        try (digest + "  " + name + "\n").write(to: file.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
        return file
    }
    func testNumericVersionsAndStrictNames() throws {
        XCTAssertGreaterThan(try XCTUnwrap(ReleaseVersion("0.10.0")), try XCTUnwrap(ReleaseVersion("0.9.9")))
        for value in ["01.0.0", "1.0", "1.0.0-beta", "1.0.-1", "1.0.1000000", "1.0.0\n"] { XCTAssertNil(ReleaseVersion(value)) }
        XCTAssertNil(LocalUpdates.version(of: "MacMaintenance-1.0.0-x86_64.dmg"))
        XCTAssertNil(LocalUpdates.version(of: "MacMaintenance-1.0.0-arm64.dmg.sh"))
    }
    func testNewestAndCurrent() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try release("0.4.0", in: root); let latest = try release("0.10.0", in: root)
        let expected = digest
        let state = LocalUpdates.check(folder: root, current: ReleaseVersion("0.3.0")!, hash: { _ in expected })
        guard case .available(let found) = state else { return XCTFail("Expected available: \(state)") }
        let actual = try FileManager.default.attributesOfItem(atPath: found.file.path)
        let wanted = try FileManager.default.attributesOfItem(atPath: latest.path)
        XCTAssertEqual(try XCTUnwrap(actual[.systemNumber] as? NSNumber), try XCTUnwrap(wanted[.systemNumber] as? NSNumber))
        XCTAssertEqual(try XCTUnwrap(actual[.systemFileNumber] as? NSNumber), try XCTUnwrap(wanted[.systemFileNumber] as? NSNumber))
        XCTAssertEqual(found.file.lastPathComponent, latest.lastPathComponent)
        XCTAssertEqual(found.version.description, "0.10.0")
        XCTAssertEqual(LocalUpdates.check(folder: root, current: ReleaseVersion("0.10.0")!, hash: { _ in nil }), .current)
    }
    func testMissingChecksumAndMismatchFailClosed() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = try release("0.5.0", in: root), current = ReleaseVersion("0.4.0")!
        guard case .invalid = LocalUpdates.check(folder: root, current: current, hash: { _ in String(repeating: "b", count: 64) }) else { return XCTFail("Mismatch accepted") }
        try FileManager.default.removeItem(at: file.appendingPathExtension("sha256"))
        let expected = digest
        guard case .invalid = LocalUpdates.check(folder: root, current: current, hash: { _ in expected }) else { return XCTFail("Missing checksum accepted") }
        XCTAssertNil(LocalUpdates.digest(from: digest + "  ../other.dmg", filename: file.lastPathComponent))
        XCTAssertNil(LocalUpdates.digest(from: digest + "  " + file.lastPathComponent + "\n" + digest + "  other", filename: file.lastPathComponent))
    }
    func testSymlinkAndUnavailable() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = try release("0.5.0", in: root)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: file.appendingPathExtension("sha256"))
        let expected = digest
        guard case .invalid = LocalUpdates.check(folder: root, current: ReleaseVersion("0.4.0")!, hash: { _ in expected }) else { return XCTFail("Symlink accepted") }
        guard case .unavailable = LocalUpdates.check(folder: root.appendingPathComponent("missing"), current: ReleaseVersion("0.4.0")!, hash: { _ in nil }) else { return XCTFail("Missing folder reported current") }
    }
    #if canImport(CryptoKit)
    func testRealSHA256AndTamperedRelease() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let name = "MacMaintenance-0.5.0-arm64.dmg", file = root.appendingPathComponent(name)
        try Data("abc".utf8).write(to: file)
        let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try (digest + "  " + name + "\n").write(to: file.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
        XCTAssertEqual(LocalUpdates.sha256(file), digest)
        let current = ReleaseVersion("0.4.0")!
        guard case .available = LocalUpdates.check(folder: root, current: current, hash: LocalUpdates.sha256) else { return XCTFail("Valid digest refused") }
        try Data("tampered".utf8).write(to: file)
        guard case .invalid = LocalUpdates.check(folder: root, current: current, hash: LocalUpdates.sha256) else { return XCTFail("Tampered artifact accepted") }
    }
    #endif
}
