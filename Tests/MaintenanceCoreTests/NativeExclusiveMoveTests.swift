#if os(macOS)
import Darwin
import Foundation
import XCTest
@testable import MaintenanceCore

final class NativeExclusiveMoveTests: XCTestCase {
    private func fixture(_ run: (URL, URL, UInt64, UInt64) throws -> Void) throws {
        let fm = FileManager.default
        let ptr = try XCTUnwrap(realpath(fm.temporaryDirectory.path, nil))
        defer { free(ptr) }
        let root = URL(fileURLWithPath: String(cString: ptr)).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try Data("original".utf8).write(to: source)
        let a = try fm.attributesOfItem(atPath: source.path)
        try run(root, source, try XCTUnwrap(a[.systemNumber] as? NSNumber).uint64Value,
                try XCTUnwrap(a[.systemFileNumber] as? NSNumber).uint64Value)
    }
    func testMoveAndIdentity() throws {
        try fixture { root, source, device, inode in
            let destination = root.appendingPathComponent("destination")
            XCTAssertThrowsError(try NativeExclusiveMove.move(source: source.path, destination: destination.path, device: device, inode: inode ^ 1))
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            try NativeExclusiveMove.move(source: source.path, destination: destination.path, device: device, inode: inode)
            XCTAssertEqual(try Data(contentsOf: destination), Data("original".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? NSNumber)?.uint64Value, inode)
        }
    }
    func testFileDirectoryAndDanglingLinkCollisions() throws {
        try fixture { root, source, device, inode in
            let fm = FileManager.default
            let file = root.appendingPathComponent("file"), directory = root.appendingPathComponent("directory"), link = root.appendingPathComponent("link")
            try Data("preserve".utf8).write(to: file)
            try fm.createDirectory(at: directory, withIntermediateDirectories: false)
            try fm.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("missing"))
            for destination in [file, directory, link] {
                XCTAssertThrowsError(try NativeExclusiveMove.move(source: source.path, destination: destination.path, device: device, inode: inode))
                XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
            }
            XCTAssertEqual(try Data(contentsOf: file), Data("preserve".utf8))
            XCTAssertTrue(try fm.contentsOfDirectory(atPath: directory.path).isEmpty)
            XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link.path), root.appendingPathComponent("missing").path)
        }
    }
    func testSymlinkAncestorAndSourceRefused() throws {
        try fixture { root, source, device, inode in
            let fm = FileManager.default
            let alias = root.appendingPathComponent("alias")
            try fm.createSymbolicLink(at: alias, withDestinationURL: root)
            XCTAssertThrowsError(try NativeExclusiveMove.move(source: source.path, destination: alias.appendingPathComponent("destination").path, device: device, inode: inode))
            XCTAssertThrowsError(try NativeExclusiveMove.move(source: alias.appendingPathComponent("source").path, destination: root.appendingPathComponent("destination").path, device: device, inode: inode))
            let link = root.appendingPathComponent("source-link")
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            XCTAssertThrowsError(try NativeExclusiveMove.move(source: link.path, destination: root.appendingPathComponent("destination").path, device: device, inode: inode))
            XCTAssertTrue(fm.fileExists(atPath: source.path))
        }
    }
}
#endif
