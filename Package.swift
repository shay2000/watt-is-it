// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WattIsIt",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WattIsIt", targets: ["WattIsIt"])
    ],
    targets: [
        .executableTarget(
            name: "WattIsIt",
            path: "Sources/WattIsIt",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
