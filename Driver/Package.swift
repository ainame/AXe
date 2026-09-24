// swift-tools-version:6.4
import Foundation
import PackageDescription

let idbHeaders = ProcessInfo.processInfo.environment["IDB_CHECKOUT_DIR"]
    .map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("idb_checkout")
let headerRoot = idbHeaders.appendingPathComponent("PrivateHeaders")
let headerFlags = ["", "AccessibilityPlatformTranslation", "AXRuntime", "CoreSimDeviceIO",
                   "CoreSimulator", "CoreSimulatorUtilities", "SimulatorKit"]
    .map { "-I\(headerRoot.appendingPathComponent($0).path)" }

let package = Package(
    name: "AXeDriver",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "axe-driver", targets: ["AXeDriver"])],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/ainame/swift-typesafe", from: "0.7.2"),
    ],
    targets: [
        .executableTarget(
            name: "AXeDriver",
            dependencies: [
                .product(name: "AXeSimulator", package: "AXe"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TypeSafe", package: "swift-typesafe"),
            ],
            swiftSettings: [.unsafeFlags(headerFlags)]
        ),
        .testTarget(
            name: "AXeDriverTests",
            dependencies: ["AXeDriver"],
            swiftSettings: [.unsafeFlags(headerFlags)]
        )
    ]
)
