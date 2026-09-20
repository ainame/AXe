// swift-tools-version:6.4
import Foundation
import PackageDescription

let typeSafePackage: Package.Dependency = ProcessInfo.processInfo.environment["TYPESAFE_PACKAGE_DIR"]
    .map { .package(path: $0) }
    ?? .package(url: "https://github.com/ainame/swift-typesafe", from: "0.7.0")
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
    dependencies: [.package(path: ".."), typeSafePackage],
    targets: [
        .executableTarget(
            name: "AXeDriver",
            dependencies: [
                .product(name: "AXeSimulator", package: "AXe"),
                .product(name: "TypeSafe", package: "swift-typesafe"),
            ],
            swiftSettings: [.unsafeFlags(headerFlags)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path"])]
        ),
        .testTarget(
            name: "AXeDriverTests",
            dependencies: ["AXeDriver"],
            swiftSettings: [.unsafeFlags(headerFlags)]
        )
    ]
)
