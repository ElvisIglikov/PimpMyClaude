import AppKit
import ClaudeAX

/// Акцент PMP (WF126, `docs/wf126-spec.md` §5): красит плашку PMP на значке и в панели, кнопки действия и текущую
/// фазу. Хранится id в `UserDefaults["pmpAccent"]`; нет или чужое — фиолетовый. С WF189 (слово Элвиса 09.10 04:00:
/// «цветов побольше… по цветовому кругу эти цвета выставь, чтоб красиво было») — девять, по кругу от красного к
/// розовому, графит последним; жёлтого и голубого нет: жёлтый — «ждёт» и рядом с янтарём, голубой — между бирюзой и синим.
enum PMPAccent: String, CaseIterable {
    case red, orange, amber, green, teal, blue, violet, pink, graphite

    static let key = "pmpAccent"

    static var current: PMPAccent {
        UserDefaults.standard.string(forKey: key).flatMap(PMPAccent.init(rawValue:)) ?? .violet
    }

    /// Имя — только подсказкой по наведению (WF189: «названия цветов не пиши»).
    var name: String {
        switch self {
        case .red: return "Красный"
        case .orange: return "Оранжевый"
        case .amber: return "Янтарь"
        case .green: return "Зелёный"
        case .teal: return "Бирюзовый"
        case .blue: return "Синий"
        case .violet: return "Фиолетовый"
        case .pink: return "Розовый"
        case .graphite: return "Графит"
        }
    }

    var hex: UInt32 {
        switch self {
        case .red: return 0xF0524F
        case .orange: return 0xFB7B30
        case .amber: return 0xF59E0B
        case .green: return 0x5FC48F
        case .teal: return 0x5BC8C0
        case .blue: return 0x7AA2F7
        case .violet: return 0xA98BFA
        case .pink: return 0xF06BB4
        case .graphite: return 0xECECEE
        }
    }

    /// Идущие Workflow в плитках (31.1): цвет PMP; красный, оранжевый, зелёный, бирюзовый и янтарь — белым, чтобы
    /// не спутать с тревогой (красный), «готов» (зелёный) и «ждёт» (жёлтый).
    var runHex: UInt32 { [.red, .orange, .green, .teal, .amber].contains(self) ? 0xECECEE : hex }

    /// Цвет плашки на светлой строке меню (WF193): графит #ECECEE там почти не виден — тёмный графит; бирюза, синий
    /// и фиолетовый — чуть темнее, чтобы вырезанные буквы читались. Остальные — как есть. Панель всегда тёмная.
    var lightBarHex: UInt32 {
        switch self {
        case .graphite: return 0x3A3A3C
        case .teal: return 0x3AAFA7
        case .blue: return 0x5B86EC
        case .violet: return 0x8E6CF2
        default: return hex
        }
    }

    var nsColor: NSColor { Self.fromHex(hex) }

    static func fromHex(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Кисть получает цвет, а не случай: узнаём случай по цвету (sRGB), чужой цвет — без изменений.
    static func onBar(_ color: NSColor, dark: Bool) -> NSColor {
        guard !dark, let rgb = color.usingColorSpace(.sRGB) else { return color }
        let match = allCases.first { accent in
            let c = accent.nsColor
            return abs(c.redComponent - rgb.redComponent) < 0.003 && abs(c.greenComponent - rgb.greenComponent) < 0.003
                && abs(c.blueComponent - rgb.blueComponent) < 0.003
        }
        return match.map { fromHex($0.lightBarHex) } ?? color
    }
}

/// Значок у часов (WF87, `docs/10-choice.md` §1): бейдж «PMP» и число лимита, рисуется кодом.
/// Что рисовать решает `StatusIcon.look` (ClaudeAX, тесты `PanelWF87Tests`); здесь только кисть.
/// С WF126 плашка — цветом акцента PMP.
enum StatusIconArt {
    static let height: CGFloat = 22

    static func foreground(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.85)
    }

