// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vox",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vox", targets: ["PragueGuideMCP"]),
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
            name: "PragueGuideMCP",
            dependencies: ["VoiceCore"],
            path: "Sources/PragueGuideMCP",
            linkerSettings: [
                .linkedFramework("NaturalLanguage"),
            ]
        ),
    ]
)
