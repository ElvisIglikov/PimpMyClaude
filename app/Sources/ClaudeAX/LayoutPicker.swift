import AppKit

/// Полоса раскладок — первый пункт меню на жёлтой кнопке (план WF21, слово Элвиса 08.09:
/// «раскладку выбираем картинками прямо в меню»). Плитки в порядке макета: «4 в ряд»,
/// «5 в ряд», «5 × 2» и «как сейчас» (лента); мини-схема столбиками, подпись под ней,
/// выбранная — акцентом. ⌥⌘A повторяет последнюю выбранную.
///
/// Слова Элвиса 08.09 16:30 меняют в полосе три вещи:
/// - плитка «как сейчас» рисует НАСТОЯЩЕЕ положение окон, а не пять выдуманных столбиков
///   («"как сейчас" всегда же по-разному», #5798);
/// - плиток столько, сколько имеет смысл при нынешнем числе окон («здесь только сейчас два
///   окна отображается — зачем эти режимы вообще», #5800): негодные не сереют, а не рисуются
///   вовсе, иначе Элвис снова видит четыре варианта на два окна;
/// - последняя клетка — «💾 сохранить», то же действие, что пункт «💾 Сохранить эту
///   раскладку…» в «⋯ Ещё ▸ 🗂 Раскладки ▸» («это же пресеты», #5799).
///
/// Одна вьюха на всю полосу, а не четыре кнопки: `NSMenuItem.view` получает события мыши сам,
/// а подсветку строки AppKit у view-пункта не рисует (та же история у `SliderMenuView`) —
/// наведение ведём сами, `NSTrackingArea` плюс перерисовка.
///
/// Клик: сперва закрывается меню (`cancelTracking`), потом ходом вперёд зовётся обработчик —
/// как у `BlockMenuItem`: замыкание срабатывает внутри цикла `popUp`, а окна должны ехать,
/// когда меню уже закрылось и фокус вернулся Claude.
final class LayoutPickerView: NSView {
    /// Плитка полосы: раскладка, подпись, влезает ли она на этот экран и выбрана ли сейчас.
    struct Tile: Equatable {
        let mode: ArrangeLayout.Mode
        let title: String
        /// Ячейка была бы уже `minWindowWidth` — плитка серая и не нажимается.
        let isEnabled: Bool
        let isSelected: Bool
    }

    /// Полоса не шире меню (`SliderMenuView.width` — та же мерка).
    static let width: CGFloat = SliderMenuView.width
    static let height: CGFloat = 66
    /// Размер картинки; подпись живёт под ней.
    static let tileSize = NSSize(width: 54, height: 40)
    private static let gap: CGFloat = 6
    private static let captionHeight: CGFloat = 14
    private static let captionGap: CGFloat = 2

    let tiles: [Tile]
    /// Как окна стоят прямо сейчас — долями области экрана (`ArrangeLayout.shapes`): их рисует
    /// плитка «как сейчас» (#5798). Пусто (экран не известен, рамок не дали) — плитка рисует
    /// прежнюю схему столбиками.
    let shapes: [CGRect]
    private let onPick: (ArrangeLayout.Mode) -> Void
    private let onSave: () -> Void
    private var hovered: Int?
    private var tracking: NSTrackingArea?
    /// Прямоугольники, под которыми сейчас висят подсказки серых плиток: по ним видно, что
    /// они пересчитаны после растяжки вьюхи (#5681).
    private(set) var hintRects: [NSRect] = []

    init(config: MinimizeMenu.MenuConfig) {
        tiles = LayoutPickerView.tiles(mode: config.arrangeMode, fits: config.arrangeFits,
                                       windows: config.windowFrames.count)
        shapes = config.windowArea.map { ArrangeLayout.shapes(of: config.windowFrames, in: $0) } ?? []
        onPick = config.arrange
        onSave = config.saveLayout
        super.init(frame: NSRect(x: 0, y: 0, width: LayoutPickerView.width,
                                 height: LayoutPickerView.height))
        refreshToolTips()
    }

    /// Клеток в полосе: плитки и «💾 сохранить» последней.
    var cellCount: Int { tiles.count + 1 }
    /// Номер клетки «💾 сохранить».
    var saveIndex: Int { tiles.count }

