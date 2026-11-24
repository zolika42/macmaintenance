// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MacMaintenance", platforms: [.macOS(.v14)], products: [.executable(name: "MacMaintenance", targets: ["MacMaintenance"])], targets: [.target(name: "NativeMove"), .target(name: "MaintenanceCore", dependencies: ["NativeMove"]), .executableTarget(name: "MacMaintenance", dependencies: ["MaintenanceCore"]), .testTarget(name: "MaintenanceCoreTests", dependencies: ["MaintenanceCore"])])
