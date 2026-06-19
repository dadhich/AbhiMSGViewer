// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AbhiMSGViewer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MSGParser",
            targets: ["MSGParser"]
        ),
        .executable(
            name: "MSGFileViewer",
            targets: ["MSGFileViewer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/typelift/SwiftCheck", from: "0.12.0")
    ],
    targets: [
        .target(
            name: "MSGParser",
            path: "Sources/MSGParser"
        ),
        .executableTarget(
            name: "MSGFileViewer",
            dependencies: ["MSGParser"],
            path: "Sources/MSGFileViewer",
            exclude: ["Info.plist", "MSGFileViewer.entitlements", "AppIcon.icns"]
        ),
        .testTarget(
            name: "MSGParserTests",
            dependencies: [
                "MSGParser",
                "SwiftCheck"
            ],
            path: "Tests/MSGParserTests"
        )
    ]
)
