import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// #10704 (снимок Элвиса 23.10.2026 `Rick/work/pokaz-1023/pmp-1355-2.png`; слово: «Давай напишем: память, проц… Видюха и
/// токены»): свёрнутые половинки «Память · Проц · Видюха · Токены» — имена короткие и с числами до 100 % входят целиком
/// любым из семи наборов шрифтов; не вошло («Токены · 826 млн» набором 49.4) — ужимаются все подписи свёрнутых блоков
/// одной долей (`CollapsedScaleKey`), а не одна (раньше `minimumScaleFactor` у длинной «Процессор» делал её мельче
/// «Памяти»); числа — одной ролью `value`, не ужимаются (цвет состояния у памяти, процессора и видеокарты остаётся).
/// Кадры раскладки Элвиса пишутся, только когда задан `PMP_SNAPSHOT_DIR`.
final class PanelTiles10704AppTests: XCTestCase {
    func testShortTitles() {
        XCTAssertEqual([PanelWidget.memory, .cpu, .gpu, .tokens].map { $0.title }, ["Память", "Процессор", "Видюха", "Токены"])
    }

    /// Раскладка Элвиса 23.10: «Память · Проц», «Видюха · Токены» — свёрнутые половинки.
    private static let elvisLayout = #"[{"id":"week","wide":false},{"id":"reset","wide":false},"#
        + #"{"id":"limits","collapsed":true,"wide":false},{"id":"fable","collapsed":true,"wide":false},"#
        + #"{"id":"temperature","collapsed":true,"wide":true},{"id":"memory","collapsed":true,"wide":false},"#
        + #"{"id":"cpu","collapsed":true,"wide":false},{"id":"gpu","collapsed":true,"wide":false},"#
        + #"{"id":"tokens","collapsed":true,"wide":false},{"id":"colors","collapsed":true,"wide":false},"#
        + #"{"id":"workflow","collapsed":true,"wide":true},{"id":"terminals","collapsed":true,"wide":true}]"#

    private func scene(cpu: Double, tokens: Int?) throws -> PanelModel {
        let now = Date()
        let model = PanelWF253Scenes.elvis(now: now)
        model.macLoad = (0..<60).map { MacLoadSample(at: now.addingTimeInterval(Double($0 - 59) * 60), cpu: cpu, gpu: cpu) }
        model.memory = PanelWF253Scenes.memory(now: now, usedGB: 24, totalGB: 24)
        model.tokenSpark = tokens.map { TokenSpark(values: [300_000_000, 280_000_000, 500_000_000, 410_000_000, 390_000_000,
                                                            700_000_000, $0], scanned: now) }
        model.layout = PanelWidgetLayout(items: try JSONDecoder().decode([PanelWidgetLayout.Item].self,
                                                                         from: Data(Self.elvisLayout.utf8)))
        return model
    }

    /// Общая доля подписей свёрнутых блоков (`CollapsedScaleKey`) во всей панели набором `type`.
    private func scale(_ model: PanelModel, type: PanelTypography) -> CGFloat {
        final class Box { var value: CGFloat = -1 }
        let box = Box()
        model.typography = type
        let view = NSHostingView(rootView: PanelRoot(model: model).onPreferenceChange(CollapsedScaleKey.self) { box.value = $0 })
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: 1400)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        return box.value
    }

    /// Короткие имена входят в половинку целиком любым набором — «Память · Видюха» по 100 % подписи не ужимают; «Процессор»
    /// (#10993) общую долю не задаёт.
    func testShortTitlesFitWholeInEveryType() throws {
        let model = try scene(cpu: 100, tokens: nil)
        for type in PanelTypography.all { XCTAssertEqual(scale(model, type: type), 1, type.number) }
    }

    /// «Токены · 826 млн» в половинку набором 49.4 (у Элвиса) целиком не входит: подпись ужимается — и вместе с ней все
    /// подписи свёрнутых блоков одной долей, не одна «ТОКЕНЫ» мельче соседей; числа не ужимаются.
    func testTokensShrinkAllLabelsTogether() throws {
        let model = try scene(cpu: 66, tokens: 826_000_000)
        let shared = scale(model, type: .giant)
        XCTAssertLessThan(shared, 1)
        XCTAssertGreaterThanOrEqual(shared, 0.75, "ужато не больше нужного")
        XCTAssertEqual(scale(try scene(cpu: 66, tokens: nil), type: .giant), 1, "без токенов — снова целиком")
    }

    /// Кадр: раскладка Элвиса (23.10) — «Память · Проц», «Видюха · Токены» свёрнутыми половинками, наборы 49.4 и 2.4.
    func testSnapshot10704() throws {
        let model = try scene(cpu: 66, tokens: 826_000_000)
        for type in [PanelTypography.giant, .standard] {
            try PanelWF253Scenes.render(model, type: type, name: "10704-tiles-\(type.number)")
        }
    }
}
