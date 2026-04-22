// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirTerm",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AirTerm", targets: ["AirTerm"]),
    ],
    targets: [
        .executableTarget(
            name: "AirTerm",
            path: "AirTerm"
        ),
        .testTarget(
            name: "AirTermTests",
            dependencies: ["AirTerm"]
        ),
    ]
)
