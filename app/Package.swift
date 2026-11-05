// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PimpMyClaude",
    platforms: [.macOS(.v13)],
    targets: [
        // Патчер Claude.app (asar, лоадер, Info.plist, codesign, бэкап/restore), обновление Claude и самого Пимпа,
        // папка MyClaude и запись в неё (`SupportFiles`).
        .target(name: "Patcher", path: "Sources/Patcher"),
        // AX-модуль: меню на жёлтой кнопке, хоткеи, ⌘Q, Расставить/Показать, темы, каналы команд и «Пимп».
        // Видит Patcher (ревизия WF247, С5б): папка MyClaude, её права и слияние claude.css — одной копией там.
        .target(name: "ClaudeAX", dependencies: ["Patcher"], path: "Sources/ClaudeAX"),
        // Мост к CoreBrightness — подсветка клавиатуры, перенесён из NightWolf (#10394) как есть.
        .target(name: "KeyboardBridge", path: "Sources/KeyboardBridge",
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]),
        // Меню-бар приложение (LSUIElement): значок и панель у часов, окно разрешений, уведомления.
        .executableTarget(
            name: "PimpMyClaude",
            dependencies: ["Patcher", "ClaudeAX", "KeyboardBridge"],
            path: "Sources/PimpMyClaude"
        ),
        .testTarget(name: "PatcherTests", dependencies: ["Patcher"], path: "Tests/PatcherTests"),
        .testTarget(name: "ClaudeAXTests", dependencies: ["ClaudeAX", "Patcher"], path: "Tests/ClaudeAXTests"),
        .testTarget(name: "PimpMyClaudeTests", dependencies: ["PimpMyClaude", "ClaudeAX"], path: "Tests/PimpMyClaudeTests"),
    ],
    swiftLanguageVersions: [.v5]
)
