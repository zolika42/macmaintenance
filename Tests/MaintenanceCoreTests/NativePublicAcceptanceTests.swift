#if os(macOS)
import Foundation
import Darwin
import XCTest
@testable import MaintenanceCore

final class NativePublicAcceptanceTests: XCTestCase {
    @MainActor func testRealKeepAliveAndRemoval() async throws {
        guard ProcessInfo.processInfo.environment["MM_NATIVE_LAUNCHD_QA"] == "1" else { throw XCTSkip("Run make native-acceptance in the logged-in macOS GUI session") }
        let ptr = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil)); defer { free(ptr) }
        let root = URL(fileURLWithPath: String(cString: ptr)).appendingPathComponent("mm-native-" + UUID().uuidString)
        let id = "local.macmaintenance.qa." + UUID().uuidString.lowercased()
        let apps = root.appendingPathComponent("Applications"), app = apps.appendingPathComponent("Fixture.app")
        let exe = app.appendingPathComponent("Contents/MacOS/Fixture"), agent = root.appendingPathComponent("Library/LaunchAgents/\(id).plist")
        let data = root.appendingPathComponent("Library/Application Support/\(id)/database.sqlite")
        let quarantine = root.appendingPathComponent("quarantine")
        let domain = "gui/\(getuid())", job = domain + "/" + id
        let fm = FileManager.default
        defer {
            _ = Runner.run(.init("QA cleanup", "/bin/launchctl", ["bootout", job]))
            _ = Runner.run(.init("QA cleanup", "/bin/launchctl", ["enable", job]))
            try? fm.removeItem(at: root)
        }
        for folder in [exe.deletingLastPathComponent(), agent.deletingLastPathComponent(), data.deletingLastPathComponent(), quarantine] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        // Build our own executable, rather than copying an Apple platform binary.
        let source = root.appendingPathComponent("fixture.c")
        try Data("#include <unistd.h>\nint main(void) { for (;;) pause(); }\n".utf8).write(to: source)
        let compile = Runner.run(.init("QA compile", "/usr/bin/xcrun", ["clang", "-O2", source.path, "-o", exe.path]), timeout: 60)
        XCTAssertEqual(compile.status, 0, compile.output); guard compile.status == 0 else { return }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":id,"CFBundlePackageType":"APPL","CFBundleExecutable":"Fixture"], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let signed = Runner.run(.init("QA sign", "/usr/bin/codesign", ["--force", "--sign", "-", app.path]), timeout: 30)
        XCTAssertEqual(signed.status, 0, signed.output); guard signed.status == 0 else { return }
        try PropertyListSerialization.data(fromPropertyList: ["Label":id,"ProgramArguments":[exe.path],"KeepAlive":true,"RunAtLoad":true,"ThrottleInterval":1], format: .xml, options: 0).write(to: agent)
        try Data("disposable fixture only".utf8).write(to: data)
        let loaded = Runner.run(.init("QA bootstrap", "/bin/launchctl", ["bootstrap",domain,agent.path]))
        XCTAssertEqual(loaded.status, 0, loaded.output); guard loaded.status == 0 else { return }
        var initial = ServiceRemoval.scanUserProcesses(in: app.path)
        for _ in 0..<60 {
            if let pids = initial.pids, !pids.isEmpty { break }
            try await Task.sleep(for: .milliseconds(200))
            initial = ServiceRemoval.scanUserProcesses(in: app.path)
        }
        let launchState = Runner.run(.init("QA launch state", "/bin/launchctl", ["print",job]))
        let initialPIDs = try XCTUnwrap(initial.pids, "Process discovery unavailable: \(initial)\n\(launchState.output)")
        XCTAssertFalse(initialPIDs.isEmpty, "KeepAlive fixture did not launch or executable lookup missed it: \(initial)\n\(launchState.output)")
        guard !initialPIDs.isEmpty else { return }
        let engine = FullUninstaller(home: root, applications: apps, systemLibrary: root.appendingPathComponent("MachineLibrary"))
        let review = engine.review(appPath: app.path, bundleID: id)
        XCTAssertTrue(review.defaultSelection.contains(agent.path)); XCTAssertTrue(review.defaultSelection.contains(app.path)); XCTAssertTrue(review.defaultSelection.contains(data.deletingLastPathComponent().path))
        let result = await engine.trash(review, selected: review.defaultSelection, otherIDs: [], stop: {
            var quiet = 0
            for _ in 0..<30 {
                ServiceRemoval.signalOwnedProcesses(in: app.path, force: true)
                let scan = ServiceRemoval.scanUserProcesses(in: app.path)
                if scan.pids?.isEmpty == true { quiet += 1; if quiet >= 3 { return true } } else { quiet = 0 }
                try? await Task.sleep(for: .milliseconds(200))
            }
            return false
        }, isRunning: { !(ServiceRemoval.userProcesses(in: app.path)?.isEmpty ?? false) }, moveToTrash: { url in
            // Native real file moves, but no user's Trash is touched by this fixture.
            let destination = quarantine.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination); return destination
        })
        XCTAssertEqual(result.moved.count, 3, result.failures.joined(separator: "\n") + "\nProcess scan: \(ServiceRemoval.scanUserProcesses(in: app.path))"); XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: app.path)); XCTAssertFalse(fm.fileExists(atPath: agent.path)); XCTAssertFalse(fm.fileExists(atPath: data.path))
        try await Task.sleep(for: .seconds(2))
        let state = Runner.run(.init("QA verify", "/bin/launchctl", ["print",job]))
        XCTAssertNotEqual(state.status, 0); XCTAssertEqual(ServiceRemoval.scanUserProcesses(in: app.path), .verified([]))
    }
}
#endif
