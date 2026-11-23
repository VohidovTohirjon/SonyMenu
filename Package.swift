// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SonyMenu",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "SonyMenu",
            path: "Sources/SonyMenu",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        )
    ]
)
