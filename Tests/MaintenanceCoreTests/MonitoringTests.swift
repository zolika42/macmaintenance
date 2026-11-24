import XCTest
@testable import MaintenanceCore
final class MonitoringTests: XCTestCase {
    func testCPUUsesLastSample() {
        XCTAssertEqual(MonitorParsing.cpu("CPU usage: 1% user, 1% sys, 98% idle\nCPU usage: 20.5% user, 4.5% sys, 75% idle"), 25)
        XCTAssertNil(MonitorParsing.cpu("CPU usage: 101% idle")); XCTAssertNil(MonitorParsing.cpu("unavailable"))
    }
    func testMemoryUsesReportedPageSize() {
        let text = "Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages active: 10.\nPages wired down: 5.\nPages occupied by compressor: 2.\nPages free: 100."
        XCTAssertEqual(MonitorParsing.memory(text), 17 * 16384)
        XCTAssertNil(MonitorParsing.memory("Pages active: 100."))
        XCTAssertEqual(MonitorParsing.swap("total = 4096.00M used = 512.50M free = 3583.50M"), 537395200)
    }
    func testBatteryAndNetwork() {
        XCTAssertEqual(MonitorParsing.battery("-InternalBattery-0  88%; charging; 0:40 remaining")?.0, 88)
        XCTAssertEqual(MonitorParsing.batteryCycles("\"CycleCount\" = 123"), 123)
        let rows = "Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll\nen0 1500 <Link#6> aa:bb 1 0 100 2 0 200 0\nen0 1500 192.168.0 192.168.0.1 1 0 100 2 0 200 0\nutun0 1500 <Link#7> xx 1 0 900 2 0 900 0"
        let previous = MonitorParsing.network(rows)
        XCTAssertEqual(previous, ["en0": .init(received: 100, sent: 200)])
        let rates = MonitorParsing.networkRates(previous: previous, current: ["en0": .init(received: 200, sent: 240)], seconds: 2)
        XCTAssertEqual(rates?.0, 50); XCTAssertEqual(rates?.1, 20)
        XCTAssertNil(MonitorParsing.networkRates(previous: previous, current: ["en0": .init(received: 1, sent: 1)], seconds: 2))
        XCTAssertNil(MonitorParsing.networkRates(previous: previous, current: [:], seconds: 2))
        XCTAssertNil(MonitorParsing.networkRates(previous: previous, current: previous, seconds: 0))
    }
}
