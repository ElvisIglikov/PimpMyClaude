// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PimpMyClaude",
    platforms: [.macOS(.v13)],
    targets: [
        // Патчер Claude.app: asar, лоадер, Info.plist, codesign, бэкап/restore. Владелец: батч A.
        .target(name: "Patcher", path: "Sources/Patcher"),
        // AX-модуль: авто-Allow, меню на кнопке «Свернуть», хоткеи, ⌘Q, Расставить/Показать. Владелец: батч B.
        .target(name: "ClaudeAX", path: "Sources/ClaudeAX"),
        // Меню-бар приложение (LSUIElement). Владелец: батч A (волна 1), C (волна 2).
        .executableTarget(
            name: "PimpMyClaude",
            dependencies: ["Patcher", "ClaudeAX"],
            path: "Sources/PimpMyClaude"
        ),
        .testTarget(name: "PatcherTests", dependencies: ["Patcher"], path: "Tests/PatcherTests"),
        .testTarget(name: "ClaudeAXTests", dependencies: ["ClaudeAX"], path: "Tests/ClaudeAXTests"),
    ],
    swiftLanguageVersions: [.v5]
)