    /// AppKit тянет вьюху пункта по ширине меню, а прямоугольники подсказок остались бы от
    /// начальных `bounds` — и подсказка серой плитки вылезала бы над соседней (#5681).
    /// Клетки считаются от `bounds`, поэтому подсказки перевешиваем на каждое изменение размера.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshToolTips()
    }

    /// Подсказка только у серых плиток: остальным объяснять нечего.
    private func refreshToolTips() {
        removeAllToolTips()
        hintRects = []
        for index in tiles.indices where !tiles[index].isEnabled {
            let rect = cell(of: index)
            addToolTip(rect, owner: self, userData: nil)
            hintRects.append(rect)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// Плитки в порядке макета: сетки, потом лента. Раскладки, у которых при нынешнем числе
    /// окон часть ячеек осталась бы пустой, в полосу не попадают вовсе (#5800).
    static func tiles(mode: ArrangeLayout.Mode, fits: (ArrangeLayout.Mode) -> Bool,
                      windows: Int) -> [Tile] {
        MenuModel.layoutOrder.filter { ArrangeLayout.suits($0, windows: windows) }.map { candidate in
            Tile(mode: candidate, title: MenuModel.layoutTitle(candidate),
                 isEnabled: fits(candidate), isSelected: candidate == mode)
        }
    }

    // MARK: - геометрия

    /// Ширина клетки: обычно `tileSize.width`, а когда клеток много — ужимаем, чтобы полоса
    /// не вылезла за меню (пять клеток по 54 в 260 не влезают). Считается от постоянной
    /// ширины полосы, а не от `bounds`: AppKit тянет вьюху пункта по ширине меню, и картинки
    /// прыгали бы от того, какие ещё пункты в нём есть.
    static func tileWidth(cells: Int) -> CGFloat {
        guard cells > 1 else { return tileSize.width }
        let room = width - gap * CGFloat(cells - 1)
        return min(tileSize.width, (room / CGFloat(cells)).rounded(.down))
    }

    /// Клетка целиком: картинка и подпись под ней. Полоса стоит по центру пункта.
    func cell(of index: Int) -> NSRect {
        let cellWidth = LayoutPickerView.tileWidth(cells: cellCount)
        let step = cellWidth + LayoutPickerView.gap
        let strip = step * CGFloat(cellCount) - LayoutPickerView.gap
        let height = LayoutPickerView.tileSize.height + LayoutPickerView.captionGap
            + LayoutPickerView.captionHeight
        return NSRect(x: ((bounds.width - strip) / 2).rounded(.down) + CGFloat(index) * step,
                      y: ((bounds.height - height) / 2).rounded(.down),
                      width: cellWidth, height: height)
    }

    /// Какая клетка под точкой; между клетками — ничья (клик мимо ничего не делает).
    func index(at point: NSPoint) -> Int? {
        (0..<cellCount).first { cell(of: $0).insetBy(dx: -LayoutPickerView.gap / 2, dy: 0)
            .contains(point) }
    }

    /// Где на плитке рисовать окно: доли области (0…1, y ВНИЗ, как у AX) → координаты вьюхи
    /// (y вверх). Чистая — её и гоняют тесты.
    static func place(_ shape: CGRect, in area: NSRect) -> NSRect {
        NSRect(x: area.minX + shape.minX * area.width,
               y: area.maxY - shape.maxY * area.height,
               width: shape.width * area.width, height: shape.height * area.height)
    }

    // MARK: - рисование

    override func draw(_ dirtyRect: NSRect) {
        for index in tiles.indices { draw(tiles[index], in: cell(of: index), hovered: hovered == index) }
        drawSave(in: cell(of: saveIndex), hovered: hovered == saveIndex)
    }

    private func draw(_ tile: Tile, in cell: NSRect, hovered: Bool) {
        let accent = NSColor.controlAccentColor
        drawBack(cell, selected: tile.isSelected, hovered: hovered && tile.isEnabled)
        let area = drawBox(in: cell)
        let bars: NSColor = tile.isEnabled ? (tile.isSelected ? accent
                                                              : accent.withAlphaComponent(0.7))
                                           : NSColor.tertiaryLabelColor
        // «Как сейчас» рисует настоящие окна (#5798); схема столбиками остаётся сеткам и той
        // же ленте, когда рамок окон нам не дали.
        if tile.mode == .ribbon && !shapes.isEmpty { drawShapes(in: area, color: bars) }
        else { drawBars(in: area, mode: tile.mode, color: bars) }

        let color: NSColor = !tile.isEnabled ? .tertiaryLabelColor
            : (tile.isSelected ? .labelColor : .secondaryLabelColor)
        drawCaption(tile.title, in: cell, color: color, selected: tile.isSelected)
    }

    /// Клетка «💾 сохранить» (#5799): та же коробка, внутри значок, подпись под ней.
    /// Выбранной она не бывает — это кнопка, а не раскладка.
    private func drawSave(in cell: NSRect, hovered: Bool) {
        drawBack(cell, selected: false, hovered: hovered)
        let area = drawBox(in: cell)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let glyph = NSAttributedString(string: MenuModel.saveLayoutIcon, attributes: [
            .font: NSFont.systemFont(ofSize: 18),
            .paragraphStyle: style,
        ])
        let height = glyph.size().height
        glyph.draw(in: NSRect(x: area.minX, y: area.midY - height / 2,
                              width: area.width, height: height))
        drawCaption(MenuModel.saveLayoutTileTitle, in: cell, color: .secondaryLabelColor,
                    selected: false)
    }

    /// Подложка клетки: выбранная — акцентом, под курсором — светлее фона.
    private func drawBack(_ cell: NSRect, selected: Bool, hovered: Bool) {
        let accent = NSColor.controlAccentColor
        let back = NSBezierPath(roundedRect: cell.insetBy(dx: -3, dy: -2), xRadius: 7, yRadius: 7)
        if selected {
            accent.withAlphaComponent(0.22).setFill()
            back.fill()
            accent.withAlphaComponent(0.75).setStroke()
            back.lineWidth = 1
            back.stroke()
        } else if hovered {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            back.fill()
        }
    }

    /// «Экран» клетки: рамка с заливкой. Отдаёт область внутри неё — в ней рисуется картинка.
    private func drawBox(in cell: NSRect) -> NSRect {
        let screen = NSRect(x: cell.minX, y: cell.maxY - LayoutPickerView.tileSize.height,
                            width: cell.width, height: LayoutPickerView.tileSize.height)
        let box = NSBezierPath(roundedRect: screen, xRadius: 5, yRadius: 5)
        NSColor.quaternaryLabelColor.setFill()
        box.fill()
        NSColor.separatorColor.setStroke()
        box.lineWidth = 1
        box.stroke()
        return screen.insetBy(dx: 3.5, dy: 3.5)
    }

    private func drawCaption(_ text: String, in cell: NSRect, color: NSColor, selected: Bool) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        // Клетка ужалась (полоса из пяти) — вместе с ней и подпись: «как сейчас» в 10 pt в
        // такую клетку не влезает и обрывалась бы многоточием.
        let size: CGFloat = cell.width < LayoutPickerView.tileSize.width ? 9 : 10
        let caption = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: selected ? .semibold : .regular),
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
        caption.draw(in: NSRect(x: cell.minX - LayoutPickerView.gap / 2, y: cell.minY,
                                width: cell.width + LayoutPickerView.gap,
                                height: LayoutPickerView.captionHeight))
    }

    /// Настоящие окна на плитке «как сейчас» (#5798): каждое своим прямоугольником, чуть
    /// поджатым, — стоящие вплотную окна не сливаются в одно пятно.
    private func drawShapes(in area: NSRect, color: NSColor) {
        color.setFill()
        for shape in shapes {
            let rect = LayoutPickerView.place(shape, in: area).insetBy(dx: 0.5, dy: 0.5)
            guard rect.width > 0, rect.height > 0 else { continue }
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    /// Столбики ячеек: у сетки они заданы, у ленты их пять и последний пунктиром —
    /// «сколько окон, столько и ячеек».
    private func drawBars(in area: NSRect, mode: ArrangeLayout.Mode, color: NSColor) {
        let grid = ArrangeLayout.grid(of: mode) ?? (cols: 5, rows: 1)
        let gap: CGFloat = 2
        let width = (area.width - gap * CGFloat(grid.cols - 1)) / CGFloat(grid.cols)
        let height = (area.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
        for row in 0..<grid.rows {
            for col in 0..<grid.cols {
                let bar = NSRect(x: area.minX + CGFloat(col) * (width + gap),
                                 y: area.maxY - height - CGFloat(row) * (height + gap),
                                 width: width, height: height)
                let path = NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5)
                if mode == .ribbon && col == grid.cols - 1 {
                    color.setStroke()
                    path.lineWidth = 1
                    path.setLineDash([2, 2], count: 2, phase: 0)
                    path.stroke()
                } else {
                    color.setFill()
                    path.fill()
                }
            }
        }
    }

    // MARK: - мышь

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseMoved(with event: NSEvent) { hover(event) }
    override func mouseDragged(with event: NSEvent) { hover(event) }
    override func mouseExited(with event: NSEvent) { setHover(nil) }

    /// Нажатие оставляем себе — иначе `mouseUp` до вьюхи не дойдёт.
    override func mouseDown(with event: NSEvent) { hover(event) }

    override func mouseUp(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else { return }
        pick(index)
    }

    private func hover(_ event: NSEvent) {
        setHover(index(at: convert(event.locationInWindow, from: nil)))
    }

    private func setHover(_ index: Int?) {
        guard hovered != index else { return }
        hovered = index
        needsDisplay = true
    }

    /// Выбор клетки: серая плитка молчит, остальные закрывают меню и ходом вперёд ставят
    /// окна; последняя клетка — «💾 сохранить», она тем же ходом спрашивает имя раскладки.
    func pick(_ index: Int) {
        if index == saveIndex {
            enclosingMenuItem?.menu?.cancelTracking()
            DispatchQueue.main.async { [onSave] in onSave() }
            return
        }
        guard tiles.indices.contains(index), tiles[index].isEnabled else { return }
        let mode = tiles[index].mode
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [onPick] in onPick(mode) }
    }
}

extension LayoutPickerView: NSViewToolTipOwner {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        MenuModel.layoutTooSmallHint
    }
}
