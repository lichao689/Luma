// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OfficeWorkoutLogic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OfficeWorkoutLogic", targets: ["OfficeWorkoutLogic"]),
    ],
    targets: [
        .target(
            name: "OfficeWorkoutLogic",
            path: "Sources/OfficeWorkoutLogic"
        ),
        .testTarget(
            name: "OfficeWorkoutLogicTests",
            dependencies: ["OfficeWorkoutLogic"],
            path: "Tests/OfficeWorkoutLogicTests"
        ),
    ]
)
