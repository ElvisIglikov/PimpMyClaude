import AppKit
import ClaudeAX
import SwiftUI

// MARK: «Температура»

/// Температура Мака (#8898, `docs/25.html` раздел 4): свёрнуто — строка «Температура · линия за 3 ч · 54°»,
/// нажал — график за 3 часа, наведи — градусы на тот момент. Чип, без него — батарея (`MacTemperature`).
struct TemperatureView: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent
    @State private var hover = false
    @Environment(\.panelNarrow) private var narrow
    /// Блоки сетки — свернуть вместе с соседом по ряду (#10993).
    @Environment(\.widgetVisible) private var visible
    @Environment(\.panelType) private var type

    var body: some View {
        let history = model.temperature
        let last = history.last
        let now = last?.value.map(MacTemperature.degrees) ?? "—"
        // Градусы — цветом состояния, как у PimpTray (#10308); данных нет — прочерк цветом показания.
        let tone: Color? = last?.value == nil ? nil : last.map { chartColor(MacTemperature.health($0), good: accent) }
        VStack(alignment: .leading, spacing: 8) {
            // Строка названия — свернуть блок в строку раскладки (файл 53, 4.3); шеврон — у названия.
            Button { model.toggleRow(PanelWidget.temperature.rawValue, visible: visible) } label: {
                // В половинке — зазоры уже, раскрытая — только градусы (WF214: с «чип » заголовок резался); откуда
                // градусы, сказано подписью под графиком. Не входит — линия уходит, потом градусы под подписью (WF253).
                // Градусы — показанием, крупнее значений (WF267).
                let source = model.temperatureOpen && !narrow ? (last?.isChip == true ? "чип " : "батарея ") : ""
                FitLine(id: PanelWidget.temperature.rawValue, label: "Температура",
                        value: type.note.text(source) + type.reading.text(now, color: tone),
                        spacing: narrow ? 5 : 8) {
                    if !model.temperatureOpen && !narrow {
                        TemperatureSpark(history: history).sparkFill()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .onHover { hover = $0 }
            .handCursor()
            .accessibilityLabel("Температура")
            .accessibilityValue(now)
            if model.temperatureOpen {
                TemperatureChart(history: history, domain: model.chartDomain, left: model.chartLeft)
                    .frame(height: ChartFrame.height)
                    .transition(.opacity)
                let caption = MacTemperature.caption(history)
                if !caption.isEmpty {
                    Text(caption).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                ChartTips(title: TemperatureTipsText.title, tips: TemperatureTipsText.tips,
                          link: TemperatureTipsText.standURL.map { (TemperatureTipsText.linkTitle, $0) })
                    .transition(.opacity)
            }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.03 : 0)))
        .card()
    }
}

// MARK: «Нагрузка на память»

/// Нагрузка на память (#9082, WF164, `docs/31.html` 31.5; WF177 — #9197) — как температура: свёрнуто — «Память · линия
/// за 3 ч · 6,3 ГБ»; нажал — график за 3 ч по оси «0 · 4 · 8 ГБ» (вся память Мака), наведи — «20:07 · 6,3 ГБ».
/// С WF242 (слово Элвиса 11.10.2026: «должен быть серый график просто тоже. Но там, где нагрузка была повышенная,
/// должно быть просто красным такие участки… Когда своп начинает использоваться») линия серая, как у температуры,
/// красным — участки, где своп рос или держался высоко; с #9818 зелёная, когда всё хорошо, жёлтая и красная по
/// `MacMemory.health`. Под графиком — короткие советы и
/// кнопка «Анализ памяти»: поручение из файла ложится в поле ввода окна Claude, отправляет человек сам.
struct MemoryView: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent
    @State private var hover = false
    @Environment(\.panelNarrow) private var narrow
    /// Блоки сетки — свернуть вместе с соседом по ряду (#10993).
    @Environment(\.widgetVisible) private var visible
    @Environment(\.panelType) private var type

    var body: some View {
        let history = model.memory
        let now = MacMemory.nowText(history)
        // Гигабайты — цветом состояния памяти, как у PimpTray (#10308).
        let tone = MacMemory.health(history).last.map { chartColor($0, good: accent) }
        VStack(alignment: .leading, spacing: 8) {
            Button { model.toggleRow(PanelWidget.memory.rawValue, visible: visible) } label: {
                // Гигабайты — показанием, как градусы у температуры (WF267).
                FitLine(id: PanelWidget.memory.rawValue, label: narrow ? "Память" : "Нагрузка на память",
                        value: type.reading.text(now, color: tone), spacing: narrow ? 5 : 8) {
                    if !model.memoryOpen && !narrow { MemorySpark(history: history).sparkFill() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .onHover { hover = $0 }
            .handCursor()
            .help(MacMemory.help(history))
            .accessibilityLabel("Нагрузка на память")
            .accessibilityValue(MacMemory.help(history))
            if model.memoryOpen {
                MemoryChart(history: history, domain: model.chartDomain, left: model.chartLeft)
                    .frame(height: ChartFrame.height)
                    .transition(.opacity)
                let caption = MacMemory.captionParts(history)
                if !caption.word.isEmpty || !caption.rest.isEmpty {
                    (Text(caption.word).foregroundColor(chartColor(MacMemory.health(history).last ?? .good, good: accent))
                        + Text(caption.word.isEmpty || caption.rest.isEmpty ? "" : " · ")
                        + Text(caption.rest).foregroundColor(PanelColor.sub))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                // #11620: кто съел память — причина видна, а не угадывается.
                if let eaters = MemoryEaters.text(model.memoryEaters) {
                    Text(eaters).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                MemoryTips(model: model).transition(.opacity)
            }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.03 : 0)))
        .card()
    }
}

/// Как остудить Мак (#9818; #10206, слово Элвиса 18.10.2026: «Тупые советы… Отстойные советы, убери их. Используй
/// подставку с охлаждением. Мы используем подставку с вентилятором. Например, такую. И ссылку на мою подставку через
/// реферальную программу давай дадим. Подставка смогла снизить температуру до 42°C»). Один совет и ссылка; ссылки
/// ещё нет — строки «Например, такая» нет. «У нас Мак остыл до 42°» снято (#10994, слово Элвиса 27.10: «не надо писать
/// 40 это у нас просто подставка для вентилятора»).
enum TemperatureTipsText {
    static let title = "Как остудить Мак"
    static let tips = [
        "Подставка с вентилятором",
    ]
    static let linkTitle = "Например, такая"
    /// Реферальная ссылка на подставку Элвиса — пришлёт Рик (#10206).
    static let standURL: URL? = nil
}

/// Советы по памяти и «Анализ памяти» (WF242; слово Элвиса 11.10.2026: «там, где нагрузка на память, там надо советы
/// давать… на одной странице информация очень компактно… нажимаешь анализ памяти, у тебя в Claude Code вставляется…
/// человек Enter нажимает»). Четыре строки и одна кнопка — без простыни.
enum MemoryTipsText {
    static let title = "Как освободить память"
    static let tips = [
        "Закрой лишние вкладки браузера",
        "HTML и фото — в PimpViewer, не в браузере",
        "Закрой ненужные мессенджеры и программы",
        "Проверь фоновые программы в строке меню",
    ]
    static let button = "Анализ памяти"
    static let caption = "Вставит поручение в поле Claude — жми Enter"
    static let edit = "Изменить текст"
}

/// Советы под графиком — один вид у температуры и памяти: волосок, заголовок (подпись набора, WF267), строки с точкой.
private struct ChartTips: View {
    let title: String
    let tips: [String]
    /// Ссылка под советами: подпись и адрес (подставка, #10206).
    var link: (String, URL)?
    @Environment(\.panelType) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(PanelColor.frame).frame(height: 1)
            type.label.text(title).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("·").font(.system(size: 11)).foregroundColor(PanelColor.sub)
                        Text(tip).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let (label, url) = link {
                    LinkButton(title: label) { NSWorkspace.shared.open(url) }.handCursor().padding(.leading, 11)
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct MemoryTips: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChartTips(title: MemoryTipsText.title, tips: MemoryTipsText.tips)
            HStack(alignment: .center, spacing: 10) {
                SmallButton(title: MemoryTipsText.button, primary: false) { model.actions.memoryAnalysis() }
                    .handCursor()
                    .help("Поручение из файла ложится в поле ввода окна Claude. Отправляешь сам.")
                Spacer(minLength: 0)
                FooterLink(title: MemoryTipsText.edit) { model.actions.editMemoryPrompt() }
                    .help("Открыть файл поручения — поправь под себя")
            }
            .padding(.top, 4)
            Text(model.memoryStarterNote ?? MemoryTipsText.caption).font(.system(size: 11))
                .foregroundColor(model.memoryStarterNote == nil ? PanelColor.sub : PanelColor.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Линия в строке во всю свободную ширину между подписью и значением (слово Элвиса 22.10.2026: «график широкий
/// должен быть… чтоб они не впритык были… две буквы Р… слева-справа»): поле с каждой стороны — ещё 12 pt к
/// промежутку строки 8, около двух «Р» подписи; меньше 56 pt — строка уходит в вид без линии, как раньше.
extension View {
    func sparkFill(height: CGFloat = 16) -> some View {
        frame(minWidth: 56, idealWidth: 56, maxWidth: .infinity, minHeight: height, maxHeight: height)
            .padding(.horizontal, 12)
    }
}

/// Линия за 3 ч в свёрнутой строке во всю ширину (слово Элвиса 22.10.2026: «график широкий должен быть»):
/// у температуры, памяти, процессора и видеокарты; у прочих блоков — nil.
@ViewBuilder func collapsedSpark(_ widget: PanelWidget, model: PanelModel) -> some View {
    switch widget {
    case .temperature: TemperatureSpark(history: model.temperature).sparkFill()
    case .memory: MemorySpark(history: model.memory).sparkFill()
    case .cpu: LoadSpark(history: model.macLoad, kind: .cpu).sparkFill()
    case .gpu: LoadSpark(history: model.macLoad, kind: .gpu).sparkFill()
    default: EmptyView()
    }
}

/// Цвет состояния (#9818): всё хорошо — акцент `good` (слово 03.11.2026, меняется вместе с акцентом; см. `PanelColor.good`), жёлтый, красный —
/// как «Давление памяти» в Мониторинге системы.
func chartColor(_ health: MacHealth, good: Color) -> Color {
    switch health {
    case .good: return PanelColor.good(good)
    case .warn: return PanelColor.warn
    case .bad: return PanelColor.bad
    }
}

/// Линия за 3 ч в свёрнутой строке: занятое (доля всей памяти), свой масштаб по мин–макс; цвет — состояние памяти
/// (`MacMemory.health`, #9818); сплошная: сон Мака не рвёт её (`sparkLine`).
private struct MemorySpark: View {
    let history: [MacMemorySample]
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        Canvas { context, size in
            let values = history.map { (MacMemory.fraction($0) ?? 0) * 100 }
            guard let low = values.min(), let high = values.max() else { return }
            let range = max(high - low, 10)
            let mid = (high + low) / 2
            let line = sparkLine(history.map { $0.at }, gap: MacMemory.gap, step: MacMemory.interval, width: size.width)
            let points = chartPoints(segments: line.segments, values: values,
                                     passes: ChartFrame.sparkPasses) { index, value in
                CGPoint(x: line.x[index],
                        y: size.height - 1.5 - CGFloat((value - (mid - range / 2)) / range) * (size.height - 3))
            }
            let health = MacMemory.health(history)
            for segment in line.segments {
                for piece in chartPieces(segment, points: points, health: health) {
                    context.stroke(piece.line, with: .color(chartColor(piece.health, good: accent)),
                                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// График за 3 ч (31.5; WF177 — #9197; WF242): шкала «0 · 4 · 8 ГБ» от всей памяти Мака, высота — занятое, часы
/// внизу, «сейчас» справа; линия плавная цветом состояния (#9818: зелёная — всё хорошо, жёлтая и красная с лёгкой
/// заливкой — где своп), наведение — крест, точка и «20:07 · 6,3 ГБ · в свопе 1,2 ГБ». Поля и ось времени — общие
/// с графиком температуры (`ChartFrame`, `ChartDomain`, левое поле `left` — по самой широкой подписи обоих).
private struct MemoryChart: View {
    let history: [MacMemorySample]
    let domain: ChartDomain?
    var left: CGFloat = ChartFrame.left
    @State private var hovered: Int?
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        GeometryReader { proxy in
            let x1 = proxy.size.width - ChartFrame.right
            let span = domain ?? ChartDomain(first: history.first?.at ?? Date(), last: history.last?.at ?? Date())
            let y: (Double) -> CGFloat = { fraction in
                ChartFrame.bottom - CGFloat(fraction) * (ChartFrame.bottom - ChartFrame.top)
            }
            let segments = MacMemory.segments(history)
            let points = chartPoints(segments: segments, values: history.map { MacMemory.fraction($0) ?? 0 }) { index, value in
                CGPoint(x: span.x(history[index].at, from: left, to: x1), y: y(value))
            }
            let health = MacMemory.health(history)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for tick in MacMemory.axis(total: history.last?.total ?? 0) {
                        chartGridLine(&context, y: y(tick.fraction), left: left, x1: x1, label: tick.label)
                    }
                    chartHours(&context, span: span, left: left, x1: x1)
                    for segment in segments where segment.count > 1 { // одиночная точка у сна — не «точка, разрыв, линия»
                        for piece in chartPieces(segment, points: points, health: health) {
                            chartStroke(&context, piece, good: accent)
                        }
                    }
                    if let last = history.indices.last {
                        chartDot(&context, at: points[last], color: chartColor(health[last], good: accent))
                    }
                    if let index = hovered, history.indices.contains(index) {
                        chartCross(&context, at: points[index], accent: accent)
                    }
                }
                if let index = hovered, history.indices.contains(index), let value = MacMemory.amount(history[index]) {
                    let swap = MacMemory.swapText(history[index]).map { " · " + $0 } ?? ""
                    ChartBubble(text: "\(chartClock.string(from: history[index].at)) · \(value)\(swap)",
                                x: points[index].x, x1: x1)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hovered = span.nearest(history.map { $0.at }, x: location.x, from: left, to: x1)
                case .ended:
                    hovered = nil
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Нагрузка на память за 3 часа")
        .accessibilityValue(MacMemory.caption(history))
    }
}

// MARK: «Процессор» и «Видеокарта» (#10308)

/// Плитка нагрузки, как `LoadTile` у PimpTray: подпись слева, процент справа цветом состояния, шеврон; раскрыта — график
/// за 3 ч (линия, заливка, точка на конце) и подпись «за 3 ч: 12–68 %»; свёрнутая во всю ширину — линия за 3 ч, как у
/// температуры. Каждая раскрывается сама и встаёт своим рядом (файл 53, раздел 4).
struct LoadView: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent
    let kind: MacLoad.Kind
    @State private var hover = false
    @Environment(\.panelNarrow) private var narrow
    /// Блоки сетки — свернуть вместе с соседом по ряду (#10993).
    @Environment(\.widgetVisible) private var visible
    @Environment(\.panelType) private var type

    private var widget: PanelWidget { kind == .cpu ? .cpu : .gpu }

    var body: some View {
        let history = model.macLoad
        let value = history.last?.value(kind)
        let text = value.map(MacLoad.percentText) ?? "—"
        VStack(alignment: .leading, spacing: 8) {
            Button { model.toggleRow(widget.rawValue, visible: visible) } label: {
                FitLine(id: widget.rawValue, label: widget.title,
                        value: type.reading.text(text, color: value.map { chartColor(MacLoad.health($0), good: accent) }),
                        spacing: narrow ? 5 : 8) {
                    if !model.opened(widget) && !narrow { LoadSpark(history: history, kind: kind).sparkFill() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .onHover { hover = $0 }
            .handCursor()
            .help(MacLoad.help(history, kind))
            .accessibilityLabel(widget.title)
            .accessibilityValue(text)
            if model.opened(widget) { opened(history) }
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.03 : 0)))
        .card()
    }

    @ViewBuilder private func opened(_ history: [MacLoadSample]) -> some View {
        LoadChart(history: history, kind: kind)
            .frame(height: LoadChart.height)
            .transition(.opacity)
        let caption = MacLoad.caption(history, kind)
        if !caption.isEmpty {
            Text(caption).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }
}

/// Линия нагрузки за 3 ч в свёрнутой строке во всю ширину: свой масштаб по мин–макс (не уже 10 %), цвет — порог
/// нагрузки; сплошная (`sparkLine`).
private struct LoadSpark: View {
    let history: [MacLoadSample]
    let kind: MacLoad.Kind
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        Canvas { context, size in drawLoadSpark(&context, size: size, series: MacLoad.series(history, kind), good: accent) }
            .accessibilityHidden(true)
    }
}

private func drawLoadSpark(_ context: inout GraphicsContext, size: CGSize, series: [(at: Date, value: Double)], good: Color) {
    let values: [Double] = series.map { $0.value }
    guard let low = values.min(), let high = values.max() else { return }
    let range: Double = max(high - low, 10)
    let base: Double = (high + low) / 2 - range / 2
    let line = sparkLine(series.map { $0.at }, gap: MacLoad.gap, step: MacLoad.interval, width: size.width)
    let place: (Int, Double) -> CGPoint = { index, value in
        let y = size.height - 1.5 - CGFloat((value - base) / range) * (size.height - 3)
        return CGPoint(x: line.x[index], y: y)
    }
    let points = chartPoints(segments: line.segments, values: values, passes: ChartFrame.sparkPasses, place: place)
    let health: [MacHealth] = values.map(MacLoad.health)
    for segment in line.segments {
        for piece in chartPieces(segment, points: points, health: health) {
            context.stroke(piece.line, with: .color(chartColor(piece.health, good: good)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

/// График нагрузки за 3 ч, как у PimpTray: шкала 0…100 % без подписей (поле — волосок внизу), линия цветом порога с
/// заливкой до низа и точка «сейчас» на конце. Короткая история растягивается на всю ширину.
private struct LoadChart: View {
    static let height: CGFloat = 56
    static let top: CGFloat = 4
    static let bottom: CGFloat = 52
    let history: [MacLoadSample]
    let kind: MacLoad.Kind
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        Canvas { context, size in drawLoadChart(&context, size: size, series: MacLoad.series(history, kind), good: accent) }
            .accessibilityElement()
            .accessibilityLabel(kind == .cpu ? "Процессор за 3 часа" : "Видеокарта за 3 часа")
            .accessibilityValue(MacLoad.caption(history, kind))
    }
}

private func drawLoadChart(_ context: inout GraphicsContext, size: CGSize, series: [(at: Date, value: Double)], good: Color) {
    var base = Path()
    base.move(to: CGPoint(x: 0, y: LoadChart.bottom))
    base.addLine(to: CGPoint(x: size.width, y: LoadChart.bottom))
    context.stroke(base, with: .color(PanelColor.frame), lineWidth: 1)
    guard let last = series.indices.last else { return }
    let values: [Double] = series.map { $0.value }
    let first = series.first?.at, end = series.last?.at
    let x1: CGFloat = size.width - 4
    let place: (Int, Double) -> CGPoint = { index, value in
        let share = CGFloat(min(100, max(0, value)) / 100)
        let x = chartX(series[index].at, first: first, last: end, from: 3, to: x1)
        return CGPoint(x: x, y: LoadChart.bottom - share * (LoadChart.bottom - LoadChart.top))
    }
    let segments = MacLoad.segments(series.map { $0.at })
    let points = chartPoints(segments: segments, values: values, place: place)
    let health: [MacHealth] = values.map(MacLoad.health)
    for segment in segments where segment.count > 1 {
        for piece in chartPieces(segment, points: points, health: health) {
            chartStroke(&context, piece, good: good, bottom: LoadChart.bottom)
        }
    }
    chartDot(&context, at: points[last], color: chartColor(health[last], good: good))
}

// MARK: «Токены»

/// Слова плитки «Токены» (WF187, #9250, слово Элвиса 09.10 03:35: «там же просто можно „944 млн“ написать, а у тебя
/// многоточие… что этот маленький график значит?»): подпись под линией и подсказка по наведению.
enum TokensTileText {
    static let sparkCaption = "7 дней"
    static let sparkHelp = "Токены по дням за 7 дней, справа — сегодня"

    static func help(_ spark: TokenSpark?, collected: String) -> String {
        let tail = collected.isEmpty ? "" : " · " + collected
        if spark?.isEmpty != false { return "За 7 дней токенов нет: копилку Rick/data/tokens-daily.json пополняет Рик" + tail }
        if spark?.today == nil { return "Сегодня Рик ещё не собирал токены" + tail }
        return sparkHelp + tail
    }

    /// #11167 (WF298): в половинке линия в строку не входит — раскрытая плитка была пустой («274 млн» и «›»).
    /// Там неделя по дням идёт под строкой, из того же `tokenSpark`, что у окна «Токены»; пусто за неделю — нет.
    static func weekBelow(_ spark: TokenSpark?, narrow: Bool) -> Bool { narrow && spark?.isEmpty == false }
}

/// Плитка «Токены» (WF157, #9149; WF170, #9179): «Токены · линия общего расхода за 7 дней · сегодня N»; нажал —
/// окно с графиком рядом. День, который Рик ещё не собрал, — «—», а не «0». WF187 (#9250): число всегда целиком
/// («944 млн», «1,2 млрд») — ужимается подпись «Токены», а не число; под линией мелко «7 дней», сегодня — точкой.
struct TokensTile: View {
    @ObservedObject var model: PanelModel
    @State private var hover = false
    @Environment(\.panelNarrow) private var narrow
    @Environment(\.panelType) private var type

    var body: some View {
        let spark = model.tokenSpark
        let today = spark?.todayText ?? "—"
        let collected = TokenStats.scannedText(spark?.scanned, now: Date())
        Button { model.openTokens() } label: {
            // WF177: «нет данных» и «не собрано» — словами и тихо, число — ярко. «7 дней» — кеглем пояснений
            // (WF253: было 9). Не входит — линия уходит, потом число под подписью; «…» нет.
            let quiet = spark?.today == nil || spark?.isEmpty != false
            VStack(alignment: .leading, spacing: 6) {
                FitLine(id: PanelWidget.tokens.rawValue, label: "Токены",
                        value: type.note.text(narrow || spark?.isEmpty != false ? "" : "сегодня ")
                            + type.value.text(today, color: quiet ? PanelColor.sub : nil),
                        chevron: true, spacing: narrow ? 5 : 8) {
                    if !narrow && spark?.isEmpty == false {
                        VStack(spacing: 0) {
                            TokensSpark(values: spark?.values ?? []).frame(minWidth: 56, idealWidth: 56, maxWidth: .infinity,
                                                                           minHeight: 14, maxHeight: 14)
                            type.note.text(TokensTileText.sparkCaption).fixedSize()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, -4)
                        .help(TokensTileText.sparkHelp)
                    }
                }
                if TokensTileText.weekBelow(spark, narrow: narrow) {
                    VStack(spacing: 2) {
                        TokensSpark(values: spark?.values ?? []).frame(maxWidth: .infinity).frame(height: 28)
                        type.note.text(TokensTileText.sparkCaption).fixedSize()
                    }
                    .help(TokensTileText.sparkHelp)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { hover = $0 }
        .handCursor()
        .help(TokensTileText.help(spark, collected: collected))
        .accessibilityLabel("Токены")
        .accessibilityValue("сегодня " + today)
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.03 : 0)))
        .card()
    }
}

/// Плавная линия общего расхода за 7 дней с заливкой цветом PMP, сегодня — точкой справа; шкала от нуля по
/// максимуму недели. Несобранный день (nil) не рисуется — линия кончается на последнем собранном.
private struct TokensSpark: View {
    let values: [Int?]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let top = values.compactMap({ $0 }).max(), top > 0 else { return }
            let accent = PanelColor.hex(PMPAccent.current.hex)
            // Поля 4 pt со всех сторон — ореол сегодняшней точки не обрезается.
            let step = (size.width - 8) / CGFloat(values.count - 1)
            let points = values.enumerated().compactMap { index, value in
                value.map { CGPoint(x: 4 + CGFloat(index) * step,
                                    y: size.height - 4 - CGFloat($0) / CGFloat(top) * (size.height - 8)) }
            }
            guard let first = points.first, let last = points.last else { return }
            var line = Path()
            line.move(to: first)
            for index in points.indices.dropFirst() {
                let from = points[index - 1], to = points[index]
                let middle = (from.x + to.x) / 2
                line.addCurve(to: to, control1: CGPoint(x: middle, y: from.y), control2: CGPoint(x: middle, y: to.y))
            }
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: size.height))
            area.addLine(to: CGPoint(x: first.x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [accent.opacity(0.35), accent.opacity(0)]),
                                                     startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            // Сегодня — выделенной точкой с ореолом (WF187): справа — сегодняшний день.
            if values.last ?? nil != nil {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)),
                             with: .color(accent.opacity(0.28)))
                context.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(accent))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: общее графиков температуры и памяти (WF242)

/// Поля графиков — одни на оба: слева место подписям шкалы («16 ГБ», «100°»), справа — точке «сейчас». Правые края,
/// сетка и подписи часов двух графиков стоят друг под другом (слово Элвиса 11.10.2026: «у них выравнивания нету двух
/// графиков… чтоб они справа сходились»).
enum ChartFrame {
    /// Левое поле по умолчанию; подпись шире («128 ГБ») — поле шире у ОБОИХ графиков (`left(labels:)`, #9818).
    static let left: CGFloat = 40
    /// Зазор от подписи шкалы до сетки.
    static let labelGap: CGFloat = 6

    /// Общее левое поле двух графиков: самая широкая подпись шкалы обоих и зазор, не меньше `left` — поля графиков
    /// начинаются на одной линии при любой ширине подписей («100°» и «16 ГБ», «128 ГБ» на большом Маке).
    static func left(labels: [String]) -> CGFloat {
        let widest = labels.map { monoWidth($0, size: 10) }.max() ?? 0
        return max(left, ceil(widest) + labelGap)
    }
    static let right: CGFloat = 8
    static let top: CGFloat = 10
    static let bottom: CGFloat = 104
    static let hours: CGFloat = 120
    static let height: CGFloat = 132
    static let lineWidth: CGFloat = 1.5
    /// Линия в свёрнутой строке — 56 pt на те же 3 ч: минута там треть пикселя, сглаживание втрое шире.
    static let sparkPasses = 16
}

/// Общая ось времени двух графиков: от первой точки до последней.
struct ChartDomain: Equatable {
    let first: Date
    let last: Date

    /// X момента: первая точка — левый край, последняя — правый; одна точка — справа.
    func x(_ at: Date, from x0: CGFloat, to x1: CGFloat) -> CGFloat {
        chartX(at, first: first, last: last, from: x0, to: x1)
    }

    /// Ближайшая по времени точка к X курсора; курсор заметно мимо графика или точек нет — nil.
    func nearest(_ dates: [Date], x: CGFloat, from x0: CGFloat, to x1: CGFloat) -> Int? {
        let fraction = Double((x - x0) / max(1, x1 - x0))
        guard (-0.02...1.02).contains(fraction), !dates.isEmpty else { return nil }
        let target = first.addingTimeInterval(last.timeIntervalSince(first) * min(1, max(0, fraction)))
        return dates.indices.min { abs(dates[$0].timeIntervalSince(target)) < abs(dates[$1].timeIntervalSince(target)) }
    }
}

private func chartX(_ at: Date, first: Date?, last: Date?, from x0: CGFloat, to x1: CGFloat) -> CGFloat {
    guard let first = first, let last = last else { return x1 }
    let span = last.timeIntervalSince(first)
    guard span > 0 else { return x1 }
    return x0 + CGFloat(at.timeIntervalSince(first) / span) * (x1 - x0)
}

/// Линия свёрнутой строки (температура, память, процессор, видеокарта): один кусок без разрывов, X — по времени без
/// сна (`ChartCurve.awakeFractions`), поля по 1 pt.
private func sparkLine(_ dates: [Date], gap: TimeInterval, step: TimeInterval, width: CGFloat) -> (segments: [[Int]], x: [CGFloat]) {
    let x = ChartCurve.awakeFractions(dates, gap: gap, step: step).map { 1 + CGFloat($0) * (width - 2) }
    return (dates.isEmpty ? [] : [Array(dates.indices)], x)
}

/// Точки линии по всем чтениям: значения сглаживаются внутри каждого куска без разрыва (`ChartCurve.smoothed`) —
/// края куска и его крайние значения остаются как есть.
private func chartPoints(segments: [[Int]], values: [Double], passes: Int = ChartCurve.passes,
                         place: (Int, Double) -> CGPoint) -> [CGPoint] {
    var points = values.indices.map { place($0, values[$0]) }
    for segment in segments where segment.count > 2 {
        let smooth = ChartCurve.smoothed(segment.map { values[$0] }, passes: passes)
        for (offset, index) in segment.enumerated() { points[index] = place(index, smooth[offset]) }
    }
    return points
}

/// Плавная линия куска, порезанная по цвету: отрезок цвета своей правой точки (`health`); соседние отрезки одного
/// цвета идут одним путём. Кривая — монотонный сплайн (`ChartCurve.controls`): за точки не вылетает. Одна точка — кружок.
private func chartPieces(_ segment: [Int], points: [CGPoint], health: [MacHealth])
    -> [(line: Path, health: MacHealth, from: CGPoint, to: CGPoint)] {
    guard let first = segment.first else { return [] }
    let at = { (index: Int) in health.indices.contains(index) ? health[index] : .good }
    guard segment.count > 1 else {
        let dot = points[first]
        return [(Path(ellipseIn: CGRect(x: dot.x - 1, y: dot.y - 1, width: 2, height: 2)), at(first), dot, dot)]
    }
    let run = segment.map { points[$0] }
    let controls = ChartCurve.controls(run)
    var pieces: [(line: Path, health: MacHealth, from: CGPoint, to: CGPoint)] = []
    for offset in controls.indices {
        let hot = at(segment[offset + 1])
        if var piece = pieces.last, piece.health == hot {
            piece.line.addCurve(to: run[offset + 1], control1: controls[offset].c1, control2: controls[offset].c2)
            piece.to = run[offset + 1]
            pieces[pieces.count - 1] = piece
        } else {
            var line = Path()
            line.move(to: run[offset])
            line.addCurve(to: run[offset + 1], control1: controls[offset].c1, control2: controls[offset].c2)
            pieces.append((line, hot, run[offset], run[offset + 1]))
        }
    }
    return pieces
}

/// Кусок линии цветом состояния с заливкой до низа поля `bottom` (#10308, как у PimpTray): под цветом «хорошо» — едва заметной,
/// под жёлтым и красным — заметнее, чтобы участок читался сразу (#9818).
private func chartStroke(_ context: inout GraphicsContext, _ piece: (line: Path, health: MacHealth, from: CGPoint, to: CGPoint),
                         good: Color, bottom: CGFloat = ChartFrame.bottom) {
    let color = chartColor(piece.health, good: good)
    if piece.to.x > piece.from.x {
        var fill = piece.line
        fill.addLine(to: CGPoint(x: piece.to.x, y: bottom))
        fill.addLine(to: CGPoint(x: piece.from.x, y: bottom))
        fill.closeSubpath()
        context.fill(fill, with: .color(color.opacity(piece.health == .good ? 0.06 : 0.12)))
    }
    context.stroke(piece.line, with: .color(color),
                   style: StrokeStyle(lineWidth: ChartFrame.lineWidth, lineCap: .round, lineJoin: .round))
}

private let chartMono = Font.system(size: 10, design: .monospaced)

private func chartGridLine(_ context: inout GraphicsContext, y: CGFloat, left: CGFloat, x1: CGFloat, label: String) {
    var line = Path()
    line.move(to: CGPoint(x: left, y: y))
    line.addLine(to: CGPoint(x: x1, y: y))
    context.stroke(line, with: .color(PanelColor.frame), lineWidth: 1)
    context.draw(Text(label).font(chartMono).foregroundColor(PanelColor.sub),
                 at: CGPoint(x: left - ChartFrame.labelGap, y: y), anchor: .trailing)
}

private func chartHours(_ context: inout GraphicsContext, span: ChartDomain, left: CGFloat, x1: CGFloat) {
    for label in chartHourLabels(first: span.first, last: span.last, left: left, x1: x1) {
        context.draw(Text(label.text).font(chartMono).foregroundColor(PanelColor.sub),
                     at: CGPoint(x: label.x, y: ChartFrame.hours), anchor: label.anchor)
    }
}

/// Точка «сейчас» на правом краю.
private func chartDot(_ context: inout GraphicsContext, at dot: CGPoint, color: Color) {
    context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .color(color))
}

/// Наведение: вертикаль и точка на линии.
private func chartCross(_ context: inout GraphicsContext, at dot: CGPoint, accent: Color) {
    var cross = Path()
    cross.move(to: CGPoint(x: dot.x, y: ChartFrame.top))
    cross.addLine(to: CGPoint(x: dot.x, y: ChartFrame.bottom))
    context.stroke(cross, with: .color(PanelColor.text.opacity(0.35)), lineWidth: 1)
    let ring = Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8))
    context.fill(ring, with: .color(accent))
    context.stroke(ring, with: .color(PanelColor.panel), lineWidth: 2)
}

/// Ширина строки моноширинным шрифтом — по числу знаков, без раскладки CoreText (#10207): `NSString.size(withAttributes:)`
/// в `body` уронил Пимп 18.10 22:15 сразу после пробуждения Мака («attempt to insert nil object» в CoreText при подмене
/// шрифта для русских букв). Русские буквы идут запасным шрифтом чуть шире — для места подписи этого хватает.
func monoWidth(_ text: String, size: CGFloat) -> CGFloat {
    CGFloat(text.count) * NSFont.monospacedSystemFont(ofSize: size, weight: .regular).maximumAdvancement.width
}

/// Подпись точки под курсором — над графиком, не выходит за его края.
private struct ChartBubble: View {
    let text: String
    let x: CGFloat
    let x1: CGFloat

    var body: some View {
        let half = monoWidth(text, size: 11) / 2 + 7
        Text(text).font(.system(size: 11, design: .monospaced)).foregroundColor(PanelColor.text)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(PanelColor.hex(0x2E2E31)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(PanelColor.frame, lineWidth: 1))
            .fixedSize()
            .position(x: x1 - half < half ? x1 / 2 : min(max(x, half), x1 - half), y: 9)
            .allowsHitTesting(false)
    }
}

/// Линия за 3 часа в свёрнутой строке: свой масштаб по мин–макс, плавная, цветом нагрева по macOS (#9818); сплошная:
/// сон Мака её не рвёт (`sparkLine`).
private struct TemperatureSpark: View {
    let history: [MacTemperatureSample]
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        Canvas { context, size in
            let values = history.map { $0.value ?? 0 }
            guard let low = values.min(), let high = values.max() else { return }
            let range = max(high - low, 4)
            let mid = (high + low) / 2
            let line = sparkLine(history.map { $0.at }, gap: MacTemperature.gap, step: MacTemperature.interval,
                                 width: size.width)
            let points = chartPoints(segments: line.segments, values: values, passes: ChartFrame.sparkPasses) { index, value in
                CGPoint(x: line.x[index],
                        y: size.height - 1.5 - CGFloat((value - (mid - range / 2)) / range) * (size.height - 3))
            }
            let health = MacTemperature.health(history)
            for segment in line.segments {
                for piece in chartPieces(segment, points: points, health: health) {
                    context.stroke(piece.line, with: .color(chartColor(piece.health, good: accent)),
                                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// График за 3 часа (кадр 4.2; WF242 — плавной линией): шкала по 20°, часы внизу, «сейчас» справа; наведение — крест,
/// точка и «00:40 · 61°»; цвет линии — нагрев по macOS (#9818). Поля и ось времени — общие с графиком памяти
/// (`ChartFrame`, `ChartDomain`, левое поле `left`).
private struct TemperatureChart: View {
    let history: [MacTemperatureSample]
    let domain: ChartDomain?
    var left: CGFloat = ChartFrame.left
    @State private var hovered: Int?
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        GeometryReader { proxy in
            let x1 = proxy.size.width - ChartFrame.right
            let span = domain ?? ChartDomain(first: history.first?.at ?? Date(), last: history.last?.at ?? Date())
            let scale = MacTemperature.scale(history)
            let y: (Double) -> CGFloat = { value in
                ChartFrame.bottom - CGFloat((value - scale.low) / (scale.high - scale.low)) * (ChartFrame.bottom - ChartFrame.top)
            }
            let segments = MacTemperature.segments(history)
            let points = chartPoints(segments: segments, values: history.map { $0.value ?? scale.low }) { index, value in
                CGPoint(x: span.x(history[index].at, from: left, to: x1), y: y(value))
            }
            let health = MacTemperature.health(history)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for tick in scale.ticks {
                        chartGridLine(&context, y: y(tick), left: left, x1: x1, label: MacTemperature.degrees(tick))
                    }
                    chartHours(&context, span: span, left: left, x1: x1)
                    for segment in segments where segment.count > 1 {
                        for piece in chartPieces(segment, points: points, health: health) {
                            chartStroke(&context, piece, good: accent)
                        }
                    }
                    if let last = history.indices.last { chartDot(&context, at: points[last], color: chartColor(health[last], good: accent)) }
                    if let index = hovered, history.indices.contains(index) {
                        chartCross(&context, at: points[index], accent: accent)
                    }
                }
                if let index = hovered, history.indices.contains(index), let value = history[index].value {
                    ChartBubble(text: "\(chartClock.string(from: history[index].at)) · \(MacTemperature.degrees(value))",
                                x: points[index].x, x1: x1)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hovered = span.nearest(history.map { $0.at }, x: location.x, from: left, to: x1)
                case .ended:
                    hovered = nil
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Температура за 3 часа")
        .accessibilityValue(MacTemperature.caption(history))
    }
}

private let chartClock: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

/// Подписи часов графиков за 3 ч (температура, память): первая точка, дальше каждый час от неё, справа — «сейчас».
private func chartHourLabels(first: Date?, last: Date?, left: CGFloat, x1: CGFloat) -> [(text: String, x: CGFloat, anchor: UnitPoint)] {
    guard let first = first, let last = last else { return [] }
    let span = last.timeIntervalSince(first)
    var labels: [(text: String, x: CGFloat, anchor: UnitPoint)] = [("сейчас", x1, .trailing)]
    guard span >= 20 * 60 else { return labels }
    labels.append((chartClock.string(from: first), left, .leading))
    var hour: TimeInterval = 3600
    while hour < span - 30 * 60 {
        labels.append((chartClock.string(from: first.addingTimeInterval(hour)),
                       left + CGFloat(hour / span) * (x1 - left), .center))
        hour += 3600
    }
    return labels
}
