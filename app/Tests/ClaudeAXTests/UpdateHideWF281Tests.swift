import ClaudeAX
import XCTest

/// #10765: карточку «Обновление Claude» скрывают крестиком до следующей версии — скрыта только готовая карточка той же
/// версии; загрузка, установка и сбой видны всегда.
final class UpdateHideWF281Tests: XCTestCase {
    private let version = "1.4758.0"

    func testHidesOnlyReadyCardOfSameVersion() {
        let cards: [PimpPanelText.UpdateBlock] = [
            .ready(version: version, question: nil),
            .busy(version: version, work: "3 Workflow · 4 терминала"),
            .timely(version: version, reason: "Claude закрыт"),
        ]
        for block in cards {
            XCTAssertTrue(PimpPanelText.updateCardHidden(block, hidden: version), "\(block)")
            XCTAssertFalse(PimpPanelText.updateCardHidden(block, hidden: nil), "\(block)")
            XCTAssertFalse(PimpPanelText.updateCardHidden(block, hidden: "1.4000.0"), "\(block)")
        }
    }

    func testNewerVersionBringsCardBack() {
        XCTAssertFalse(PimpPanelText.updateCardHidden(.busy(version: "1.4759.0", work: "2 чата"), hidden: version))
    }

    func testOtherStatesNeverHidden() {
        let others: [PimpPanelText.UpdateBlock] = [
            .none, .ready(version: version, question: "Идут чаты — обновить всё равно?"), .available(version: version, canWrite: true, note: nil), .verifying(version: version, from: nil),
            .snoozed, .installing(version: version, step: 1), .done(version: version), .failed("нет сети"),
        ]
        for block in others { XCTAssertFalse(PimpPanelText.updateCardHidden(block, hidden: version), "\(block)") }
    }
}
