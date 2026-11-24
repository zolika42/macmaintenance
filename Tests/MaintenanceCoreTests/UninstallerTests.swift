import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import XCTest
@testable import MaintenanceCore

final class UninstallerTests: XCTestCase {
    private func fixture() throws -> URL {
        let p = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(p) }
        let root = URL(fileURLWithPath: try XCTUnwrap(String(validatingCString: p)), isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Applications"), withIntermediateDirectories: true)
        return root
    }
    private func makeApp(_ root: URL, name: String = "Example", id: String = "org.example.utility") throws -> URL {
        let app = root.appendingPathComponent("Applications/\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try Data([1,2,3]).write(to: contents.appendingPathComponent("payload"))
        return app
    }
    private func tool(_ root: URL) -> Uninstaller { Uninstaller(home: root, applications: root.appendingPathComponent("Applications", isDirectory: true)) }
    func testValidAppAndProtectedData() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root)
        let data = root.appendingPathComponent("Library/Application Support/org.example.utility", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data([4]).write(to: data.appendingPathComponent("document"))
        let cache = root.appendingPathComponent("Library/Caches/org.example.utility", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let u = tool(root); let review = u.review(appPath: app.path, bundleID: "org.example.utility")
        XCTAssertNil(review.reason); XCTAssertEqual(review.items.filter(\.allowed).count, 1)
        XCTAssertTrue(review.items.contains { $0.kind == .protectedData && !$0.allowed })
        XCTAssertTrue(review.items.contains { $0.kind == .cache && !$0.allowed })
        XCTAssertEqual(try u.validate(review).path, app.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: data.path))
    }
    func testChangedAppRefused() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root); let u = tool(root)
        let review = u.review(appPath: app.path, bundleID: "org.example.utility")
        try Data([1,2,3,4]).write(to: app.appendingPathComponent("Contents/payload"))
        XCTAssertThrowsError(try u.validate(review))
    }
    func testWrongIDSystemSelfAndVendorRefused() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root); let u = tool(root)
        for id in ["org.example.other", "../evil", "com.apple.Safari", "local.macmaintenance.toolkit"] {
            XCTAssertNotNil(u.review(appPath: app.path, bundleID: id).reason)
        }
        let docker = try makeApp(root, name: "Docker", id: "com.docker.docker")
        XCTAssertNotNil(u.review(appPath: docker.path, bundleID: "com.docker.docker").reason)
    }
    func testServiceMarkerRefused() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Library/LoginItems"), withIntermediateDirectories: true)
        XCTAssertNotNil(tool(root).review(appPath: app.path, bundleID: "org.example.utility").reason)
    }
    func testInternalFrameworkLinkAllowedButExternalRefused() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root); let u = tool(root)
        let link = app.appendingPathComponent("Contents/link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "payload")
        let review = u.review(appPath: app.path, bundleID: "org.example.utility")
        XCTAssertTrue(try XCTUnwrap(review.items.first).allowed)
        XCTAssertEqual(try u.validate(review).path, app.path)
        try FileManager.default.removeItem(at: link)
        let outside = root.appendingPathComponent("outside"); try Data([9]).write(to: outside)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../../../outside")
        XCTAssertFalse(try XCTUnwrap(u.review(appPath: app.path, bundleID: "org.example.utility").items.first).allowed)
        XCTAssertThrowsError(try u.validate(review))
    }
    func testOutsideAndSymlinkAppRefused() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root); let u = tool(root)
        let alias = root.appendingPathComponent("Applications/Alias.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: app)
        XCTAssertNotNil(u.review(appPath: alias.path, bundleID: "org.example.utility").reason)
        let moved = root.appendingPathComponent("Other.app"); try FileManager.default.moveItem(at: app, to: moved)
        XCTAssertNotNil(u.review(appPath: moved.path, bundleID: "org.example.utility").reason)
    }
    func testReviewedCacheOnlyAfterRemoval() throws {
        let h = try fixture(); defer { try? FileManager.default.removeItem(at: h) }
        let app = try makeApp(h); let u = tool(h)
        let cache = h.appendingPathComponent("Library/Caches/org.example.utility", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let payload = cache.appendingPathComponent("cache"); try Data([1,2]).write(to: payload)
        let review = u.review(appPath: app.path, bundleID: "org.example.utility")
        XCTAssertThrowsError(try u.validateRemovedAppCache(review, installedIDs: []))
        try FileManager.default.moveItem(at: app, to: h.appendingPathComponent("Removed.app"))
        XCTAssertThrowsError(try u.validateRemovedAppCache(review, installedIDs: ["ORG.EXAMPLE.UTILITY"]))
        XCTAssertEqual(try u.validateRemovedAppCache(review, installedIDs: []).path, cache.path)
        try Data([1,2,3]).write(to: payload)
        XCTAssertThrowsError(try u.validateRemovedAppCache(review, installedIDs: []))
    }
}
