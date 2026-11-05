import AppKit
@testable import ClaudeAX
import XCTest
@testable import PimpMyClaude

/// #9823: запасной путь обновления Claude — «Скачать с claude.ai» и «копировать». Ссылка одна на всех, в буфер ложится
/// ровно она; под гонкой загрузки строка встаёт, только когда загрузка тянется дольше 3 мин или упала. Кадры
/// состояний — `UpdateCardWF234SnapshotTests/testSnapshotSiteDownload9823`.
final class SiteDownload9823AppTests: XCTestCase {
    private func lane(_ id: String, _ state: ClaudeUpdateMenu.LaneState) -> ClaudeUpdateMenu.Lane {
        ClaudeUpdateMenu.Lane(id: id, title: id, bytes: 40_000_000, total: 380_000_000, bytesPerSec: 2_000_000,
                              state: state)
    }

    private func race(_ states: [ClaudeUpdateMenu.LaneState]) -> ClaudeUpdateMenu.Race {
        ClaudeUpdateMenu.Race(version: "2.31226.1",
                              lanes: states.enumerated().map { lane("lane\($0.offset)", $0.element) })
    }

    func testLinkIsTheDownloadPage() {
        XCTAssertEqual(PimpPanelText.claudeDownloadURL, "https://claude.ai/download")
        XCTAssertEqual("https://" + PimpPanelText.claudeDownloadShort, PimpPanelText.claudeDownloadURL,
                       "видимая ссылка — та же, что ляжет в буфер")
        XCTAssertEqual(PimpPanelText.siteDownloadTitle, "Скачать с claude.ai")
        XCTAssertFalse(PimpPanelText.siteDownloadTitle.contains("Пимп"))
    }

    /// «Копировать» кладёт ровно ссылку и затирает прежнее содержимое. Буфер — свой, не общий буфер человека.
    func testCopyPutsExactlyTheURL() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("pmp-test-9823-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("прежнее", forType: .string)
        XCTAssertTrue(DownloadFromSiteRow.copyLink(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "https://claude.ai/download")
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(DownloadFromSiteRow.copiedFor, 1.5)
    }

    /// Обычная загрузка — без строки; дольше 3 мин или все дорожки сошли — строка есть.
    func testRowUnderRaceOnlyWhenLongOrFallen() {
        XCTAssertEqual(PimpPanelText.siteDownloadAfter, 180)
        let going = race([.leading, .running, .dropped("медленно")])
        XCTAssertFalse(PimpPanelText.siteDownloadShown(going, elapsed: 0))
        XCTAssertFalse(PimpPanelText.siteDownloadShown(going, elapsed: 179))
        XCTAssertTrue(PimpPanelText.siteDownloadShown(going, elapsed: 180))
        XCTAssertTrue(PimpPanelText.siteDownloadShown(going, elapsed: 600))
        XCTAssertFalse(PimpPanelText.siteDownloadShown(race([]), elapsed: 5), "гонка только началась — дорожек нет")
        XCTAssertTrue(PimpPanelText.siteDownloadShown(race([.failed("нет сети"), .dropped("медленно")]), elapsed: 20),
                      "все дорожки сошли — загрузка упала")
        XCTAssertFalse(PimpPanelText.siteDownloadShown(race([.failed("нет сети"), .running]), elapsed: 20))
    }
}
