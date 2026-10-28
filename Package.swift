// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NovaV4Mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "V4Kit", targets: ["V4Kit"]),
        .executable(name: "NovaV4", targets: ["NovaV4"]),
        .executable(name: "novav4ctl", targets: ["novav4ctl"]),
    ],
    targets: [
        .target(
            name: "V4Kit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(name: "NovaV4", dependencies: ["V4Kit"]),
        .executableTarget(name: "novav4ctl", dependencies: ["V4Kit"]),
        .executableTarget(name: "v4kit-selftest", dependencies: ["V4Kit"]),
    ]
)
