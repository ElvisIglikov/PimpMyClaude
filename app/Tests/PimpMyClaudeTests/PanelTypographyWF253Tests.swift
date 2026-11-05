import AppKit
@testable import ClaudeAX
import SwiftUI
import XCTest
@testable import PimpMyClaude

/// WF253: данные панели для кадров и проверок — как на снимке Элвиса 17.10.2026 00:05
/// (`Rick/work/pimp-1016-marathon/elvis-panel-sbros-0005.png`) и «злой» набор самых длинных значений.
enum PanelWF253Scenes {
    static let gb: UInt64 = 1_073_741_824

    /// Неделя 93 %, сброс через 6 часов 1 минуту, 5 часов 50 % (сброс через 32 мин), Fable 31 %, 48°, 20.8 ГБ,
    /// карточка «Скачалось обновление Claude 2.42304.0»; токенов на снимке нет.
    static func elvis(now: Date) -> PanelModel {
        let model = base(now: now)
        model.appVersion = "1.10.25"
        model.patch = .installed(version: "2.19675.0", loader: 8)
        model.update = .ready(version: "2.42304.0", question: nil)
        model.limits = ClaudeLimits(at: now, plan: "Max 20x",
                                    fiveHour: .init(used: 50, resetsAt: now.addingTimeInterval(32 * 60)),
                                    weekly: .init(used: 93, resetsAt: now.addingTimeInterval(6 * 3600 + 60)),
                                    fable: .init(used: 31, resetsAt: now.addingTimeInterval(6 * 3600 + 60)),
                                    source: "api")
        model.temperature = temperature(now: now, last: 48)
        model.memory = memory(now: now, usedGB: 20.8, totalGB: 24)
        model.tokenSpark = nil
        finish(model, now: now)
        return model
    }

    /// Самые длинные значения: 100 % везде, сброс недели «23 часа 59 минут» (или `weekReset`), 105°, 127.9 ГБ,
    /// «1,2 млрд», «Claude 2.142304.10», длинный план и размер скачанного.
    static func evil(now: Date, weekReset: TimeInterval = 23 * 3600 + 59 * 60) -> PanelModel {
        let model = base(now: now)
        model.appVersion = "1.10.125"
        model.patch = .installed(version: "2.142304.10", loader: 8)
        model.update = .ready(version: "2.142304.10", question: nil)
        model.readySize = "1,24 ГБ"
        model.limits = ClaudeLimits(at: now, plan: "Team Premium Enterprise",
                                    fiveHour: .init(used: 100, resetsAt: now.addingTimeInterval(4 * 3600 + 59 * 60)),
                                    weekly: .init(used: 100, resetsAt: now.addingTimeInterval(weekReset)),
                                    fable: .init(used: 100, resetsAt: now.addingTimeInterval(weekReset)),
                                    source: "api")
        model.temperature = temperature(now: now, last: 105)
        model.memory = memory(now: now, usedGB: 127.9, totalGB: 128)
        model.tokenSpark = TokenSpark(values: [120, 300, 280, 500, 410, 390, 1200].map { $0 * 1_000_000 }, scanned: now)
        finish(model, now: now)
        return model
    }

    private static func base(now: Date) -> PanelModel {
        let model = PanelModel()
        model.now = now
        model.phase = .open
        model.reduceMotion = true
        model.maxCardHeight = 1600
        model.accent = .graphite
        model.layout = .unfolded
        return model
    }

    private static func finish(_ model: PanelModel, now: Date) {
        model.iconLook = StatusIcon.look(mode: .week, limits: model.limits, patch: model.patch, phase: .idle, now: now)
        model.foldSections()
    }

    /// Температура за 2 ч с рябью, последняя точка — `last` градусов.
    static func temperature(now: Date, last: Double) -> [MacTemperatureSample] {
        (0..<120).map { index -> MacTemperatureSample in
            let ripple = Double((index * 104_729) % 11) - 5
            let value = index == 119 ? last : last - 6 + ripple
            return MacTemperatureSample(at: now.addingTimeInterval(Double(index - 119) * 60),
                                        chipAverage: value, chipMax: value + 20, battery: 31, state: .nominal)
        }
    }

