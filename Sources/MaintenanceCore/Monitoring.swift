import Foundation

public struct NetworkCounters: Sendable, Equatable {
    public let received: UInt64
    public let sent: UInt64
    public init(received: UInt64, sent: UInt64) { self.received = received; self.sent = sent }
}
public struct MonitorReading: Sendable, Identifiable {
    public let id = UUID()
    public let date: Date
    public let cpu: Double?
    public let memoryBytes: UInt64?
    public let totalMemory: UInt64
    public let swapBytes: UInt64?
    public let battery: Double?
    public let batteryState: String?
    public let thermal: String
    public let network: [String: NetworkCounters]
    public let downloadRate: Double?
    public let uploadRate: Double?
    public var memoryPercent: Double? { guard let memoryBytes, totalMemory > 0 else { return nil }; return min(100, Double(memoryBytes) / Double(totalMemory) * 100) }
    public init(date: Date = Date(), cpu: Double?, memoryBytes: UInt64?, totalMemory: UInt64, swapBytes: UInt64?, battery: Double?, batteryState: String?, thermal: String, network: [String: NetworkCounters], previous: MonitorReading?) {
        self.date = date; self.cpu = cpu; self.memoryBytes = memoryBytes; self.totalMemory = totalMemory; self.swapBytes = swapBytes; self.battery = battery; self.batteryState = batteryState; self.thermal = thermal; self.network = network
        let rates = previous.flatMap { MonitorParsing.networkRates(previous: $0.network, current: network, seconds: date.timeIntervalSince($0.date)) }
        self.downloadRate = rates?.0; self.uploadRate = rates?.1
    }
}
public enum MonitorParsing {
    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]), let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<result.numberOfRanges).map { Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
    public static func cpu(_ text: String) -> Double? {
        let lines = text.split(separator: "\n").filter { $0.contains("CPU usage:") }
        guard let last = lines.last, let match = captures(#"([0-9]+(?:\.[0-9]+)?)%\s+idle"#, String(last)), let idle = Double(match[0]), (0...100).contains(idle) else { return nil }
        return 100 - idle
    }
    // Active + wired + compressed physical pages; not the Activity Monitor total.
    public static func memory(_ text: String) -> UInt64? {
        guard let page = captures(#"page size of ([0-9]+) bytes"#, text).flatMap({ UInt64($0[0]) }), page > 0 else { return nil }
        var sum: UInt64 = 0
        for key in ["Pages active", "Pages wired down", "Pages occupied by compressor"] {
            guard let n = captures("^" + key + #":\s*([0-9]+)\.?\s*$"#, text).flatMap({ UInt64($0[0]) }) else { return nil }
            let (next, overflow) = sum.addingReportingOverflow(n); guard !overflow else { return nil }; sum = next
        }
        let (bytes, overflow) = sum.multipliedReportingOverflow(by: page); return overflow ? nil : bytes
    }
    public static func swap(_ text: String) -> UInt64? {
        guard let m = captures(#"used\s*=\s*([0-9]+(?:\.[0-9]+)?)([KMGT]?)"#, text), let value = Double(m[0]) else { return nil }
        let factor: Double = ["K": 1024, "M": 1048576, "G": 1073741824, "T": 1099511627776][m[1]] ?? 1
        let bytes = value * factor; guard bytes.isFinite, bytes >= 0, bytes < Double(UInt64.max) else { return nil }; return UInt64(bytes)
    }
    public static func battery(_ text: String) -> (Double, String)? {
        guard let m = captures(#"([0-9]+)%;\s*([^;\n]+);"#, text), let percent = Double(m[0]), (0...100).contains(percent) else { return nil }
        return (percent, m[1].trimmingCharacters(in: .whitespaces))
    }
    // Link rows only, en* interfaces; exclude protocol-address duplicate rows.
    public static func network(_ text: String) -> [String: NetworkCounters] {
        let lines = text.split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
        guard let header = lines.first, let input = header.firstIndex(of: "Ibytes"), let output = header.firstIndex(of: "Obytes"), let name = header.firstIndex(of: "Name"), let network = header.firstIndex(of: "Network") else { return [:] }
        var result: [String: NetworkCounters] = [:]
        for row in lines.dropFirst() where row.count > max(input, output, name, network) {
            let iface = row[name].trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            guard iface.range(of: #"^en[0-9]+$"#, options: .regularExpression) != nil, row[network].hasPrefix("<Link#"), let rx = UInt64(row[input]), let tx = UInt64(row[output]) else { continue }
            result[iface] = .init(received: rx, sent: tx)
        }
        return result
    }
    public static func networkRates(previous: [String: NetworkCounters], current: [String: NetworkCounters], seconds: Double) -> (Double, Double)? {
        guard seconds.isFinite, seconds > 0, !current.isEmpty, Set(previous.keys) == Set(current.keys) else { return nil }
        var rx = 0.0, tx = 0.0
        for (key, now) in current {
            guard let old = previous[key], now.received >= old.received, now.sent >= old.sent else { return nil }
            rx += Double(now.received - old.received); tx += Double(now.sent - old.sent)
        }
        return (rx / seconds, tx / seconds)
    }
    public static func batteryCycles(_ text: String) -> UInt64? { captures(#""CycleCount"\s*=\s*([0-9]+)"#, text).flatMap { UInt64($0[0]) } }
}
