import AppKit

/// Полоса раскладок — первый пункт меню на жёлтой кнопке (план WF21, слово Элвиса 08.09:
/// «раскладку выбираем картинками прямо в меню»). Четыре плитки в порядке макета: «4 в ряд»,
/// «5 в ряд», «5 × 2» и «как сейчас» (лента); мини-схема столбиками, подпись под ней,
/// выбранная — акцентом. ⌥⌘A повторяет последнюю выбранную.
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
    private let onPick: (ArrangeLayout.Mode) -> Void
    private var hovered: Int?
    private var tracking: NSTrackingArea?
    /// Прямоугольники, под которыми сейчас висят подсказки серых плиток: по ним видно, что
    /// они пересчитаны после растяжки вьюхи (#5681).
    private(set) var hintRects: [NSRect] = []

    init(config: MinimizeMenu.MenuConfig) {
        tiles = LayoutPickerView.tiles(mode: config.arrangeMode, fits: config.arrangeFits)
        onPick = config.arrange
        super.init(frame: NSRect(x: 0, y: 0, width: LayoutPickerView.width,
                                 height: LayoutPickerView.height))
        refreshToolTips()
    }

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

    /// Плитки в порядке макета: сетки, потом лента.
    static func tiles(mode: ArrangeLayout.Mode,
                      fits: (ArrangeLayout.Mode) -> Bool) -> [Tile] {
        MenuModel.layoutOrder.map { candidate in
            Tile(mode: candidate, title: MenuModel.layoutTitle(candidate),
                 isEnabled: fits(candidate), isSelected: candidate == mode)
        }
    }

    // MARK: - геометрия

    /// Клетка плитки целиком: картинка и подпись под ней. Полоса стоит по центру пункта.
    func cell(of index: Int) -> NSRect {
        let step = LayoutPickerView.tileSize.width + LayoutPickerView.gap
        let strip = step * CGFloat(tiles.count) - LayoutPickerView.gap
        let height = LayoutPickerView.tileSize.height + LayoutPickerView.captionGap
            + LayoutPickerView.captionHeight
        return NSRect(x: ((bounds.width - strip) / 2).rounded(.down) + CGFloat(index) * step,
                      y: ((bounds.height - height) / 2).rounded(.down),
                      width: LayoutPickerView.tileSize.width, height: height)
    }

    /// Какая плитка под точкой; между плитками — ничья (клик мимо ничего не делает).
    func index(at point: NSPoint) -> Int? {
        tiles.indices.first { cell(of: $0).insetBy(dx: -LayoutPickerView.gap / 2, dy: 0)
            .contains(point) }
    }

    // MARK: - рисование

    override func draw(_ dirtyRect: NSRect) {
        for index in tiles.indices { draw(tiles[index], in: cell(of: index), hovered: hovered == index) }
    }

    private func draw(_ tile: Tile, in cell: NSRect, hovered: Bool) {
        let accent = NSColor.controlAccentColor
        // Подложка клетки: выбранная — акцентом, под курсором — светлее фона.
        let back = NSBezierPath(roundedRect: cell.insetBy(dx: -3, dy: -2), xRadius: 7, yRadius: 7)
        if tile.isSelected {
            accent.withAlphaComponent(0.22).setFill()
            back.fill()
            accent.withAlphaComponent(0.75).setStroke()
            back.lineWidth = 1
            back.stroke()
        } else if hovered && tile.isEnabled {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            back.fill()
        }

        // «Экран» плитки: рамка и внутри столбики ячеек.
        let screen = NSRect(x: cell.minX, y: cell.maxY - LayoutPickerView.tileSize.height,
                            width: cell.width, height: LayoutPickerView.tileSize.height)
        let box = NSBezierPath(roundedRect: screen, xRadius: 5, yRadius: 5)
        NSColor.quaternaryLabelColor.setFill()
        box.fill()
        NSColor.separatorColor.setStroke()
        box.lineWidth = 1
        box.stroke()
        let bars: NSColor = tile.isEnabled ? (tile.isSelected ? accent
                                                              : accent.withAlphaComponent(0.7))
                                           : NSColor.tertiaryLabelColor
        drawBars(in: screen, mode: tile.mode, color: bars)

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let color: NSColor = !tile.isEnabled ? .tertiaryLabelColor
            : (tile.isSelected ? .labelColor : .secondaryLabelColor)
        let caption = NSAttributedString(string: tile.title, attributes: [
            .font: NSFont.systemFont(ofSize: 10,
                                     weight: tile.isSelected ? .semibold : .regular),
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
        caption.draw(in: NSRect(x: cell.minX - LayoutPickerView.gap / 2, y: cell.minY,
                                width: cell.width + LayoutPickerView.gap,
                                height: LayoutPickerView.captionHeight))
    }

    /// Столбики ячеек: у сетки они заданы, у ленты их пять и последний пунктиром —
    /// «сколько окон, столько и ячеек».
    private func drawBars(in screen: NSRect, mode: ArrangeLayout.Mode, color: NSColor) {
        let grid = ArrangeLayout.grid(of: mode) ?? (cols: 5, rows: 1)
        let area = screen.insetBy(dx: 3.5, dy: 3.5)
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

    /// Выбор плитки: серая молчит, остальные закрывают меню и ходом вперёд ставят окна.
    func pick(_ index: Int) {
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
