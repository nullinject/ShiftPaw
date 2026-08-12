// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShiftPaw",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ShiftPaw", targets: ["ShiftPaw"])
    ],
    targets: [
        .executableTarget(name: "ShiftPaw"),
        .testTarget(name: "ShiftPawTests", dependencies: ["ShiftPaw"])
    ]
)
