// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftPMX",
    products: [
        .library(name: "SwiftPMX", targets: ["SwiftPMX"]),
    ],
    targets: [
        .target(name: "SwiftPMX"),
        .testTarget(name: "SwiftPMXTests", dependencies: ["SwiftPMX"]),
    ]
)