    /// Память за 3 ч, последняя точка — `usedGB` из `totalGB`.
    static func memory(now: Date, usedGB: Double, totalGB: UInt64) -> [MacMemorySample] {
        (0..<180).map { index -> MacMemorySample in
            let ripple = Double((index * 7919) % 13) / 13 - 0.5
            let used = index == 179 ? usedGB : min(usedGB, usedGB - 1.5 + ripple)
            return MacMemorySample(at: now.addingTimeInterval(Double(index - 179) * 60), pressure: 50, level: .normal,
                                   used: UInt64(used * Double(gb)), total: totalGB * gb, swap: 0)
        }
    }

    /// Кадр панели набором шрифтов `type`: снимается всегда, в файл пишется, только когда задан `PMP_SNAPSHOT_DIR`.
    /// `light` — светлый рабочий стол и светлое оформление macOS вокруг (сама панель графитовая всегда, WF177).
    /// Обрезается по высоте панели.
    static func render(_ model: PanelModel, type: PanelTypography, name: String, light: Bool = false) throws {
        let width = PimpPanelController.width + 2 * PimpPanelController.margin
        let desk = light ? Color(.sRGB, red: 0.91, green: 0.91, blue: 0.93) : Color(.sRGB, red: 0.04, green: 0.08, blue: 0.19)
        model.typography = type
        let view = NSHostingView(rootView: ZStack(alignment: .top) {
            desk
            PanelRoot(model: model)
        })
        view.frame = NSRect(x: 0, y: 0, width: width, height: 1400)
        view.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let full = try XCTUnwrap(rep.cgImage)
        let scale = CGFloat(full.width) / width
        let side: CGFloat = 16
        let crop = CGRect(x: (PimpPanelController.margin - side) * scale, y: 0,
                          width: (PimpPanelController.width + 2 * side) * scale,
                          height: min(model.cardHeight + side, 1400) * scale)
        let image = try XCTUnwrap(full.cropping(to: crop))
        guard let dir = ProcessInfo.processInfo.environment["PMP_SNAPSHOT_DIR"] else { return }
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    /// Какой вид выбрала каждая строка блока (`FitLine`) во всей панели набором `type`.
    static func forms(_ model: PanelModel, type: PanelTypography) -> [String: PanelFit] {
        let box = FitBox()
        model.typography = type
        let view = NSHostingView(rootView: PanelRoot(model: model)
            .onPreferenceChange(PanelFitKey.self) { box.forms = $0 })
        view.frame = NSRect(x: 0, y: 0, width: PimpPanelController.width + 2 * PimpPanelController.margin, height: 1400)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        return box.forms
    }
}

final class FitBox {
    var forms: [String: PanelFit] = [:]
}

/// WF253 (слово Элвиса 17.10.2026 00:05: «6 часов 1 минута написано не влезает… переделай»): ни один
/// текст плиток не режется «…» и не вылезает; все наборы шрифтов (с WF255 — семь) заданы на все роли и читаются.
final class PanelTypographyWF253Tests: XCTestCase {
    /// Ширина текста плитки: половинка панели — 130, во всю ширину — 292 (поля карточки по 12).
    private static let half: CGFloat = (PimpPanelController.width - 24 - 8) / 2 - 24
    private static let wide: CGFloat = PimpPanelController.width - 24 - 24

    // MARK: наборы

    func testPresetsCoverEveryRole() {
        let all = PanelTypography.all
        XCTAssertEqual(Set(all.map { $0.number }).count, all.count, "номера наборов разные")
        XCTAssertEqual(Set(all.map { $0.name }).count, all.count, "имена наборов разные")
        XCTAssertEqual(PanelTypography.standard.number, PanelTypography.chosen)
        for type in all {
            XCTAssertEqual(type.roles.count, 7, type.name)
            for role in type.roles {
                // Подписи и пояснения не мельче 11 (книжное 20), проценты-герои — крупнее значений.
                XCTAssertGreaterThanOrEqual(role.size, 11, type.name)
            }
            XCTAssertGreaterThan(type.hero.size, type.value.size, type.name)
            XCTAssertGreaterThan(type.hero.size, type.unit.size, type.name)
        }
        // Наборы и правда разные — шрифтом, кеглем или начертанием героя и подписи.
        let looks = Set(all.map { "\($0.hero.face)-\($0.hero.size)-\($0.hero.weight)-\($0.label.letters)-\($0.label.size)" })
        XCTAssertEqual(looks.count, all.count)
    }

