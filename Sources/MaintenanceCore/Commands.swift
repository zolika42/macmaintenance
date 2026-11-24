import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
public struct Command: Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let executable: String
    public let arguments: [String]
    public init(_ title: String, _ executable: String, _ arguments: [String]) { self.title = title; self.executable = executable; self.arguments = arguments }
}
public struct CommandResult: Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let output: String
    public let status: Int32?
}
public enum Runner {
    public static func run(_ command: Command, timeout: TimeInterval = 8, outputLimit: Int = 96_000) -> CommandResult {
        guard (1...1_000_000).contains(outputLimit), timeout.isFinite, timeout > 0, timeout <= 3600, !Task.isCancelled else { return .init(title: command.title, output: "Invalid output limit, timeout or cancellation", status: nil) }
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: command.executable) else { return .init(title: command.title, output: "Not installed / unavailable", status: nil) }
        let directory = fm.temporaryDirectory.appendingPathComponent("MacMaintenance-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: directory) }
            let log = directory.appendingPathComponent("output")
            guard fm.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            let handle = try FileHandle(forUpdating: log); defer { try? handle.close() }
            let p = Process(); p.executableURL = URL(fileURLWithPath: command.executable); p.arguments = command.arguments
            p.standardOutput = handle; p.standardError = handle; p.standardInput = FileHandle.nullDevice
            var env = ProcessInfo.processInfo.environment
            env["LC_ALL"] = "C"
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"; env["HOMEBREW_NO_ANALYTICS"] = "1"
            env["DOCKER_HOST"] = nil; env["DOCKER_CONTEXT"] = nil
            p.environment = env
            try p.run()
            let start = ProcessInfo.processInfo.systemUptime
            var truncated = false
            while p.isRunning && ProcessInfo.processInfo.systemUptime - start < timeout && !Task.isCancelled {
                if ((try? fm.attributesOfItem(atPath: log.path)[.size] as? NSNumber)?.intValue ?? 0) > 1_000_000 { truncated = true; break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            let interrupted = p.isRunning
            if interrupted { p.terminate(); Thread.sleep(forTimeInterval: 0.2); if p.isRunning { _ = kill(p.processIdentifier, SIGKILL) } }
            p.waitUntilExit(); try handle.seek(toOffset: 0)
            let bytes = try handle.read(upToCount: outputLimit + 1) ?? Data()
            var output = String(decoding: bytes.prefix(outputLimit), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if interrupted { output += truncated ? "\n[output limit reached]" : "\n[timeout or cancellation]" }
            if bytes.count > outputLimit { output += "\n[output truncated]" }
            return .init(title: command.title, output: output.isEmpty ? "(no output)" : output, status: interrupted ? nil : p.terminationStatus)
        } catch { return .init(title: command.title, output: error.localizedDescription, status: nil) }
    }
}
