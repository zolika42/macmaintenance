import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import XCTest
@testable import MaintenanceCore
final class ScannerTests: XCTestCase {
    private func fixture() throws -> URL {
        let temp = FileManager.default.temporaryDirectory.path
        let resolved = try XCTUnwrap(realpath(temp, nil))
        defer { free(resolved) }
        let canonical = try XCTUnwrap(String(validatingCString: resolved))
        let url = URL(fileURLWithPath: canonical, isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    func testScanAndValidate() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("cache"); try Data([1,2,3]).write(to: file)
        let s = Scanner(roots: [.init("test", "test", dir)])
        let e = try XCTUnwrap(s.scan().entries.first); XCTAssertEqual(e.bytes, 3); XCTAssertTrue(e.cleanable)
        XCTAssertEqual(try s.validate(e).path, file.path)
        try Data([1,2,3,4]).write(to: file); XCTAssertThrowsError(try s.validate(e))
    }
    func testSymlinkRejected() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let dest = dir.appendingPathComponent("real"); try Data([1]).write(to: dest)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"), withDestinationURL: dest)
        let s = Scanner(roots: [.init("test", "test", dir)])
        let e = try XCTUnwrap(s.scan().entries.first { $0.path.hasSuffix("/link") }); XCTAssertFalse(e.cleanable); XCTAssertThrowsError(try s.validate(e))
    }
    func testReadOnlyAndForgedPath() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        try Data([1]).write(to: dir.appendingPathComponent("x"))
        let s = Scanner(roots: [.init("test", "test", dir, cleanable: false)])
        let e = try XCTUnwrap(s.scan().entries.first); XCTAssertFalse(e.cleanable); XCTAssertThrowsError(try s.validate(e))
        let other = Scanner(roots: [.init("test", "test", dir)])
        let forged = Entry(rootID: "test", path: dir.deletingLastPathComponent().path, bytes: 0, files: 0, fingerprint: 0, complete: true, cleanable: true)
        XCTAssertThrowsError(try other.validate(forged))
    }
    func testNestedAndPartial() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let nested = dir.appendingPathComponent("group/nested"); try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([1]).write(to: nested.appendingPathComponent("x"))
        let s = Scanner(roots: [.init("parent", "parent", dir), .init("nested", "nested", nested)])
        let entries = s.scan().entries; XCTAssertFalse(try XCTUnwrap(entries.first { $0.rootID == "parent" }).cleanable)
        XCTAssertEqual(entries.filter { $0.rootID == "nested" }.count, 1)
        let partial = Scanner(roots: [.init("parent", "parent", dir)]).scan(maxNodesPerEntry: 1)
        XCTAssertFalse(try XCTUnwrap(partial.entries.first).cleanable)
    }
    func testSymlinkRootAndNestedModification() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real"); try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        let cache = real.appendingPathComponent("cache"); try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
        let file = cache.appendingPathComponent("file"); try Data([1]).write(to: file)
        let link = dir.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertTrue(Scanner(roots: [.init("link", "link", link)]).scan().entries.isEmpty)
        let s = Scanner(roots: [.init("real", "real", real)])
        let e = try XCTUnwrap(s.scan().entries.first); XCTAssertTrue(e.cleanable)
        try Data([1,2,3]).write(to: file); XCTAssertThrowsError(try s.validate(e))
    }
    func testSymlinkAncestorRejected() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real/cache", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data([1]).write(to: real.appendingPathComponent("file"))
        let alias = dir.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real.deletingLastPathComponent())
        let unsafe = alias.appendingPathComponent("cache", isDirectory: true)
        let result = Scanner(roots: [.init("alias", "alias", unsafe)]).scan()
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertFalse(result.notes.isEmpty)
        XCTAssertEqual(Scanner(roots: [.init("real", "real", real)]).scan().entries.count, 1)
    }
    func testTimeout() {
        let r = Runner.run(.init("sleep", "/bin/sleep", ["2"]), timeout: 0.05)
        XCTAssertNil(r.status); XCTAssertTrue(r.output.contains("timeout"))
    }
    func testCommand() {
        let r = Runner.run(.init("test", "/bin/echo", ["hello; not shell"])); XCTAssertEqual(r.status, 0); XCTAssertEqual(r.output, "hello; not shell")
        XCTAssertNil(Runner.run(.init("missing", "/not/installed", [])).status)
    }
}
