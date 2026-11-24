import Foundation
import XCTest
@testable import MaintenanceCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
final class AdvancedTests: XCTestCase {
    private func fixture() throws -> URL {
        let p = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil)); defer { free(p) }
        let url = URL(fileURLWithPath: try XCTUnwrap(String(validatingCString: p))).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    @discardableResult private func file(_ home: URL, _ path: String) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1,2,3]).write(to: url); return url
    }
    func testBrowserAllowlistAndProtectedProfileData() throws {
        let h = try fixture(); defer { try? FileManager.default.removeItem(at: h) }
        try file(h, "Library/Application Support/Google/Chrome/Default/Cache/entry")
        try file(h, "Library/Application Support/Google/Chrome/Default/Cookies")
        try file(h, "Library/Application Support/Google/Chrome/Default/Login Data")
        try file(h, "Library/Application Support/Google/Chrome/Default/IndexedDB/db")
        try file(h, "Library/Application Support/Google/Chrome/Unrecognized/Cache/entry")
        try file(h, "Library/Caches/Firefox/Profiles/abcd.default/cache2/entry")
        let cleaner = AdvancedCleaner(home: h); let items = cleaner.scanBrowsers().items
        XCTAssertEqual(items.count, 2); XCTAssertTrue(items.allSatisfy { $0.entry.cleanable })
        for item in items { XCTAssertEqual(try cleaner.validateBrowser(item).path, item.entry.path) }
        XCTAssertFalse(items.contains { $0.entry.path.contains("Cookies") || $0.entry.path.contains("IndexedDB") })
    }
    func testBrowserChangedAndSymlinkRefused() throws {
        let h = try fixture(); defer { try? FileManager.default.removeItem(at: h) }
        let fileURL = try file(h, "Library/Application Support/Google/Chrome/Default/Cache/entry")
        let profile = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: profile.appendingPathComponent("GPUCache"), withDestinationURL: h)
        let cleaner = AdvancedCleaner(home: h); let item = try XCTUnwrap(cleaner.scanBrowsers().items.first)
        XCTAssertEqual(cleaner.scanBrowsers().items.count, 1)
        try Data([1,2,3,4]).write(to: fileURL)
        XCTAssertThrowsError(try cleaner.validateBrowser(item))
        let forged = Entry(rootID: item.entry.rootID, path: profile.appendingPathComponent("Cookies").path, bytes: item.entry.bytes, files: item.entry.files, fingerprint: item.entry.fingerprint, complete: true, cleanable: true)
        XCTAssertThrowsError(try cleaner.validateBrowser(.init(browser: item.browser, bundleID: item.bundleID, processPattern: item.processPattern, entry: forged)))
    }
    func testLeftoverHintsNeverCleanable() throws {
        let h = try fixture(); defer { try? FileManager.default.removeItem(at: h) }
        try file(h, "Library/Caches/org.example.removed/file")
        try file(h, "Library/Caches/org.example.installed/file")
        try file(h, "Library/Caches/com.apple.Safari/file")
        try file(h, "Library/Application Support/org.example.removed/document")
        let hints = AdvancedCleaner(home: h).leftoverHints(installedIDs: ["ORG.EXAMPLE.INSTALLED"])
        XCTAssertEqual(hints.map(\.bundleID), ["org.example.removed"]); XCTAssertFalse(try XCTUnwrap(hints.first).entry.cleanable)
    }
    func testStartupInventoryDoesNotFollowLinks() throws {
        let h = try fixture(); defer { try? FileManager.default.removeItem(at: h) }
        let url = try file(h, "Library/LaunchAgents/org.example.job.plist")
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Label": "org.example.job", "ProgramArguments": ["/bin/echo", "secret"]], format: .xml, options: 0)
        try plist.write(to: url)
        try FileManager.default.createSymbolicLink(at: url.deletingLastPathComponent().appendingPathComponent("alias.plist"), withDestinationURL: url)
        let items = AdvancedCleaner(home: h).startupItems(systemFolders: false)
        XCTAssertEqual(items.count, 1); XCTAssertEqual(items.first?.program, "/bin/echo")
    }
    func testDockerCommandOnlyTargetsLocalBuildCache() throws {
        let h = try fixture(); defer { try? FileManager.default.removeItem(at: h) }
        let manager = DockerCacheManager(home: h)
        XCTAssertEqual(try manager.pruneCommand(days: 7).arguments, ["--host", "unix://" + h.appendingPathComponent(".docker/run/docker.sock").path, "builder", "prune", "--filter", "until=168h", "--force"])
        XCTAssertThrowsError(try manager.pruneCommand(days: 0)); XCTAssertFalse(manager.review(days: 7).eligible)
    }
}
