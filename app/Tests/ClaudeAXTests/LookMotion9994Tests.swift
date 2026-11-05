import XCTest
@testable import ClaudeAX

/// #9994 (слово Элвиса 16.10.2026 19:42): живой фон движется, стоит или лежит простой картинкой; умолчание — стоит.
final class LookMotion9994Tests: XCTestCase {
    func testMotionGoesLastOnlyWithLiveBackgroundAndNotDefault() {
        XCTAssertEqual(Look(aurora: true).commandValue.json, "{\"aurora\":true,\"neon\":false,\"dense\":false}",
                       "«стоит» — умолчание, ключа нет")
        XCTAssertEqual(Look(aurora: true, scheme: "sea", motion: .live).commandValue.json,
                       "{\"aurora\":true,\"neon\":false,\"dense\":false,\"scheme\":\"sea\",\"motion\":\"live\"}")
        XCTAssertEqual(Look(aurora: true, motion: .image).commandValue.json,
                       "{\"aurora\":true,\"neon\":false,\"dense\":false,\"motion\":\"image\"}")
        XCTAssertEqual(Look(dense: true, motion: .live).commandValue.json,
                       "{\"aurora\":false,\"neon\":false,\"dense\":true}", "без живого фона движения в объекте нет")
    }

    func testMissingOrGarbageMotionIsStill() {
        XCTAssertEqual(Look.from(["aurora": true])?.motion, .still)
        XCTAssertEqual(Look.from(["aurora": true, "motion": "spin"])?.motion, .still)
        XCTAssertEqual(Look.from(["aurora": true, "motion": 1])?.motion, .still)
        XCTAssertEqual(Look.from(["aurora": true, "motion": "live"])?.motion, .live)
        XCTAssertEqual(Look.from(["aurora": true, "motion": "image"])?.motion, .image)
        // «Светлячки» сняты (#11211): старая запись у людей — «стоит», крутилки в команду не идут.
        let old = Look.from(["aurora": true, "motion": "fireflies", "flySpeed": 1.2, "flyChaos": 0.8])
        XCTAssertEqual(old?.motion, .still)
        XCTAssertEqual(old?.defaultsValue as NSDictionary?, ["aurora": true] as NSDictionary)
        XCTAssertTrue(Look(motion: .live).isEmpty, "движение — не эффект: пустоту вида не меняет")
    }

    func testMotionSurvivesDefaultsProjectFileAndThemeMap() throws {
        let suite = testSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ThemeStore(defaults: defaults)
        store.setAllLook(Look(aurora: true, scheme: "theme", motion: .image))
        XCTAssertEqual(store.allLook, Look(aurora: true, scheme: "theme", motion: .image))
        store.setAllLook(Look(aurora: true))
        XCTAssertNil(defaults.dictionary(forKey: ThemeStore.lookAllKey)?[Look.motionKey], "умолчание не пишем")

        let settings = ProjectSettings.parse(object: ["look": ["aurora": true, "motion": "live"]])
        guard case .set(let look) = settings.look else { return XCTFail("слой look потерян") }
        XCTAssertEqual(look.motion, .live)

        // window-themes.json: запись страницы хранится как есть, `motion` — последним.
        let raw: [String: Any] = ["motion": "image", "scheme": "sea", "dense": false, "aurora": true, "neon": false]
        XCTAssertEqual(WindowThemeStore.value(from: raw, field: "look")?.json,
                       "{\"aurora\":true,\"neon\":false,\"dense\":false,\"scheme\":\"sea\",\"motion\":\"image\"}")
    }

    func testProjectWindowsTakeMotionFromAllWindowsAndRepaintOnChange() {
        let all = Look(aurora: true, scheme: "theme", motion: .live)
        XCTAssertEqual(ProjectPaint.liveLook(.set(Look(dense: true, motion: .image)), all: all),
                       .set(Look(aurora: true, dense: true, scheme: "theme", motion: .live)))
        XCTAssertEqual(ProjectPaint.liveLook(.set(Look(dense: true, motion: .image)), all: Look()),
                       .set(Look(dense: true)), "живого фона нет — и движения нет")
        var still = all
        still.motion = .still
        XCTAssertNotEqual(ProjectPaint.liveDigest(all), ProjectPaint.liveDigest(still),
                          "сменили движение — окна проекта перекрашиваются")
        XCTAssertEqual(ProjectPaint.liveDigest(Look(motion: .live)), "|live:off")
    }

    func testPanelRowChoices() {
        XCTAssertEqual(PanelColorTiles.motionItems.map { $0.title }, ["Нет", "Движется", "Стоит", "Картинка"])
        XCTAssertEqual(PanelColorTiles.motionItems.map { $0.value }, [nil, .live, .still, .image])
        XCTAssertTrue(PanelColorTiles.motionItems.allSatisfy { !$0.help.isEmpty }, "у каждого сегмента подсказка")
        XCTAssertNil(PanelColorTiles.motionChoice(live: false, motion: .live))
        XCTAssertEqual(PanelColorTiles.motionChoice(live: true, motion: .image), .image)

        // Из «Нет» — живой фон в тонах цвета с выбранным движением, прочие эффекты целы.
        let on = PanelColorTiles.liveLook(Look(dense: true), motion: .image)
        XCTAssertEqual(on, Look(aurora: true, dense: true, scheme: PanelColorTiles.liveScheme, motion: .image))
        // Смена движения при включённом фоне схему из меню окна не трогает.
        XCTAssertEqual(PanelColorTiles.liveLook(Look(aurora: true, scheme: "sea"), motion: .live),
                       Look(aurora: true, scheme: "sea", motion: .live))
        // «Нет» — живой фон снят.
        XCTAssertFalse(PanelColorTiles.liveLook(on, motion: nil).aurora)
        // Новая установка: «Живой» включён и стоит.
        XCTAssertEqual(PanelColorTiles.liveLook(Look(), on: true).motion, .still)
    }
}
