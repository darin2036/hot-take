// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RelaytakeMac",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Relaytake", targets: ["Relaytake"]),
        .library(name: "RelaytakeCore", targets: ["RelaytakeCore"]),
    ],
    dependencies: [
        // On-device speech recognition: the system's engines, language models, custom vocabulary and the
        // offline guard. Depends on nothing but system frameworks (no third-party code). It began in the
        // Plainspoken dictation app and is kept here as its own package so both can use it.
        .package(path: "Packages/PlainspokenSpeech"),
    ],
    targets: [
        // Pure logic (caption formatting, file naming, prompts). No system-framework capture code.
        .target(name: "RelaytakeCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Relaytake",
            dependencies: [
                "RelaytakeCore",
                .product(name: "PlainspokenSpeech", package: "PlainspokenSpeech"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "RelaytakeCoreTests", dependencies: ["RelaytakeCore"]),
    ]
)
