// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProperBar",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "ProperBarCore"),
        .executableTarget(
            name: "ProperBar",
            dependencies: ["ProperBarCore"],
            linkerSettings: [.linkedFramework("CoreWLAN"), .linkedFramework("ScreenCaptureKit")]
        ),
        .testTarget(name: "ProperBarCoreTests", dependencies: ["ProperBarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
