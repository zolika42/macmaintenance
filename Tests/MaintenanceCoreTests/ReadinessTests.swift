import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import MaintenanceCore
final class ReadinessTests: XCTestCase {
    func testPermissionSetupPerVersionAndInstalledLocation() {
        XCTAssertTrue(PermissionSetupPolicy.needsReview(installedVersion: "1.3.0", reviewedVersion: "1.2.3"))
        XCTAssertTrue(PermissionSetupPolicy.needsReview(installedVersion: "unknown", reviewedVersion: "unknown"))
        XCTAssertFalse(PermissionSetupPolicy.needsReview(installedVersion: "1.3.0", reviewedVersion: "1.3.0"))
        XCTAssertTrue(PermissionSetupPolicy.installedPath("/Applications/MacMaintenance.app", home: "/Users/test"))
        XCTAssertTrue(PermissionSetupPolicy.installedPath("/Users/test/Applications/MacMaintenance.app", home: "/Users/test"))
        XCTAssertFalse(PermissionSetupPolicy.installedPath("/Volumes/MacMaintenance/MacMaintenance.app", home: "/Users/test"))
        XCTAssertFalse(PermissionSetupPolicy.installedPath("/Applications/.MacMaintenance-backups/backup.x/MacMaintenance.app", home: "/Users/test"))
    }
    func testProtectionKnownStates() {
        XCTAssertEqual(ProtectionCheck.fileVault.evaluate(output: "FileVault is On.", status: 0), .enabled)
        XCTAssertEqual(ProtectionCheck.sip.evaluate(output: "System Integrity Protection status: disabled.", status: 0), .disabled)
        XCTAssertEqual(ProtectionCheck.gatekeeper.evaluate(output: "assessments enabled", status: 0), .enabled)
        XCTAssertEqual(ProtectionCheck.firewall.evaluate(output: "Firewall is enabled. (State = 1)", status: 0), .enabled)
    }
    func testProtectionFailsClosed() {
        let p = ProtectionCheck.fileVault
        for text in ["not FileVault is On.", "FileVault is On.\nFileVault is Off.", "FileVault is On.\nEncryption in progress", "FileVault is On.\n[output truncated]"] {
            XCTAssertEqual(p.evaluate(output: text, status: 0), .unknown)
        }
        XCTAssertEqual(p.evaluate(output: "FileVault is On.", status: 1), .unknown)
        XCTAssertEqual(p.evaluate(output: "FileVault is On.", status: nil), .unknown)
        XCTAssertEqual(ProtectionCheck.sip.evaluate(output: "System Integrity Protection status: enabled (Custom Configuration).", status: 0), .unknown)
    }
    func testProbeErrorClassification() {
        XCTAssertEqual(PermissionProbe.classify(EPERM), .denied)
        XCTAssertEqual(PermissionProbe.classify(EACCES), .denied)
        XCTAssertEqual(PermissionProbe.classify(ENOENT), .missing)
        XCTAssertEqual(PermissionProbe.classify(EIO), .unavailable)
    }
    func testProbeDoesNotFollowFinalSymlink() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        XCTAssertEqual(PermissionProbe.directory(root), .accessible)
        XCTAssertEqual(PermissionProbe.directory(root.appendingPathComponent("absent")), .missing)
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertEqual(PermissionProbe.directory(link), .unavailable)
        XCTAssertEqual(PermissionProbe.directory(URL(string: "https://example.invalid")!), .unavailable)
    }
    func testLargestMatchesFullSortAndStableTies() {
        let input = (0..<8000).map { FileCandidate(url: URL(fileURLWithPath: "/fixture/\($0)"), bytes: Int64(($0 * 31) % 103)) }
        var top = LargestCandidates(limit: 37)
        for item in input.reversed() { top.add(item) }
        let expected = input.sorted { $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes > $1.bytes }
        XCTAssertEqual(top.result, Array(expected.prefix(37)))
    }
    func testInvalidLimitAndNegativeSize() {
        var top = LargestCandidates(limit: 0)
        top.add(.init(url: URL(fileURLWithPath: "/negative"), bytes: -1))
        XCTAssertTrue(top.result.isEmpty)
        top.add(.init(url: URL(fileURLWithPath: "/ok"), bytes: 0))
        XCTAssertEqual(top.result.count, 1)
    }
    func testInvalidTimeoutRefusedBeforeLaunch() {
        for timeout in [0.0, -1.0, .infinity, .nan] {
            let result = Runner.run(.init("invalid", "/bin/echo", ["not executed"]), timeout: timeout)
            XCTAssertNil(result.status); XCTAssertTrue(result.output.contains("timeout"))
        }
    }
}
