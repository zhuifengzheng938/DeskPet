// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeskPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DeskPetKit", targets: ["DeskPetKit"]),
        .executable(name: "DeskPet", targets: ["DeskPet"]),
        .executable(name: "DeskPetLauncher", targets: ["DeskPetLauncher"])
    ],
    targets: [
        .target(name: "DeskPetKit"),
        .executableTarget(
            name: "DeskPet",
            dependencies: ["DeskPetKit"]
        ),
        .executableTarget(name: "DeskPetLauncher")
    ]
)
