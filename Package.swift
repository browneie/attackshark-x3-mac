// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "attackshark-x3-mac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "x3ctl", targets: ["x3ctl"]),
        .executable(name: "X3Config", targets: ["X3Config"]),
    ],
    targets: [
        .target(name: "X3Kit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "x3ctl", dependencies: ["X3Kit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "X3Config", dependencies: ["X3Kit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
