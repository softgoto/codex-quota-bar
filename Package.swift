// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexQuotaBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]),
        .executable(name: "CodexQuotaBar", targets: ["CodexQuotaBar"]),
        .executable(name: "CodexQuotaCoreSmokeTests", targets: ["CodexQuotaCoreSmokeTests"])
    ],
    targets: [
        .target(
            name: "CodexQuotaCore"
        ),
        .executableTarget(
            name: "CodexQuotaBar",
            dependencies: ["CodexQuotaCore"]
        ),
        .executableTarget(
            name: "CodexQuotaCoreSmokeTests",
            dependencies: ["CodexQuotaCore"],
            path: "Tests/CodexQuotaCoreSmokeTests"
        )
    ]
)