    /// Серое на тёмном — числом (книжное 20): каждая роль каждого набора от 4,5 : 1 к фону плитки.
    func testEveryRoleReadsOnTile() throws {
        // Плитка: подложка панели #1C1C1E и белый 4,5 % поверх.
        let tile = (r: 28 + (255 - 28) * 0.045, g: 28 + (255 - 28) * 0.045, b: 30 + (255 - 30) * 0.045)
        func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
            func channel(_ v: Double) -> Double {
                let c = v / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }
        let back = luminance(tile.r, tile.g, tile.b)
        for type in PanelTypography.all {
            for role in type.roles {
                let color = try XCTUnwrap(NSColor(role.color).usingColorSpace(.sRGB))
                let a = Double(color.alphaComponent)
                let mix = { (front: CGFloat, under: Double) in Double(front) * 255 * a + under * (1 - a) }
                let front = luminance(mix(color.redComponent, tile.r), mix(color.greenComponent, tile.g),
                                      mix(color.blueComponent, tile.b))
                let ratio = (max(front, back) + 0.05) / (min(front, back) + 0.05)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(type.name): \(role)")
            }
        }
    }

    // MARK: короткие записи

    func testShortResetText() {
        let now = Date()
        let short = { (seconds: TimeInterval) in
            PanelShort.left(now.addingTimeInterval(seconds), now: now)?.replacingOccurrences(of: "\u{00A0}", with: " ")
        }
        XCTAssertEqual(short(6 * 3600 + 60), "6 ч 1 мин")
        XCTAssertEqual(short(23 * 3600 + 59 * 60), "23 ч 59 мин")
        XCTAssertEqual(short(6 * 86400 + 23 * 3600 + 59 * 60), "6 дн 23 ч")
        XCTAssertEqual(short(2 * 86400), "2 дн")
        XCTAssertEqual(short(12 * 60), "12 мин")
        XCTAssertEqual(short(20), "< 1 мин")
        XCTAssertNil(PanelShort.left(now.addingTimeInterval(-5), now: now))
        XCTAssertNil(PanelShort.left(nil, now: now))
        // Тот же счёт, что длинная запись полосы «Сброс».
        XCTAssertEqual(StatusIcon.weekStrip(now.addingTimeInterval(6 * 3600 + 60), now: now)?.left, "6 часов 1 минута")
    }

    func testLongLinesBreakOnlyBetweenParts() {
        XCTAssertEqual(PanelShort.keepTogether("сброс через 23 ч 59 мин"), "сброс через 23\u{00A0}ч\u{00A0}59\u{00A0}мин")
        XCTAssertEqual(PanelShort.keepTogether("сброс пт 08:00"), "сброс пт\u{00A0}08:00")
        XCTAssertEqual(PanelShort.keepTogether(" "), " ")
        // Шапка с #10308 не переносится вовсе — одна строка (`Header`), `headerParts` снят.
    }

    // MARK: строка блока без «…»

    /// Вид строки блока в плитке шириной `width` и ширина, которую он занимает.
    /// `reading` — значение показанием (температура и память, WF267), иначе — вторичным значением.
    private func fit(_ type: PanelTypography, width: CGFloat, label: String, value: String, short: String? = nil,
                     chevron: Bool = false, reading: Bool = false) -> (form: PanelFit?, width: CGFloat) {
        let box = FitBox()
        let style = reading ? type.reading : type.value
        let line = FitLine(id: "line", label: label, value: style.text(value), short: short.map { style.text($0) },
                           chevron: chevron)
        let view = NSHostingView(rootView: line.frame(width: width).environment(\.panelType, type)
            .onPreferenceChange(PanelFitKey.self) { box.forms = $0 })
        view.frame = NSRect(x: 0, y: 0, width: width, height: 80)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return (box.forms["line"], measure(type, label: label, value: value, short: short, form: box.forms["line"],
                                            chevron: chevron, style: style))
    }

