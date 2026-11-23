// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RelaytakeMac",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Relaytake", targets: ["Relaytake"]),
        .library(name: "RelaytakeCore", targets: ["RelaytakeCore"]),
        .executable(name: "hottake", targets: ["hottake"]),
    ],
    dependencies: [
        // On-device speech recognition: the system's engines, language models, custom vocabulary and the
        // offline guard. Depends on nothing but system frameworks (no third-party code). It began in the
        // Plainspoken dictation app and is kept here as its own package so both can use it.
        .package(path: "Packages/PlainspokenSpeech"),
        // The on-device voice for voiceovers (Kokoro, run with Apple's MLX on the GPU). Both are pinned exactly: a newer MLX or Kokoro
        // port can change how audio sounds or stop building, so an update is a deliberate change with its own check by ear.
        // They are linked into the app only; `RelaytakeCore` and `hottake` stay free of third-party code.
        .package(url: "https://github.com/mlalma/kokoro-ios.git", exact: "1.0.11"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
    ],
    targets: [
        // Pure logic (caption formatting, file naming, prompts). No system-framework capture code.
        .target(name: "RelaytakeCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Relaytake",
            dependencies: [
                "RelaytakeCore",
                .product(name: "PlainspokenSpeech", package: "PlainspokenSpeech"),
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLX", package: "mlx-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The command an agent runs to drive the recorder, and an MCP server over stdio. Talks to the app through a private socket.
        .executableTarget(name: "hottake", dependencies: ["RelaytakeCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "RelaytakeCoreTests", dependencies: ["RelaytakeCore"]),
    ]
)