    static func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight, digits: Bool = false) -> NSFont {
        let base = digits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                          : NSFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    /// `spin` — угол крутилки в радианах (только при `look.spinner`). `dark: nil` — тема решается в момент рисования
    /// (`NSAppearance.currentDrawing()`): строка меню рисует копии значка на каждом экране своей темой, и картинку
    /// не нужно пересобирать при смене темы (WF138: перерисовка по KVO `effectiveAppearance` зацикливалась — 100 % CPU).
    static func image(_ look: StatusIcon.Look, dark: Bool? = nil, spin: CGFloat = 0, accent: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: width(look), height: height), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let isDark = dark ?? (NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            draw(look, dark: isDark, spin: spin, accent: accent, in: cg)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Шрифт сводки проектов (вид «Проекты», WF129).
    static let summaryFont = roundedFont(12, .semibold, digits: true)

    /// Знаки сводки (WF193, «эмодзи меня бесят», правило №9 — значки одного стиля): эмодзи из `PanelTiles.summary`
    /// на значке рисуются плоскими SF Symbols цветом букв строки меню.
    static let summarySymbols: [Character: String] = ["⏳": "hourglass", "✋": "hand.raised.fill", "✅": "checkmark"]

    /// Сводка картинкой-строкой: текст шрифтом `summaryFont`, эмодзи — вложенные символы того же цвета.
    static func summaryText(_ summary: String, color: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let attrs: [NSAttributedString.Key: Any] = [.font: summaryFont, .foregroundColor: color]
        for char in summary {
            guard let name = summarySymbols[char],
                  let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
                        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))) else {
                out.append(NSAttributedString(string: String(char), attributes: attrs))
                continue
            }
            let attachment = NSTextAttachment()
            attachment.image = symbol
            // По высоте прописных букв, по середине.
            attachment.bounds = NSRect(x: 0, y: (summaryFont.capHeight - symbol.size.height) / 2,
                                       width: symbol.size.width, height: symbol.size.height)
            out.append(NSAttributedString(attachment: attachment))
        }
        return out
    }

    private static func summaryWidth(_ summary: String) -> CGFloat {
        ceil(summaryText(summary, color: .black).size().width)
    }

    /// Ширина картинки: у сводки — по тексту справа от плашки (без плашки — от края, с местом под метку), иначе —
    /// как решил `StatusIcon.look`.
    static func width(_ look: StatusIcon.Look) -> CGFloat {
        guard let summary = look.text else { return look.width }
        let text = summaryWidth(summary)
        if look.badge { return 30 + text + 2 }
        return textLeft + text + 2 + (look.mark == .none ? 0 : 9)
    }

    /// Начало сводки без плашки «PMP» (WF174, «только цифры»).
    static let textLeft: CGFloat = 1

    private static func draw(_ look: StatusIcon.Look, dark: Bool, spin: CGFloat, accent: NSColor, in cg: CGContext) {
        let fg = foreground(dark: dark)
        let accent = PMPAccent.onBar(accent, dark: dark)
        let badge = NSRect(x: 1, y: 4, width: 23, height: 14)
        let pmpFont = roundedFont(8, .heavy)
        let compact = look.mode == .percent
        let contentWidth = look.width - (compact && look.mark != .none ? 10 : 0)
        if compact {
            if look.outlined {
                fg.setStroke()
                let path = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: contentWidth - 2, height: 14),
                                        xRadius: 6, yRadius: 6)
                path.lineWidth = 1.2
                path.stroke()
                text("—", font: roundedFont(13, .semibold, digits: true), color: fg,
                     centerX: contentWidth / 2, baseline: 14.6)
            }
        } else if look.outlined {
            fg.setStroke()
            let path = NSBezierPath(roundedRect: badge.insetBy(dx: 0.6, dy: 0.6), xRadius: 3.6, yRadius: 3.6)
            path.lineWidth = 1.2
            path.stroke()
            text("PMP", font: pmpFont, color: fg, centerX: badge.midX, baseline: 13.9)
        } else if look.badge {
            accent.setFill()
            NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
            cg.saveGState()
            cg.setBlendMode(.destinationOut)
            text("PMP", font: pmpFont, color: .black, centerX: badge.midX, baseline: 13.9)
            cg.restoreGState()
        }

        if look.spinner {
            let center = NSPoint(x: compact ? contentWidth / 2 : 33.2, y: 11)
            let ring = NSBezierPath()
            ring.appendArc(withCenter: center, radius: 4.3, startAngle: 0, endAngle: 360)
            ring.lineWidth = 1.8
            fg.withAlphaComponent(0.28).setStroke()
            ring.stroke()
            let arc = NSBezierPath()
            let start = spin * 180 / .pi
            arc.appendArc(withCenter: center, radius: 4.3, startAngle: start, endAngle: start + 90)
            arc.lineWidth = 1.8
            arc.lineCapStyle = .round
            fg.setStroke()
            arc.stroke()
        } else if look.showsNumber {
            let label = look.number.map { compact ? "\($0)%" : String($0) } ?? "—"
            let box: CGFloat = label.count >= 3 ? 23 : 16
            // Число — цветом строки меню, красной бывает только полоска под ним (#8142: «чересчур это ярко… Перебор»).
            let numberColor = look.number == nil ? fg.withAlphaComponent(0.5) : fg
            text(label, font: roundedFont(13, .semibold, digits: true), color: numberColor, centerX: compact ? contentWidth / 2 : 28 + box / 2,
                 baseline: 14.6)
            if !compact {
                bar(x: 28, y: 17.4, width: box, height: 2, fill: look.number, level: look.level, fg: fg, dark: dark)
            } else if look.underline {
                // «Проценты с полоской» (WF189): полоска под числом, по его ширине — как у «PMP и неделя».
                let wide = NSAttributedString(string: label, attributes: [.font: roundedFont(13, .semibold, digits: true)])
                    .size().width
                bar(x: (contentWidth - wide) / 2, y: 17.4, width: wide, height: 2, fill: look.number, level: look.level,
                    fg: fg, dark: dark)
            }
        } else if let summary = look.text {
            let line = summaryText(summary, color: fg)
            let left: CGFloat = look.badge ? 30 : textLeft
            line.draw(with: NSRect(x: left, y: 14.6 - summaryFont.ascender, width: ceil(line.size().width) + 2,
                                   height: summaryFont.ascender - summaryFont.descender + 2),
                      options: [.usesLineFragmentOrigin])
        } else if !look.bars.isEmpty {
            for (i, spent) in look.bars.enumerated() {
                // Одна полоска («PMP с полоской», WF189) — по середине плашки, три — рядами.
                bar(x: 28, y: look.bars.count == 1 ? 9.5 : [5.5, 9.9, 14.3][min(i, 2)], width: 18,
                    height: look.bars.count == 1 ? 3 : 2.6, fill: spent,
                    level: i < look.barLevels.count ? look.barLevels[i] : .normal, fg: fg, dark: dark)
            }
        }

        // Метка в правом верхнем углу бейджа: точка «патч слетел» сильнее треугольника «скачано».
        var corner = NSPoint(x: compact ? contentWidth + 5 : 23.4, y: 4.6)
        if !compact, !look.badge, let summary = look.text {
            corner.x = textLeft + summaryWidth(summary) + 5
        }
        switch look.mark {
        case .patchLost:
            cut(NSBezierPath(ovalIn: NSRect(x: corner.x - 4.5, y: corner.y - 4.5, width: 9, height: 9)), in: cg)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: corner.x - 3.3, y: corner.y - 3.3, width: 6.6, height: 6.6)).fill()
        case .updateReady:
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: corner.x, y: corner.y - 2.6))
            tri.line(to: NSPoint(x: corner.x + 3.2, y: corner.y + 2.6))
            tri.line(to: NSPoint(x: corner.x - 3.2, y: corner.y + 2.6))
            tri.close()
            tri.lineJoinStyle = .round
            cg.saveGState()
            cg.setBlendMode(.destinationOut)
            NSColor.black.set()
            tri.lineWidth = 2
            tri.stroke()
            tri.fill()
            cg.restoreGState()
            // Цвет акцента PMP (WF126; до того янтарь WF103).
            accent.setFill()
            tri.fill()
        case .none:
            break
        }
    }

    private static func cut(_ path: NSBezierPath, in cg: CGContext) {
        cg.saveGState()
        cg.setBlendMode(.destinationOut)
        NSColor.black.setFill()
        path.fill()
        cg.restoreGState()
    }

    /// `fill` — сколько залить (израсходовано, 0…100), `level` — цвет по остатку.
    private static func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, fill spent: Int?,
                            level: StatusIcon.Level, fg: NSColor, dark: Bool) {
        let radius = height / 2
        fg.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius).fill()
        guard let spent = spent, spent > 0 else { return }
        let fill: NSColor
        switch level {
        case .critical: fill = .systemRed
        case .low: fill = dark ? .systemYellow : .systemOrange
        case .normal: fill = fg
        }
        fill.setFill()
        let w = max(height, width * CGFloat(spent) / 100)
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: height), xRadius: radius, yRadius: radius).fill()
    }

    /// Строка по центру `centerX` с базовой линией `baseline` (координаты перевёрнутые).
    private static func text(_ string: String, font: NSFont, color: NSColor, centerX: CGFloat, baseline: CGFloat) {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        let width = attributed.size().width
        attributed.draw(with: NSRect(x: centerX - width / 2, y: baseline - font.ascender, width: width + 2,
                                     height: font.ascender - font.descender + 2),
                        options: [.usesLineFragmentOrigin])
    }
}