    /// Замер текста: сколько места просит выбранный вид — подпись, зазор и значение (или каждое своей строкой).
    private func measure(_ type: PanelTypography, label: String, value: String, short: String?, form: PanelFit?,
                         chevron: Bool, style: PanelTextStyle) -> CGFloat {
        func width(_ text: Text) -> CGFloat {
            let host = NSHostingView(rootView: text.fixedSize())
            return host.fittingSize.width
        }
        let mark: CGFloat = chevron ? 8 + width(Text(Image(systemName: "chevron.right")).font(.system(size: 10, weight: .semibold))) : 0
        let name = width(type.label.text(label))
        let full = width(style.text(value))
        let brief = short.map { width(style.text($0)) } ?? full
        switch form {
        case .row, .bare: return name + 8 + 8 + full + mark
        case .short: return name + 8 + 8 + brief + mark
        case .stacked: return max(name, full) + mark
        case .stackedShort: return max(name, brief) + mark
        case .squeezed, nil: return .infinity
        }
    }

    /// «Сброс · 6 часов 1 минута» во всю ширину — строкой; в половинке — «Сброс · 6 ч 1 мин» строкой: полосы
    /// «Сброса» и «Недели» рядом остаются на одной линии. Ни в одном наборе не ужимается и не режется.
    func testResetLineFitsEveryPreset() {
        for type in PanelTypography.all {
            for left in ["6 часов 1 минута", "23 часа 59 минут", "6 дней 23 часа", "меньше минуты"] {
                let wide = fit(type, width: Self.wide, label: "Сброс", value: left, short: "23\u{00A0}ч\u{00A0}59\u{00A0}мин")
                XCTAssertEqual(wide.form, .row, "\(type.name): «\(left)» во всю ширину")
                XCTAssertLessThanOrEqual(wide.width, Self.wide + 0.5, "\(type.name): «\(left)»")
                let half = fit(type, width: Self.half, label: "Сброс", value: left, short: "23\u{00A0}ч\u{00A0}59\u{00A0}мин")
                XCTAssertNotNil(half.form, type.name)
                XCTAssertNotEqual(half.form, .squeezed, "\(type.name): «\(left)» в половинке")
                XCTAssertLessThanOrEqual(half.width, Self.half + 0.5, "\(type.name): «\(left)» — \(String(describing: half.form))")
            }
            // Как у Элвиса на снимке: в половинке — короткой записью в строку.
            let elvis = fit(type, width: Self.half, label: "Сброс", value: "6 часов 1 минута", short: "6\u{00A0}ч\u{00A0}1\u{00A0}мин")
            XCTAssertEqual(elvis.form, .short, type.name)
        }
    }

    /// Строки «Неделя», «Температура», «Память», «Токены» со злыми значениями — в обеих ширинах без ужатия;
    /// градусы и гигабайты — крупным показанием (WF267).
    func testRowTilesWithLongValues() {
        let half: [(label: String, value: String, chevron: Bool)] = [
            ("Неделя", "100\u{00A0}%", false), ("Температура", "105°", true), ("Память", "127.9 ГБ", true),
            ("Токены", "1,2 млрд", true),
        ]
        let wide: [(label: String, value: String, chevron: Bool)] = half + [
            ("Неделя · все модели", "100\u{00A0}%", false), ("Нагрузка на память", "127.9 ГБ", true),
            ("Температура", "батарея 105°", true), ("Токены", "сегодня 1,2 млрд", true),
        ]
        // «батарея » в панели — пояснением, здесь вся строка показанием: проверка строже настоящей.
        let readings: Set<String> = ["Температура", "Память", "Нагрузка на память"]
        for type in PanelTypography.all {
            for (width, rows) in [(Self.half, half), (Self.wide, wide)] {
                for row in rows {
                    let line = fit(type, width: width, label: row.label, value: row.value, chevron: row.chevron,
                                   reading: readings.contains(row.label))
                    XCTAssertNotNil(line.form, "\(type.name): \(row.label)")
                    XCTAssertNotEqual(line.form, .squeezed, "\(type.name): \(row.label) \(row.value) в \(width)")
                    XCTAssertLessThanOrEqual(line.width, width + 0.5, "\(type.name): \(row.label) \(row.value)")
                    if width == Self.wide { XCTAssertEqual(line.form, .row, "\(type.name): \(row.label)") }
                }
            }
        }
    }

