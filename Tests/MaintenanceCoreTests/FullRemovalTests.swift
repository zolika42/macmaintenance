import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import XCTest
@testable import MaintenanceCore

final class FullRemovalTests: XCTestCase {
    private let id = "org.example.cleaner"
    private func fixture() throws -> URL {
        let ptr = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil)); defer { free(ptr) }
        let root = URL(fileURLWithPath: String(cString: ptr)).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Applications"), withIntermediateDirectories: true)
        return root
    }
    private func put(_ root: URL, _ path: String, _ data: Data = Data([1, 2, 3])) throws -> URL {
        let u = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u); return u
    }
    private func plist(_ p: [String: Any]) throws -> Data { try PropertyListSerialization.data(fromPropertyList: p, format: .xml, options: 0) }
    private func app(_ r: URL, _ id: String? = nil) throws -> URL {
        _ = try put(r, "Applications/Cleaner.app/Contents/Info.plist", plist(["CFBundleIdentifier": id ?? self.id, "CFBundlePackageType": "APPL"]))
        _ = try put(r, "Applications/Cleaner.app/Contents/MacOS/Cleaner")
        return r.appendingPathComponent("Applications/Cleaner.app")
    }
    private func tool(_ r: URL) -> FullUninstaller { .init(home: r, applications: r.appendingPathComponent("Applications"), systemLibrary: r.appendingPathComponent("MachineLibrary")) }
    func testFullDataAndDatabaseReview() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let db = try put(r, "Library/Application Support/\(id)/data.sqlite")
        let pref = try put(r, "Library/Preferences/\(id).plist")
        let named = try put(r, "Library/Application Support/Cleaner/database.sqlite")
        _ = try put(r, "Library/Application Support/\(id).other/data.sqlite")
        let review = u.review(appPath: a.path, bundleID: id)
        XCTAssertTrue(review.canRemoveApp)
        XCTAssertTrue(review.items.contains { $0.path == db.deletingLastPathComponent().path && $0.kind == .data && $0.allowed })
        XCTAssertTrue(review.items.contains { $0.path == pref.path && $0.allowed })
        XCTAssertTrue(review.items.contains { $0.path == named.deletingLastPathComponent().path && $0.kind == .candidate })
        XCTAssertFalse(review.items.contains { $0.path.contains(".other") })
        let selected = Set(review.items.filter(\.allowed).map(\.path))
        XCTAssertEqual(try u.validate(review, selected: selected, otherIDs: []).count, selected.count)
        XCTAssertThrowsError(try u.validate(review, selected: selected, otherIDs: [id.uppercased()]))
        try Data([9,8,7,6]).write(to: db)
        XCTAssertThrowsError(try u.validate(review, selected: selected, otherIDs: []))
    }
    func testKnownVendorNamesDoNotAuthorizeUnverifiedJobs() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let id = "com.piriform.ccleaner", a = try app(r, id)
        let label = "com.piriform.ccleaner.update"
        let agent = try put(r, "Library/LaunchAgents/\(label).plist", try plist(["Label": label, "Program": "/bin/sh"]))
        let review = tool(r).review(appPath: a.path, bundleID: id)
        XCTAssertTrue(review.items.contains { $0.path == agent.path && $0.kind == .manual && !$0.allowed })
        XCTAssertFalse(review.defaultSelection.contains(agent.path))
    }
    func testVendorNameAloneDoesNotBlock() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let vendorID = "com.docker.example"
        let a = try app(r, vendorID)
        XCTAssertTrue(tool(r).review(appPath: a.path, bundleID: vendorID).canRemoveApp)
    }
    func testSystemAndSelfHidden() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        XCTAssertTrue(u.visible(appPath: a.path, bundleID: id))
        XCTAssertFalse(u.visible(appPath: a.path, bundleID: "com.apple.Safari"))
        XCTAssertFalse(u.visible(appPath: a.path, bundleID: "local.macmaintenance.toolkit"))
        XCTAssertFalse(u.visible(appPath: "/System/Applications/Test.app", bundleID: id))
        XCTAssertFalse(u.visible(appPath: a.path, bundleID: "../evil"))
    }
    func testVerifiedUserAgentAndUnverifiedSystemWarning() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let label = id + ".agent"
        let data = try plist(["Label": label, "ProgramArguments": [a.path + "/Contents/MacOS/Cleaner"]])
        let agent = try put(r, "Library/LaunchAgents/\(label).plist", data)
        let review = u.review(appPath: a.path, bundleID: id)
        XCTAssertTrue(review.canRemoveApp)
        XCTAssertTrue(review.items.contains { $0.kind == .agent && $0.allowed && $0.path == agent.path })
        XCTAssertThrowsError(try u.validate(review, selected: [a.path], otherIDs: []))
        XCTAssertEqual(try u.validate(review, selected: [a.path, agent.path], otherIDs: []).count, 2)
        _ = try put(r, "MachineLibrary/LaunchDaemons/\(label).plist", data)
        let blocked = u.review(appPath: a.path, bundleID: id)
        XCTAssertTrue(blocked.canRemoveApp)
        XCTAssertFalse(blocked.blockers.isEmpty)
        XCTAssertTrue(blocked.items.contains { $0.kind == .manual && !$0.allowed })
        XCTAssertEqual(try u.validate(blocked, selected: [a.path, agent.path], otherIDs: []).count, 2)
    }
    func testLeftoversGuardAndSharedData() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let db = try put(r, "Library/Application Support/\(id)/db")
        _ = try put(r, "Library/Group Containers/group.\(id)/db")
        _ = try put(r, "MachineLibrary/LaunchDaemons/\(id).plist", try plist(["Label": id]))
        let review = u.review(appPath: a.path, bundleID: id), path = db.deletingLastPathComponent().path
        XCTAssertTrue(review.canRemoveApp)
        XCTAssertFalse(review.blockers.isEmpty)
        XCTAssertTrue(review.defaultSelection.contains(a.path))
        XCTAssertTrue(review.defaultSelection.contains(path))
        XCTAssertEqual(try u.validate(review, selected: review.defaultSelection, otherIDs: []).count, 2)
        XCTAssertTrue(review.items.contains { $0.path.contains("Group Containers") && !$0.allowed })
        XCTAssertThrowsError(try u.validate(review, selected: [path], otherIDs: [], dataOnly: true))
        try FileManager.default.removeItem(at: a)
        XCTAssertThrowsError(try u.validate(review, selected: [path], otherIDs: [], dataOnly: true))
        try FileManager.default.removeItem(at: r.appendingPathComponent("MachineLibrary/LaunchDaemons/\(id).plist"))
        XCTAssertEqual(try u.validate(review, selected: [path], otherIDs: [], dataOnly: true).count, 1)
    }
    func testDirectServiceAndOneClickSelection() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let label = "org.example.different.agent"
        let agent = try put(r, "Library/LaunchAgents/\(label).plist", try plist(["Label": label, "Program": a.path + "/Contents/MacOS/Cleaner"]))
        let unknown = try put(r, "MachineLibrary/LaunchDaemons/\(id).plist", try plist(["Label": id, "Program": "/bin/sh"]))
        let review = u.review(appPath: a.path, bundleID: id)
        XCTAssertTrue(review.canRemoveApp)
        XCTAssertTrue(review.defaultSelection.contains(a.path))
        XCTAssertTrue(review.defaultSelection.contains(agent.path))
        XCTAssertFalse(review.defaultSelection.contains(unknown.path))
        XCTAssertEqual(review.requiredServices, [agent.path])
        XCTAssertEqual(try u.validate(review, selected: review.defaultSelection, otherIDs: []).count, 2)
        XCTAssertThrowsError(try u.validate(review, selected: review.defaultSelection.union([unknown.path]), otherIDs: []))
    }
    func testAppNestedExternalLinkDoesNotFollowTarget() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let outside = try put(r, "outside/db")
        try FileManager.default.createSymbolicLink(at: a.appendingPathComponent("Contents/link"), withDestinationURL: outside)
        let review = u.review(appPath: a.path, bundleID: id)
        XCTAssertTrue(review.canRemoveApp)
        XCTAssertEqual(try u.validate(review, selected: [a.path], otherIDs: []).count, 1)
        XCTAssertEqual(try Data(contentsOf: outside), Data([1,2,3]))
    }
    func testAppContentsChangeButBundleIdentityMustStay() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let review = u.review(appPath: a.path, bundleID: id)
        _ = try put(r, "Applications/Cleaner.app/Contents/updated-state")
        XCTAssertThrowsError(try u.validate(review, selected: [a.path], otherIDs: []))
        XCTAssertEqual(try u.validate(review, selected: [a.path], otherIDs: [], allowDataChanges: true).count, 1)
        _ = try put(r, "Applications/Cleaner.app/Contents/Info.plist", plist(["CFBundleIdentifier": "org.other.app", "CFBundlePackageType": "APPL"]))
        XCTAssertThrowsError(try u.validate(review, selected: [a.path], otherIDs: [], allowDataChanges: true))
    }
    func testShutdownWritesButNotReplacedDataRoot() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let db = try put(r, "Library/Application Support/\(id)/db")
        let review = u.review(appPath: a.path, bundleID: id)
        let selection = review.defaultSelection
        try Data([4,5,6,7]).write(to: db)
        XCTAssertThrowsError(try u.validate(review, selected: selection, otherIDs: []))
        XCTAssertEqual(try u.validate(review, selected: selection, otherIDs: [], allowDataChanges: true).count, 2)
        let directory = db.deletingLastPathComponent()
        try FileManager.default.moveItem(at: directory, to: directory.appendingPathExtension("old"))
        _ = try put(r, "Library/Application Support/\(id)/db")
        XCTAssertThrowsError(try u.validate(review, selected: selection, otherIDs: [], allowDataChanges: true))
    }
    #if os(macOS)
    @MainActor func testNativeUninstallWorkflowDoesNotRouteToLeftovers() async throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let db = try put(r, "Library/Application Support/\(id)/db")
        let unknown = try put(r, "MachineLibrary/LaunchDaemons/\(id).plist", try plist(["Label": id, "Program": "/bin/sh"]))
        let review = u.review(appPath: a.path, bundleID: id)
        let destination = r.appendingPathComponent("isolated-trash")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let result = await u.trash(review, selected: review.defaultSelection, otherIDs: [], stop: { try? Data([9,8,7,6]).write(to: db); try? Data([1]).write(to: a.appendingPathComponent("Contents/shutdown-state")); return true }, isRunning: { false }, moveToTrash: { url in
            let target = destination.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        })
        XCTAssertEqual(result.moved.count, 2)
        // A passing removal must prove the stop callback ran before moving either object.
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(id + "/db")), Data([9,8,7,6]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Cleaner.app/Contents/shutdown-state").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
        XCTAssertTrue(result.failures.contains(where: { $0.contains(unknown.path) }))
    }
    @MainActor func testNativePermissionFallbackContinuesDataRemoval() async throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let db = try put(r, "Library/Application Support/\(id)/db")
        let review = u.review(appPath: a.path, bundleID: id)
        let dest = r.appendingPathComponent("isolated-trash")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
        let result = await u.trash(review, selected: review.defaultSelection, otherIDs: [], stop: { try? Data([9]).write(to: db); return true }, isRunning: { false }, moveToTrash: { url in
            if url.path == a.path { throw CocoaError(.fileWriteNoPermission) }
            let target = dest.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target); return target
        }, authorizedAppMove: { item, bundle in
            guard item.path == a.path, bundle == review.bundleID else { throw CocoaError(.fileWriteUnknown) }
            let target = dest.appendingPathComponent("authorized.app")
            try FileManager.default.moveItem(atPath: item.path, toPath: target.path); return target
        })
        XCTAssertEqual(result.moved.count, 2); XCTAssertTrue(result.failures.isEmpty, result.failures.joined(separator: "\n"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("authorized.app").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.path))
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent(id + "/db")), Data([9]))
    }
    #endif
    func testSymlinkAndForgedSelection() throws {
        let r = try fixture(); defer { try? FileManager.default.removeItem(at: r) }
        let a = try app(r), u = tool(r)
        let outside = try put(r, "outside/db")
        let link = r.appendingPathComponent("Library/Application Support/\(id)")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.deletingLastPathComponent())
        let review = u.review(appPath: a.path, bundleID: id)
        XCTAssertTrue(review.items.contains { $0.path == link.path && !$0.allowed })
        XCTAssertThrowsError(try u.validate(review, selected: [a.path, outside.path], otherIDs: []))
    }
}
