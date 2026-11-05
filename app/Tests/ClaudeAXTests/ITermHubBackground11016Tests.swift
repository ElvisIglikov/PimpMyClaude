import Foundation
import XCTest
@testable import ClaudeAX

/// #11016: новые вкладки hub iTerm заводит в фоне — Пимп ставит скрытую настройку iTerm, только когда ключа нет.
final class ITermHubBackground11016Tests: XCTestCase {
    private let domain = "com.elvis.pimpmyclaude.test11016"

    private func value() -> CFPropertyList? {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(ITermHub.backgroundKey as CFString, domain as CFString)
    }

    override func tearDown() {
        CFPreferencesSetAppValue(ITermHub.backgroundKey as CFString, nil, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
        super.tearDown()
    }

    func testWritesOnlyWhenKeyIsAbsent() {
        tearDown()
        XCTAssertTrue(ITermHub.ensureBackgroundTabs(domain: domain))
        XCTAssertEqual(value() as? Bool, true)
        XCTAssertFalse(ITermHub.ensureBackgroundTabs(domain: domain), "уже стоит — второй записи нет")
    }

    func testHumanChoiceStays() {
        CFPreferencesSetAppValue(ITermHub.backgroundKey as CFString, kCFBooleanFalse, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
        XCTAssertFalse(ITermHub.ensureBackgroundTabs(domain: domain))
        XCTAssertEqual(value() as? Bool, false)
    }

    func testKeyIsITermsOwn() {
        XCTAssertEqual(ITermHub.backgroundKey, "tmuxWindowsOpenInBackground")
        XCTAssertEqual(ITermHub.bundle, "com.googlecode.iterm2")
    }
}
