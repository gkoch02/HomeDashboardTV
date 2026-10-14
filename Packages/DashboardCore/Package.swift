// swift-tools-version: 5.9
import PackageDescription

// The app's model and logic, kept free of UIKit/SwiftUI so `swift test` runs it on the Mac.
let package = Package(
    name: "DashboardCore",
    platforms: [.tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DashboardCore", targets: ["DashboardCore"]),
    ],
    targets: [
        .target(name: "DashboardCore"),
        .testTarget(
            name: "DashboardCoreTests",
            dependencies: ["DashboardCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
