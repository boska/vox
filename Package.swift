// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vox",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vox", targets: ["VoxMCP"]),
        .library(name: "VoiceCore", targets: ["VoiceCore"]),
    ],
    targets: [
        .target(
            name: "VoiceCore",
            path: "Sources/VoiceCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
            ]
        ),
        .executableTarget(
            name: "VoxMCP",
            dependencies: ["VoiceCore"],
            path: "Sources/VoxMCP",
            linkerSettings: [
                .linkedFramework("NaturalLanguage"),
            ]
        ),
    ]
)
