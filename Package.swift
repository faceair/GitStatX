// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitStatX",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "GitStatX",
            targets: ["GitStatX"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "GitStatX",
            path: "Sources",
            exclude: [
                "GitStatX/Resources/AppIcon.iconset",
                "GitStatX/Resources/AppIcon.icns",
                "GitStatX/Resources/AppIcon.svg"
            ],
            resources: [
                .copy("GitStatX/Resources/templates"),
                .copy("GitStatX/Resources/Chart.js")
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("SwiftData"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "GitStatXTests",
            dependencies: ["GitStatX"],
            path: "Tests"
        )
    ]
)
