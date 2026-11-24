import Foundation
#if os(macOS)
import Darwin
#endif
import XCTest
@testable import MaintenanceCore

final class ServiceRemovalTests: XCTestCase {
    func testBSDProcessIdentityColumnsAndMalformedRows() {
        XCTAssertEqual(ServiceRemoval.processIdentityArguments, ["-axww", "-o", "pid=", "-o", "uid=", "-o", "state="])
        func parse(_ output: String, status: Int32? = 0) -> ServiceRemoval.ProcessScan {
            ServiceRemoval.parseProcessIdentities(.init(title: "ps", output: output, status: status), uid: 502, selfPID: 100)
        }
        XCTAssertEqual(parse("  1  0 Ss\n 100 502 R+\n71600 502 S\n71601 502 Z\n71602 501 S\n"), .verified([71600]))
        XCTAssertEqual(parse("100 502 S\n71601 502 Z"), .verified([]))
        XCTAssertNil(parse(",uid=,state=\n100\n71600").pids)
        XCTAssertNil(parse("100 502 R\n71600 502").pids)
        XCTAssertNil(parse("71600 502 S").pids)
        XCTAssertNil(parse("100 502 S\n[output truncated]").pids)
        XCTAssertNil(parse("100 502 S", status: nil).pids)
    }
    func testSignedDarwinSystemUIDs() {
        let rows = "  1 0 Ss\n 100 502 R+\n64651    -2 Ss  \n71600 502 S\n71601 4294967294 S\n71602 -1 S\n71603 -2147483648 S"
        func parse(_ output: String) -> ServiceRemoval.ProcessScan {
            ServiceRemoval.parseProcessIdentities(.init(title: "ps", output: output, status: 0), uid: 502, selfPID: 100)
        }
        XCTAssertEqual(parse(rows), .verified([71600]))
        XCTAssertEqual(ServiceRemoval.processUID("-2"), UInt32.max - 1)
        XCTAssertEqual(ServiceRemoval.processUID("4294967294"), UInt32.max - 1)
        XCTAssertEqual(ServiceRemoval.processUID("-2147483648"), 2147483648)
        for invalid in ["-2147483649", "4294967296", "-2x", "nobody"] {
            XCTAssertNil(parse("100 502 S\n64651 \(invalid) Ss").pids)
        }
        XCTAssertEqual(ServiceRemoval.parseUserProcesses(.init(title: "ps", output: "64651 -2 /Applications/A.app/Contents/MacOS/A\n71600 502 /Applications/A.app/Contents/MacOS/A", status: 0), appPath: "/Applications/A.app", uid: 502, selfPID: 100), .verified([71600]))
    }
    #if os(macOS)
    func testActualBSDProcessIdentityListing() {
        let r = Runner.run(.init("Actual BSD ps", "/bin/ps", ServiceRemoval.processIdentityArguments), outputLimit: 1_000_000)
        let scan = ServiceRemoval.parseProcessIdentities(r, uid: getuid(), selfPID: getpid())
        XCTAssertNotNil(scan.pids, "\(scan)")
    }
    #endif
    func testNativeExecutablePathAliasesAndBoundary() {
        let app = "/private/var/tmp/Fixture.app"
        XCTAssertTrue(ServiceRemoval.matchesExecutable("/System/Volumes/Data/private/var/tmp/Fixture.app/Contents/MacOS/Fixture", appPath: app))
        XCTAssertTrue(ServiceRemoval.matchesExecutable("/var/tmp/Fixture.app/Contents/MacOS/Fixture", appPath: app))
        XCTAssertFalse(ServiceRemoval.matchesExecutable("Fixture", appPath: app))
        XCTAssertFalse(ServiceRemoval.matchesExecutable(app + "-other/Contents/MacOS/Fixture", appPath: app))
        XCTAssertFalse(ServiceRemoval.matchesExecutable(app + "/../Other", appPath: app))
    }
    func testProcessListSeparatesUnavailableFromNoMatch() {
        let app = "/Applications/Example App.app"
        func scan(_ output: String, status: Int32? = 0) -> ServiceRemoval.ProcessScan {
            ServiceRemoval.parseUserProcesses(.init(title: "ps", output: output, status: status), appPath: app, uid: 501, selfPID: 99)
        }
        XCTAssertEqual(scan("1 0 /sbin/launchd\n22 501 /bin/ps"), .verified([]))
        XCTAssertEqual(scan("  42 501 /Applications/Example App.app/Contents/MacOS/Example App\n43 502 /Applications/Example App.app/Contents/MacOS/Example App\n44 501 /Applications/Example App.app-other/Contents/MacOS/Example App\n99 501 /Applications/Example App.app/Contents/MacOS/Example App"), .verified([42]))
        XCTAssertEqual(scan("22 501 /bin/ps\n[output truncated]"), .unavailable("Process list exceeded its output limit"))
        XCTAssertNil(scan("(no output)").pids)
        XCTAssertNil(scan("invalid row").pids)
        XCTAssertNil(scan("22 501 /bin/ps", status: nil).pids)
        let long = (1000..<4000).map { "\($0) 501 /Applications/Unrelated.app/Contents/MacOS/LongExecutableName" }.joined(separator: "\n")
        XCTAssertEqual(scan(long + "\n42 501 /Applications/Example App.app/Contents/MacOS/Example App"), .verified([42]))
    }
    func testRunnerOutputLimitIsExplicit() {
        let data = String(repeating: "x", count: 100_000)
        let command = Command("output", "/bin/echo", [data])
        let limited = Runner.run(command)
        XCTAssertEqual(limited.status, 0); XCTAssertTrue(limited.output.contains("[output truncated]"))
        let full = Runner.run(command, outputLimit: 200_000)
        XCTAssertEqual(full.status, 0); XCTAssertEqual(full.output, data)
    }
    func testOwnershipBoundary() {
        XCTAssertTrue(ServiceRemoval.belongs("COM.Example.App.Helper", to: "com.example.app"))
        XCTAssertFalse(ServiceRemoval.belongs("com.example.application.helper", to: "com.example.app"))
        XCTAssertFalse(ServiceRemoval.belongs("com.other.app", to: "com.example.app"))
        XCTAssertTrue(ServiceRemoval.child("/Applications/A.app/Contents/MacOS/A", of: "/Applications/A.app"))
        XCTAssertFalse(ServiceRemoval.child("/Applications/A.app-other/Contents/MacOS/A", of: "/Applications/A.app"))
        XCTAssertFalse(ServiceRemoval.child("/Applications/A.app/../Other", of: "/Applications/A.app"))
    }
    func testKnownCCleanerJobsAreExact() {
        XCTAssertTrue(ServiceRemoval.knownJob("com.piriform.ccleaner.update", bundleID: "com.piriform.ccleaner", folder: "LaunchAgents"))
        XCTAssertFalse(ServiceRemoval.knownJob("com.piriform.ccleaner.update.extra", bundleID: "com.piriform.ccleaner", folder: "LaunchAgents"))
        XCTAssertFalse(ServiceRemoval.knownJob("com.piriform.ccleaner.update", bundleID: "org.other.app", folder: "LaunchAgents"))
        XCTAssertFalse(ServiceRemoval.knownJob("com.piriform.ccleaner.update", bundleID: "com.piriform.ccleaner", folder: "LaunchDaemons"))
    }
    func testPermissionFallbackAndNoEscalationForOtherErrors() throws {
        let source = URL(fileURLWithPath: "/Applications/Example.app")
        let dest = URL(fileURLWithPath: "/quarantine/item")
        var calls = 0
        let moved = try ServiceRemoval.moveWithPermissionFallback(source, trash: { _ in throw CocoaError(.fileWriteNoPermission) }, authorized: { calls += 1; return dest })
        XCTAssertEqual(moved, dest); XCTAssertEqual(calls, 1)
        XCTAssertEqual(try ServiceRemoval.moveWithPermissionFallback(source, trash: { _ in dest }, authorized: { calls += 1; return nil }), dest)
        XCTAssertThrowsError(try ServiceRemoval.moveWithPermissionFallback(source, trash: { _ in throw CocoaError(.fileWriteOutOfSpace) }, authorized: { calls += 1; return dest }))
        XCTAssertEqual(calls, 1)
        XCTAssertThrowsError(try ServiceRemoval.moveWithPermissionFallback(source, trash: { _ in throw CocoaError(.fileWriteNoPermission) }, authorized: { throw CocoaError(.userCancelled) }))
        XCTAssertTrue(ServiceRemoval.permissionDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)])))
    }
    func testACLListingFailsClosed() {
        XCTAssertTrue(ServiceRemoval.aclFreeListing("drwxr-xr-x  2 root wheel 64 /Library/Test"))
        XCTAssertTrue(ServiceRemoval.aclFreeListing("-rw-------@ 1 root wheel 64 /Library/Test"))
        for listing in ["", "ls: denied", "drwxr-xr-x+ 2 root wheel 64 /Library/Test", "drwxr-xr-x@ 2 root wheel 64 /Library/Test\n 0: group:everyone allow write", "lrwxr-xr-x 1 root wheel 64 /Library/Test"] {
            XCTAssertFalse(ServiceRemoval.aclFreeListing(listing), listing)
        }
    }
    func testReviewedStatIdentityCannotBeReplaced() {
        XCTAssertTrue(ServiceRemoval.matchesStatIdentity("1:2:3:4", device: 1, inode: 2))
        XCTAssertFalse(ServiceRemoval.matchesStatIdentity("9:2:3:4", device: 1, inode: 2))
        XCTAssertFalse(ServiceRemoval.matchesStatIdentity("1:20:3:4", device: 1, inode: 2))
        XCTAssertFalse(ServiceRemoval.matchesStatIdentity("1:2:3:4", device: nil, inode: 2))
        XCTAssertFalse(ServiceRemoval.matchesStatIdentity("1:2:3:4", device: 1, inode: nil))
        for value in ["1::2:3:4", ":1:2:3:4", "1:2:3:4:", "1:2:3", "1:2:3:4:5", "1:2:3:x", "1:2:3:18446744073709551616"] {
            XCTAssertFalse(ServiceRemoval.validStatIdentity(value), value)
            XCTAssertFalse(ServiceRemoval.matchesStatIdentity(value, device: 1, inode: 2), value)
        }
    }
    func testAuthorizedAppPlanScopeAndIdentity() throws {
        let script = try XCTUnwrap(ServiceRemoval.applicationMoveScript(path: "/Applications/O'Neil.app", bundleID: "org.example.app", identity: "1:2:3:4"))
        XCTAssertTrue(script.contains("CFBundleIdentifier")); XCTAssertTrue(script.contains("CFBundlePackageType"))
        XCTAssertTrue(script.contains("MacMaintenance-removed.")); XCTAssertTrue(script.contains("O'\\''Neil.app"))
        XCTAssertLessThan(try XCTUnwrap(script.range(of: "CFBundleIdentifier")).lowerBound, try XCTUnwrap(script.range(of: "/bin/mv")).lowerBound)
        XCTAssertLessThan(try XCTUnwrap(script.range(of: "1:2:3:4")).lowerBound, try XCTUnwrap(script.range(of: "/bin/mv")).lowerBound)
        for path in ["/System/Applications/Finder.app", "/Applications/../System/Applications/Finder.app", "/Applications/A.app/Contents/B.app", "/Applications/not-an-app", "/Users/me/Applications/A.app"] {
            XCTAssertNil(ServiceRemoval.applicationMoveScript(path: path, bundleID: "org.example.app", identity: "1:2:3:4"))
        }
        for id in ["com.apple.Finder", "local.macmaintenance.toolkit"] { XCTAssertNil(ServiceRemoval.applicationMoveScript(path: "/Applications/A.app", bundleID: id, identity: "1:2:3:4")) }
        XCTAssertNil(ServiceRemoval.applicationMoveScript(path: "/Applications/A.app", bundleID: "org.example.app", identity: "1:2:3:$(id)"))
        XCTAssertFalse(script.contains("rm -")); XCTAssertFalse(script.contains("chmod")); XCTAssertFalse(script.contains("chflags"))
        XCTAssertTrue(script.contains("0022")); XCTAssertTrue(script.contains("/bin/ls -lde"))
        XCTAssertFalse(script.contains("= 80"))
        XCTAssertNil(ServiceRemoval.applicationMoveScript(path: "/Applications//A.app", bundleID: "org.example.app", identity: "1:2:3:4"))
        XCTAssertNil(ServiceRemoval.applicationMoveScript(path: "/Applications/A\u{0000}.app", bundleID: "org.example.app", identity: "1:2:3:4"))
    }
    func testAdminPlanQuotesAndChecksBeforeMove() throws {
        let path = "/Library/LaunchDaemons/com.example.a.plist"
        let script = ServiceRemoval.rootMoveScript(path: path, identity: "1:2:3:4", service: "system/com.example.a", program: "/Applications/O'Neil.app/Contents/MacOS/A")
        XCTAssertTrue(script.contains("O'\\''Neil.app"))
        XCTAssertTrue(script.contains("/bin/launchctl bootout"))
        XCTAssertLessThan(try XCTUnwrap(script.range(of: "launchctl disable")).lowerBound, try XCTUnwrap(script.range(of: "bootout")).lowerBound)
        XCTAssertTrue(script.contains("/usr/bin/stat"))
        XCTAssertTrue(script.contains("/private/var/root/MacMaintenance-removed."))
        XCTAssertLessThan(try XCTUnwrap(script.range(of: "identity.txt")).lowerBound, try XCTUnwrap(script.range(of: "launchctl disable")).lowerBound)
        XCTAssertTrue(script.contains("/bin/ls -lde"))
        XCTAssertFalse(script.contains("rm -"))
        XCTAssertLessThan(try XCTUnwrap(script.range(of: "bootout")).lowerBound, try XCTUnwrap(script.range(of: "/bin/mv")).lowerBound)
    }
}
