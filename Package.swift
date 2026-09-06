// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ns2controller",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "ns2ctl", targets: ["ns2ctl"]),
        .library(name: "NS2Core", targets: ["NS2Core"]),
    ],
    targets: [
        .target(
            name: "NS2Core",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOUSBHost"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(
            name: "ns2ctl",
            dependencies: ["NS2Core"]
        ),
        .testTarget(
            name: "NS2CoreTests",
            dependencies: ["NS2Core"]
        ),
    ]
)