/// Кнопка значка: вид по строке меню, крутилка 10 кадров/с только пока ставится.
/// WF138: тему не слушаем — картинка сама рисуется темой каждой копии в строке меню (раньше KVO `effectiveAppearance`
/// → новая картинка → строка меню перерисовывает копии и ставит им тему → снова KVO: вечный цикл, 100 % CPU).
/// Кадры крутилки — из кэша (`frames`), новая картинка ставится, только когда она другая.
final class StatusIconPainter {
    /// Кадров на оборот; оборот в секунду — частота таймера равна этому числу.
    static let spinFrames = 10

    private weak var button: NSStatusBarButton?
    private var look: StatusIcon.Look?
    private var spinTimer: Timer?
    private var frame = 0
    private var accent = PMPAccent.current.nsColor
    private(set) var frames: [Int: NSImage] = [:]

    init(button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        button.title = ""
    }

    var isSpinning: Bool { spinTimer != nil }

    func apply(_ look: StatusIcon.Look, accent: NSColor) {
        guard look != self.look || accent != self.accent else { return }
        self.look = look
        self.accent = accent
        frames.removeAll()
        if look.spinner, spinTimer == nil {
            let timer = Timer(timeInterval: 1.0 / Double(Self.spinFrames), repeats: true) { [weak self] _ in
                self?.step()
            }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            spinTimer = timer
        } else if !look.spinner {
            spinTimer?.invalidate()
            spinTimer = nil
            frame = 0
        }
        redraw()
        button?.toolTip = look.toolTip
    }

    /// Следующий кадр крутилки (таймер; тесты зовут напрямую).
    func step() {
        frame = (frame + 1) % Self.spinFrames
        redraw()
    }

    /// Картинка кадра: один раз на вид/акцент, дальше из кэша.
    func image(frame index: Int) -> NSImage? {
        guard let look = look else { return nil }
        let key = look.spinner ? index : 0
        if let cached = frames[key] { return cached }
        let spin = -CGFloat(key) * .pi * 2 / CGFloat(Self.spinFrames) // по часовой
        let made = StatusIconArt.image(look, spin: spin, accent: accent)
        frames[key] = made
        return made
    }

    private func redraw() {
        guard let button = button, let image = image(frame: frame) else { return }
        if button.image !== image { button.image = image }
    }
}
