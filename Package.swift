// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoseControl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BoseControl", targets: ["BoseControlApp"])
    ],
    targets: [
        .target(
            name: "BoseBluetoothBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("IOBluetooth")
            ]
        ),
        .executableTarget(
            name: "BoseControlApp",
            dependencies: ["BoseBluetoothBridge"],
            path: "Sources/BoseControlApp"
        ),
        .testTarget(
            name: "BoseControlTests",
            dependencies: ["BoseControlApp"],
            path: "Tests/BoseControlTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
