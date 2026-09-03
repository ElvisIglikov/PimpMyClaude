import Foundation

/// Заглушка скелета. Батч A заменяет содержимое (порт claude-patch/patch-claude.mjs).
public enum Patcher {
    public static let requiredLoaderVersion = 6
    public static let claudeBundleID = "com.anthropic.claudefordesktop"
    public static let supportDirName = "MyClaude" // лоадер v6 уже смотрит сюда — не переименовывать
}
