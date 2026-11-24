import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import MaintenanceCore
final class UXTests: XCTestCase {
    private func entry(_ root: String, _ path: String, _ bytes: Int64, _ complete: Bool = true, _ cleanable: Bool = true) -> Entry {
        .init(rootID: root, path: path, bytes: bytes, files: 1, fingerprint: 1, complete: complete, cleanable: cleanable)
    }
    func testProfileNeverSelectsIncompleteOrProtected() {
        let items = [entry("npm-logs", "/a", 1), entry("xcode", "/b", 2), entry("usercache", "/c", 3, true, false), entry("brew", "/d", 4, false), entry("other", "/e", 5)]
        XCTAssertEqual(MaintenanceProfile.conservative.selection(items), ["/a"])
        XCTAssertEqual(MaintenanceProfile.development.selection(items), ["/a", "/b"])
        XCTAssertEqual(MaintenanceProfile.allEligible.selection(items), ["/a", "/b", "/e"])
    }
    func testStorageShareIncludesHiddenRemainder() {
        let items = [entry("a", "/a", 60), entry("b", "/b", 30), entry("c", "/c", 10), entry("d", "/d", 0)]
        let segments = StorageSegment.largest(items, limit: 2)
        XCTAssertEqual(segments.map(\.id), ["/a", "/b"])
        XCTAssertEqual(segments.reduce(0) { $0 + $1.share }, 0.9, accuracy: 0.00001)
        XCTAssertTrue(StorageSegment.largest([entry("a", "/a", 0)]).isEmpty)
    }
    private func withReceipt(_ work: (CacheRecovery, RecoveryReceipt, URL, URL) throws -> Void) throws {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: raw, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: raw) }
        guard let ptr = realpath(raw.path, nil) else { return XCTFail("realpath failed") }; defer { free(ptr) }
        let canonical = URL(fileURLWithPath: String(cString: ptr))
        let cache = canonical.appendingPathComponent("cache"), trash = canonical.appendingPathComponent("trash")
        try fm.createDirectory(at: cache, withIntermediateDirectories: false); try fm.createDirectory(at: trash, withIntermediateDirectories: false)
        let original = cache.appendingPathComponent("example"), destination = trash.appendingPathComponent("example")
        try Data("test".utf8).write(to: original)
        let roots = [ScanRoot("npm-logs", "npm logs", cache)]
        let e = try XCTUnwrap(Scanner(roots: roots).scan().entries.first)
        try fm.moveItem(at: original, to: destination)
        let recovery = CacheRecovery(roots: roots, trash: trash)
        let receipt = try recovery.capture(original: e, destination: destination)
        try work(recovery, receipt, original, destination)
    }
    func testReceiptRoundTripAndCollision() throws {
        try withReceipt { recovery, receipt, original, destination in
            let decoded = try JSONDecoder().decode(RecoveryReceipt.self, from: JSONEncoder().encode(receipt))
            XCTAssertEqual(try recovery.validate(decoded).source.path, destination.path)
            XCTAssertEqual(try recovery.validate(decoded).target.path, original.path)
            try Data("new".utf8).write(to: original)
            XCTAssertThrowsError(try recovery.validate(decoded))
            XCTAssertEqual(try Data(contentsOf: original), Data("new".utf8))
        }
    }
    func testChangedTrashRefused() throws {
        try withReceipt { recovery, receipt, _, destination in
            try Data("changed".utf8).write(to: destination)
            XCTAssertThrowsError(try recovery.validate(receipt))
        }
    }
    func testDanglingSymlinkCollisionAndForgedRoot() throws {
        try withReceipt { recovery, receipt, original, _ in
            let bad = RecoveryReceipt(original: entry("forged", original.path, receipt.original.bytes), trashed: receipt.trashed, device: receipt.device, inode: receipt.inode)
            XCTAssertThrowsError(try recovery.validate(bad))
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: original.appendingPathExtension("missing"))
            XCTAssertThrowsError(try recovery.validate(receipt))
        }
    }
    #if os(macOS)
    func testNativeExclusiveRestore() throws {
        try withReceipt { recovery, receipt, original, destination in
            try recovery.restore(receipt)
            XCTAssertEqual(try Data(contentsOf: original), Data("test".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertThrowsError(try recovery.restore(receipt))
        }
    }
    #endif
}
