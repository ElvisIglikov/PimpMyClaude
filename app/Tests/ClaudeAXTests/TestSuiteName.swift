import XCTest

/// Утечка plist (31.10.2026, ноут коллеги: 5000 пустых файлов в ~/Library/Preferences): `removePersistentDomain`
/// файл набора не удаляет, а стёртый руками cfprefsd пишет заново при выходе процесса, — имя набора с UUID
/// оставляло по файлу на каждый прогон. Имя теперь постоянное — тест и номер вызова в нём: из прогона в прогон
/// это тот же файл; стирается здесь, до теста, так что прошлый (и упавший) прогон в тест не протекает.
private var suiteCalls: [String: Int] = [:]

extension XCTestCase {
    func testSuiteName() -> String {
        let call = (suiteCalls[name] ?? 0) + 1
        suiteCalls[name] = call
        let test = name.filter { !"-[]".contains($0) }.replacingOccurrences(of: " ", with: ".")
        let suite = "pimp-tests.\(test).\(call)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return suite
    }
}