    /// Соседу по ряду строка не вошла (`panelStacked`) — эта тоже ставит подпись над значением (выше ростом), а свой
    /// вид сообщает прежним: ряд вернётся в строку, как только сосед снова войдёт.
    func testPairedLineStacksButReportsOwnForm() {
        let type = PanelTypography.standard
        func host(paired: Bool) -> (height: CGFloat, form: PanelFit?) {
            let box = FitBox()
            // «8 ГБ»: строка входит в половинку и у 2.4 (капитель шире), подпись сверху ставит только сосед.
            let line = FitLine(id: "line", label: "Память", value: type.value.text("8 ГБ"), chevron: true)
            let view = NSHostingView(rootView: line.frame(width: Self.half).environment(\.panelType, type)
                .environment(\.panelStacked, paired).onPreferenceChange(PanelFitKey.self) { box.forms = $0 })
            view.frame = NSRect(x: 0, y: 0, width: Self.half, height: 80)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            return (view.fittingSize.height, box.forms["line"])
        }
        let alone = host(paired: false)
        let paired = host(paired: true)
        XCTAssertEqual(alone.form, .row)
        XCTAssertEqual(paired.form, .row, "свой вид — прежний")
        XCTAssertGreaterThan(paired.height, alone.height + 10, "подпись над значением — две строки")
    }

    /// Вся панель: данные Элвиса и злой набор, плитки половинками и все во всю ширину — ни одна строка блока не
    /// ужата, «Сброс» у Элвиса в ★ — короткой записью в строку.
    func testWholePanelNeverSqueezes() {
        let now = Date()
        for type in PanelTypography.all {
            // #10461: «Неделя» и «Сброс» — подпись и крупное значение отдельными строками (как у коллеги), без FitLine.
            let elvis = PanelWF253Scenes.forms(PanelWF253Scenes.elvis(now: now), type: type)
            XCTAssertNil(elvis[PanelWidget.reset.rawValue], type.name)
            XCTAssertNil(elvis[PanelWidget.week.rawValue], type.name)
            for reset in [23 * 3600 + 59 * 60, 6 * 86400 + 23 * 3600 + 59 * 60] as [TimeInterval] {
                let evil = PanelWF253Scenes.evil(now: now, weekReset: reset)
                let forms = PanelWF253Scenes.forms(evil, type: type)
                XCTAssertEqual(Set(forms.keys), ["temperature", "memory", "tokens"], type.name)
                XCTAssertFalse(forms.values.contains(.squeezed), "\(type.name): \(forms)")
                // Все блоки во всю ширину — всё строкой (линию графика строка может отпустить).
                let wide = PanelWF253Scenes.evil(now: now, weekReset: reset)
                wide.layout = PanelWidgetLayout(items: PanelWidgetLayout.unfolded.items.map {
                    PanelWidgetLayout.Item(id: $0.id, wide: true)
                })
                let wideForms = PanelWF253Scenes.forms(wide, type: type)
                XCTAssertTrue(Set(wideForms.values).isSubset(of: [.row, .bare]), "\(type.name): \(wideForms)")
            }
        }
    }

    // MARK: кадры листа 47

    func testSnapshotWF253() throws {
        let now = Date()
        for type in PanelTypography.all {
            let n = type.number
            try PanelWF253Scenes.render(PanelWF253Scenes.elvis(now: now), type: type, name: "\(n)-1-elvis-dark")
            try PanelWF253Scenes.render(PanelWF253Scenes.elvis(now: now), type: type, name: "\(n)-2-elvis-light",
                                        light: true)
            try PanelWF253Scenes.render(PanelWF253Scenes.evil(now: now), type: type, name: "\(n)-3-zloy")
        }
        // ★ злой набор: сброс через 6 дней 23 часа и все блоки во всю ширину.
        let star = PanelTypography.standard
        try PanelWF253Scenes.render(PanelWF253Scenes.evil(now: now, weekReset: 6 * 86400 + 23 * 3600 + 59 * 60),
                                    type: star, name: "\(star.number)-4-zloy-6dn")
        let wide = PanelWF253Scenes.evil(now: now)
        wide.layout = PanelWidgetLayout(items: PanelWidgetLayout.unfolded.items.map {
            PanelWidgetLayout.Item(id: $0.id, wide: true)
        })
        try PanelWF253Scenes.render(wide, type: star, name: "\(star.number)-5-zloy-wide")
    }
}
