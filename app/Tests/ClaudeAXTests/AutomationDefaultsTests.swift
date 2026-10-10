import CoreFoundation
import XCTest
@testable import ClaudeAX

final class AutomationDefaultsTests: XCTestCase {
    func testCombinedStartupFreshStaysOffOnSecondLaunchAfterV8Marker() throws {
        let suite = "automation-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let marker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: marker) }
        func startup() {
            let previous = defaults.persistentDomain(forName: suite) ?? [:]
            let oldMarker = try? Data(contentsOf: marker)
            AutomationDefaults.migrate(defaults, values: previous, legacyPatched: AutomationDefaults.legacyMarker(oldMarker))
        }
        startup()
        XCTAssertTrue(defaults.bool(forKey: AutomationDefaults.downloadQuestionKey))
        for key in [AutomationDefaults.allowKey, ClaudeUpdateMenu.autoDownloadKey, AutomationDefaults.continueKey, AutomationDefaults.mirrorsKey] {
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)
        }
        try JSONSerialization.data(withJSONObject: ["version": "2.0", "headerSHA256": "abc", "loaderVersion": 8]).write(to: marker)
        startup()
        for key in [AutomationDefaults.allowKey, ClaudeUpdateMenu.autoDownloadKey, AutomationDefaults.continueKey, AutomationDefaults.mirrorsKey] {
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)
        }
        XCTAssertFalse(defaults.bool(forKey: AutomationDefaults.continueMigrationKey))
        defaults.removePersistentDomain(forName: suite)
        startup() // A v8 marker already exists, but no prior application settings do.
        for key in [AutomationDefaults.allowKey, ClaudeUpdateMenu.autoDownloadKey, AutomationDefaults.continueKey, AutomationDefaults.mirrorsKey] {
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)
        }
    }

    func testLegacyPreservesExplicitChoicesAndMigratesMissingOnesOnce() throws {
        let suite = "automation-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ClaudeUpdateMenu.autoDownloadKey)
        defaults.set(false, forKey: AutomationDefaults.allowKey)
        let previous = defaults.persistentDomain(forName: suite) ?? [:]
        AutomationDefaults.migrate(defaults, values: previous, legacyPatched: false)
        XCTAssertFalse(defaults.bool(forKey: ClaudeUpdateMenu.autoDownloadKey))
        XCTAssertFalse(defaults.bool(forKey: AutomationDefaults.allowKey), "прежнее значение не трогаем")
        XCTAssertTrue(defaults.bool(forKey: AutomationDefaults.continueKey))
        XCTAssertTrue(defaults.bool(forKey: AutomationDefaults.continueMigrationKey))
        XCTAssertTrue(defaults.bool(forKey: AutomationDefaults.mirrorsKey))
        XCTAssertFalse(defaults.bool(forKey: AutomationDefaults.downloadQuestionKey))
        defaults.set(false, forKey: AutomationDefaults.continueKey)
        defaults.set(false, forKey: AutomationDefaults.continueMigrationKey)
        AutomationDefaults.migrate(defaults, values: defaults.persistentDomain(forName: suite) ?? [:], legacyPatched: true)
        XCTAssertFalse(defaults.bool(forKey: AutomationDefaults.continueKey))
        XCTAssertFalse(defaults.bool(forKey: AutomationDefaults.continueMigrationKey))
        XCTAssertFalse(AutomationDefaults.legacyMarker(try JSONSerialization.data(withJSONObject: ["loaderVersion": 7])))
        XCTAssertTrue(AutomationDefaults.legacyMarker(try JSONSerialization.data(withJSONObject: ["version": "2", "headerSHA256": "a", "loaderVersion": 7])))
        XCTAssertFalse(AutomationDefaults.legacyMarker(try JSONSerialization.data(withJSONObject: ["version": "2", "headerSHA256": "a", "loaderVersion": 8])))
    }

    func testAutoContinueMigrationSurvivesConfigureAndNewGenerationWithoutForcingPageOff() throws {
        let sender = AutoContinueSwitch()
        sender.configure(on: true, migrate: true)
        let now = Date()
        var sent: [[String: Any]] = []
        func send(_ fields: [(key: String, value: CommandValue)]) -> Bool {
            let json = CommandChannel.payload(action: "auto-continue", fields: fields)
            sent.append((try! JSONSerialization.jsonObject(with: Data(json.utf8))) as! [String: Any])
            return true
        }
        sender.tick(titles: ["A"], at: now, send: send)
        sender.configure(on: true, migrate: true) // Other settings reapplied: keep preservation intent.
        sender.beginGeneration()
        sender.tick(titles: ["A"], at: now.addingTimeInterval(1), send: send)
        XCTAssertEqual(sent.count, 2)
        XCTAssertTrue(sent.allSatisfy { $0["on"] as? Bool == true && $0["migrate"] as? Bool == true })
        var page = ChatPage(kind: .main, chat: "local_a", title: "A", store: "ok", at: now)
        XCTAssertNil(AutoContinueSwitch.reported([page], at: now))
        page.autoContinue = false
        XCTAssertEqual(AutoContinueSwitch.reported([page], at: now), false, "Page off remains the reported fact even though migration policy is on")
        sender.configure(on: false, migrate: false) // Explicit native choice.
        sender.tick(titles: ["A"], at: now.addingTimeInterval(2), send: send)
        XCTAssertEqual(sent.last?["on"] as? Bool, false)
        XCTAssertNil(sent.last?["migrate"])
    }

    func testNewPolicyKeysAloneNeverProveLegacy() throws {
        let suite = "automation-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in [ClaudeUpdateMenu.autoDownloadKey, AutomationDefaults.continueKey, AutomationDefaults.mirrorsKey, "unknownPreference"] {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(false, forKey: key)
            let previous = defaults.persistentDomain(forName: suite) ?? [:]
            XCTAssertFalse(AutomationDefaults.isLegacy(values: previous, patched: false))
            AutomationDefaults.migrate(defaults, values: previous, legacyPatched: false)
            for policy in [AutomationDefaults.allowKey, ClaudeUpdateMenu.autoDownloadKey, AutomationDefaults.continueKey, AutomationDefaults.mirrorsKey] {
                XCTAssertEqual(defaults.object(forKey: policy) as? Bool, false)
            }
        }
        for key in ["setupWindowSeen", "themeByWindow", "minimizeMenuEnabled"] {
            XCTAssertTrue(AutomationDefaults.isLegacy(values: [key: false], patched: false))
        }
    }

    func testMissingAutoAllowMigratesOnlyUninitializedLegacyInstallations() throws {
        let suite = "automation-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cases: [(values: [String: Any], patched: Bool, expected: Bool)] = [
            ([:], false, false),
            (["unknownPreference": true], false, false),
            (["setupWindowSeen": true], false, true),
            (["minimizeMenuEnabled": false], false, true),
            ([:], true, true),
            ([AutomationDefaults.initializedKey: true], false, false),
            ([AutomationDefaults.initializedKey: true, "setupWindowSeen": true, "minimizeMenuEnabled": true], false, false),
            ([AutomationDefaults.initializedKey: true, "setupWindowSeen": true], true, false),
            ([AutomationDefaults.initializedKey: false, "setupWindowSeen": true], true, false)
        ]
        for item in cases {
            defaults.setPersistentDomain(item.values, forName: suite)
            AutomationDefaults.migrate(defaults, values: item.values, legacyPatched: item.patched)
            XCTAssertEqual(defaults.object(forKey: AutomationDefaults.allowKey) as? Bool, item.expected, "\(item.values)")
            // После первого запуска появляются и другие приметы установки, но выбор не меняется.
            defaults.set(true, forKey: "loginItemConfigured")
            AutomationDefaults.migrate(defaults, values: defaults.persistentDomain(forName: suite) ?? [:], legacyPatched: true)
            XCTAssertEqual(defaults.object(forKey: AutomationDefaults.allowKey) as? Bool, item.expected)
        }
    }

    func testAutoAllowPreservesExplicitBooleansBeforeAndAfterInitialization() throws {
        let suite = "automation-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for initialized in [false, true] {
            for on in [false, true] {
                var values: [String: Any] = [AutomationDefaults.allowKey: on]
                if initialized { values[AutomationDefaults.initializedKey] = true }
                defaults.setPersistentDomain(values, forName: suite)
                AutomationDefaults.migrate(defaults, values: defaults.persistentDomain(forName: suite) ?? [:], legacyPatched: false)
                XCTAssertEqual(defaults.object(forKey: AutomationDefaults.allowKey) as? Bool, on)
                defaults.set(!on, forKey: AutomationDefaults.allowKey) // Новый ручной выбор.
                AutomationDefaults.migrate(defaults, values: defaults.persistentDomain(forName: suite) ?? [:], legacyPatched: true)
                XCTAssertEqual(defaults.object(forKey: AutomationDefaults.allowKey) as? Bool, !on)
            }
        }
    }

    func testMalformedAutoAllowIsStoredAsFalseEvenAfterInitialization() throws {
        let suite = "automation-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let malformed: [Any] = ["true", "false", "YES", 1, 0, 1.0, [true], ["on": true]]
        for initialized in [false, true] {
            for bad in malformed {
                var values: [String: Any] = [AutomationDefaults.allowKey: bad, "setupWindowSeen": true]
                if initialized { values[AutomationDefaults.initializedKey] = true }
                defaults.setPersistentDomain(values, forName: suite)
                AutomationDefaults.migrate(defaults, values: defaults.persistentDomain(forName: suite) ?? [:], legacyPatched: true)
                let stored = try XCTUnwrap(defaults.object(forKey: AutomationDefaults.allowKey) as? NSNumber)
                XCTAssertEqual(CFGetTypeID(stored), CFBooleanGetTypeID(), "\(bad) должен стать Bool")
                XCTAssertFalse(stored.boolValue)
                AutomationDefaults.migrate(defaults, values: defaults.persistentDomain(forName: suite) ?? [:], legacyPatched: true)
                XCTAssertFalse(defaults.bool(forKey: AutomationDefaults.allowKey))
            }
        }
    }

    func testReturningAutoAllowDoesNotRemigrateOtherP2Settings() throws {
        let suite = "automation-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let previous: [String: Any] = [
            AutomationDefaults.initializedKey: true, "setupWindowSeen": true, "minimizeMenuEnabled": true,
            AutomationDefaults.continueKey: false, AutomationDefaults.continueMigrationKey: true,
            ClaudeUpdateMenu.autoDownloadKey: false, AutomationDefaults.mirrorsKey: true,
            AutomationDefaults.downloadQuestionKey: true, "blockQuitEnabled": false,
            SendDelaySetting.key: ["on": false, "seconds": 3]
        ]
        defaults.setPersistentDomain(previous, forName: suite)
        AutomationDefaults.migrate(defaults, values: defaults.persistentDomain(forName: suite) ?? [:], legacyPatched: true)
        var expected = previous
        expected[AutomationDefaults.allowKey] = false
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, expected as NSDictionary)
        AutomationDefaults.migrate(defaults, values: defaults.persistentDomain(forName: suite) ?? [:], legacyPatched: true)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, expected as NSDictionary)
    }
}
