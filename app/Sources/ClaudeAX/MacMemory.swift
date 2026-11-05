import Darwin
import Foundation

// Нагрузка на память в панели у часов (#9082, WF132 «Память»; образец — температура, `MacTemperature.swift`).
// Слово Элвиса: «сделай ещё такой же график» — как «Нагрузка на память» в Мониторинге системы: высота — нагрузка,
// заливка зелёная / жёлтая / красная по уровню macOS.
//
// Откуда цифры (всё открытое, без прав):
//   • нагрузка — `kern.memorystatus_level` (сколько памяти macOS считает доступной, %): нагрузка = 100 − он;
//     нет его — доля занятого от всей памяти;
//   • уровень — `kern.memorystatus_vm_pressure_level` (1 — норма, 2 — жёлтая, 4 — красная), его же слушает
//     DISPATCH_SOURCE_TYPE_MEMORYPRESSURE;
//   • занято — как «Использовано памяти» в Мониторинге: память приложений (внутренние страницы без очищаемых)
//     + неперемещаемая + сжатая, `host_statistics64(HOST_VM_INFO64)`, против `physicalMemory`;
//   • своп — `vm.swapusage` (`xsw_usage.xsu_used`, байт): сколько сейчас лежит в файле подкачки (WF242).
// Опрос — раз в минуту на своей очереди, допуск 10 с; история — 180 точек (3 ч) только в памяти.

/// Уровень давления памяти, как цвет графика в Мониторинге системы.
public enum MemoryPressureLevel: Int, Equatable {
    case normal = 1
    case warn = 2
    case critical = 4
}

/// Состояние Мака на графиках температуры и памяти (#9818, слово Элвиса 11.10.2026: «зелёным… всё хорошо. Человек
/// заходит, и эта штука его должна успокаивать… зелёная, жёлтая и красная, когда всё плохо»): цвет линии и точки
/// «сейчас». Пороги — смысл самой macOS: температура — `thermalState`, память — своп и давление памяти.
public enum MacHealth: Int, Comparable {
    case good, warn, bad

    public static func < (left: MacHealth, right: MacHealth) -> Bool { left.rawValue < right.rawValue }
}

/// Одно чтение.
public struct MacMemorySample: Equatable {
    public let at: Date
    /// Нагрузка, % (0…100): что рисуем.
    public let pressure: Double?
    public let level: MemoryPressureLevel?
    /// Занято и всего, байт.
    public let used: UInt64?
    public let total: UInt64
    /// В файле подкачки, байт (`vm.swapusage`); nil — не прочитали.
    public let swap: UInt64?

    public init(at: Date, pressure: Double?, level: MemoryPressureLevel?, used: UInt64?, total: UInt64,
                swap: UInt64? = nil) {
        self.at = at
        self.pressure = pressure
        self.level = level
        self.used = used
        self.total = total
        self.swap = swap
    }

    /// Что рисуем: нагрузка по macOS, без неё — доля занятого.
    public var value: Double? {
        if let pressure = pressure { return pressure }
        guard let used = used, total > 0 else { return nil }
        return Swift.min(100, Double(used) / Double(total) * 100)
    }
}

/// Чистая часть: разбор чисел, история, слова, куски графика (тесты `MemoryWF132Tests`).
public enum MacMemory {
    public static let interval: TimeInterval = 60
    public static let window: TimeInterval = 3 * 3600
    public static let capacity = 180
    /// Разрыв линии: пропущено больше двух чтений (сон Мака, выключали и включали).
    public static let gap: TimeInterval = 150
    /// Ключ выключателя «Память в панели» (умолчание — включено, как у температуры).
    public static let enabledKey = "memoryInPanel"
    /// Шкала графика до WF177 — 0…100 % нагрузки (осталась для Мака, где занятое не читается).
    public static let ticks: [Double] = [0, 50, 100]

    /// `kern.memorystatus_vm_pressure_level`: 1/2/4, прочее — не знаем.
    public static func level(raw: Int?) -> MemoryPressureLevel? { raw.flatMap(MemoryPressureLevel.init(rawValue:)) }

    /// `kern.memorystatus_level` (доступно, %) → нагрузка, %; вне 0…100 — мусор.
    public static func pressure(available raw: Int?) -> Double? {
        guard let raw = raw, (0...100).contains(raw) else { return nil }
        return Double(100 - raw)
    }

    /// Занято, байт: приложения (внутренние без очищаемых) + неперемещаемая + сжатая.
    public static func used(internalPages: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        return (app + wired + compressed) * pageSize
    }

    /// Новая точка в истории: старше 3 ч и сверх 180 — прочь; точка без данных не добавляется.
    public static func append(_ sample: MacMemorySample, to history: [MacMemorySample]) -> [MacMemorySample] {
        guard sample.value != nil else { return history }
        var next = history.filter { sample.at.timeIntervalSince($0.at) < window && $0.at <= sample.at }
        next.append(sample)
        if next.count > capacity { next.removeFirst(next.count - capacity) }
        return next
    }

    public static func word(_ level: MemoryPressureLevel?) -> String {
        switch level {
        case .normal: return "в норме"
        case .warn: return "под нагрузкой"
        case .critical: return "не хватает"
        case nil: return "—"
        }
    }

    public static func percent(_ value: Double) -> String { "\(Int(value.rounded())) %" }

    /// Гигабайты: «6.3 ГБ» без «.0» («8 ГБ»). Дробная часть — через точку (WF267, слово Элвиса 17.10.2026 11:24:
    /// «память с точкой»): у памяти везде — строка плитки, подсказка, подпись и ось графика.
    public static func gigabytes(_ bytes: UInt64) -> String { tenthsText(tenths(bytes)) }

    /// Десятые гигабайта — одно округление на строку, подпись и ось.
    static func tenths(_ bytes: UInt64) -> Int { Int((Double(bytes) / 1_073_741_824 * 10).rounded()) }

    static func tenthsText(_ tenths: Int) -> String {
        tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }

    // MARK: ось в гигабайтах (WF177, #9197)

    // Слово Элвиса 09.10 02:35: «занято 6,3 ГБ, а шкала 100, 0, 50. Сделай шкалу 0 · 4 · 8 ГБ — по тому, сколько гигов
    // у пользователя; 6,3 из 8, а график на середине — как будто 4». Высота точки — занятое от всей памяти Мака
    // (`ProcessInfo.physicalMemory`), число строки — «6,3 ГБ»; цвет — по-прежнему уровень давления macOS.

    /// Высота точки 0…1: занято / вся память; занятого не знаем — нагрузка, %.
    public static func fraction(_ sample: MacMemorySample) -> Double? {
        if let used = sample.used, sample.total > 0 { return Swift.min(1, Double(used) / Double(sample.total)) }
        return sample.value.map { $0 / 100 }
    }

    /// Деления оси: 0 · половина · вся память, подписи в ГБ («0», «4», «8 ГБ» на 8 ГБ); памяти не знаем — 0 · 50 · 100 %.
    public static func axis(total: UInt64) -> [(fraction: Double, label: String)] {
        guard total > 0 else { return ticks.map { (fraction: $0 / 100, label: $0 == 100 ? "100 %" : "\(Int($0))") } }
        return [(fraction: 0, label: "0"), (fraction: 0.5, label: gigabytes(total / 2)),
                (fraction: 1, label: gigabytes(total) + " ГБ")]
    }

    /// Число одной точки: «6,3 ГБ», занятого нет — «65 %».
    public static func amount(_ sample: MacMemorySample) -> String? {
        if let used = sample.used, sample.total > 0 { return gigabytes(used) + " ГБ" }
        return sample.value.map(percent)
    }

    /// Занято, % всей памяти — из тех же десятых гигабайта, что «6,3 ГБ» и «из 8 ГБ» (WF181, #9217: «Как может быть
    /// 50 %, когда занято 6 ГБ?» — 50 % было нагрузкой macOS, `kern.memorystatus_level`, а не долей занятого):
    /// 6,3 из 8 — 79 %. Занятого не знаем — nil.
    public static func usedPercent(_ sample: MacMemorySample) -> Int? {
        guard let used = sample.used, sample.total > 0 else { return nil }
        let whole = tenths(sample.total)
        guard whole > 0 else { return nil }
        return Int((Double(tenths(used)) / Double(whole) * 100).rounded())
    }

    /// Число строки плитки — последняя точка; точек нет — «—».
    public static func nowText(_ history: [MacMemorySample]) -> String { history.last.flatMap(amount) ?? "—" }

    /// Подсказка строки плитки: «Память: занято 6,3 из 8 ГБ — 79 % · под нагрузкой · в свопе 1,2 ГБ» — ГБ и процент
    /// одной формулой (`usedPercent`). Занятого не знаем — честно «нагрузка по macOS 65 %» (это не доля занятого).
    /// Слова цвета («жёлтая») с WF242 нет: график серый, красным — только своп.
    public static func help(_ history: [MacMemorySample]) -> String {
        guard let last = history.last, let now = last.value else { return "Память" }
        let level = (last.level.map { " · \(word($0))" } ?? "") + (swapText(last).map { " · " + $0 } ?? "")
        if let used = last.used, last.total > 0, let share = usedPercent(last) {
            return "Память: занято \(gigabytes(used)) из \(gigabytes(last.total)) ГБ — \(share) %\(level)"
        }
        return "Память: нагрузка по macOS \(percent(now))\(level)"
    }

    /// Подпись под графиком (31.5) — два куска: слово уровня (рисуется его цветом) и остальное —
    /// «под нагрузкой» · «за 3 ч от 43 до 76 % · занято 7 из 8 ГБ». Число «сейчас» одно — в строке плитки
    /// (`percent(last.value)`), здесь его нет; «от A до B» считается по тем же округлённым точкам, что и оно,
    /// поэтому «сейчас» всегда внутри. Уровня не знаем — первого куска нет.
    /// С WF177 (ось в ГБ) — «за 3 ч от 5,1 до 6,8 ГБ»: числа те же десятые, что «6,3 ГБ» строки, всё из всей памяти
    /// уже на оси; занятого не знаем — как раньше, проценты нагрузки.
    /// С WF242 своп известен — первое слово про него («своп растёт» / «много в свопе», красным; спокойно — слова
    /// нет), в конце «в свопе 1,2 ГБ»; свопа не знаем — слово уровня macOS, как раньше.
    public static func captionParts(_ history: [MacMemorySample]) -> (word: String, rest: String) {
        guard let last = history.last else { return ("", "") }
        var parts: [String] = []
        let span = history.count > 1 ? Int((last.at.timeIntervalSince(history[0].at) / 60).rounded()) : 0
        let when = span >= 175 ? "за 3 ч" : span >= 60 ? "за \(span / 60) ч \(span % 60) мин" : "за \(max(span, 1)) мин"
        if last.used != nil, last.total > 0 {
            let marks = history.compactMap { $0.used }.map { MacMemory.tenths($0) }
            if let low = marks.min(), let high = marks.max(), history.count > 1 {
                parts.append(low == high ? "\(when) без изменений"
                                         : "\(when) от \(tenthsText(low)) до \(tenthsText(high)) ГБ")
            }
        } else {
            let values = history.compactMap { $0.value }.map { Int($0.rounded()) }
            if let low = values.min(), let high = values.max(), history.count > 1 {
                parts.append(low == high ? "\(when) без изменений" : "\(when) от \(low) до \(high) %")
            }
        }
        guard last.swap != nil else { return (last.level.map(word) ?? "", parts.joined(separator: " · ")) }
        if let swap = swapText(last) { parts.append(swap) }
        return (swapWord(history), parts.joined(separator: " · "))
    }

    // MARK: своп — когда память нагружена (WF242)

    // Слово Элвиса 11.10.2026: «Когда память-то считается нагружена? Когда своп начинает использоваться… он же
    // в какой-то момент прямо значительный, сразу понятно становится, что он попёр». Одного «своп не ноль» мало:
    // macOS не возвращает давно вытесненное с диска, пока его не спросят, — сотни мегабайт лежат в свопе сутками
    // после былой тесноты, и график был бы красным всегда. Поэтому два признака:
    //   • растёт — за минуту (одно чтение) в своп ушло от `swapGrowth` (64 МБ, это устойчиво больше 1 МБ/с): память
    //     вытесняется на диск прямо сейчас; мелкая рябь в единицы мегабайт под порог не попадает;
    //   • держится высоко — в свопе от `swapHighShare` (четверть) всей памяти Мака: 2 ГБ при 8, 4 ГБ при 16. Столько
    //     на диске — уже не забытый хвост, а рабочие данные: переключение между программами читает с диска.

    /// Прирост свопа за одно чтение, с которого он «растёт», байт.
    public static let swapGrowth: UInt64 = 64 * 1_048_576
    /// Доля всей памяти в свопе, с которой он «держится высоко».
    public static let swapHighShare = 0.25

    enum SwapLoad: Equatable { case calm, growing, high }

    /// Нагрузка точки по свопу: растёт (против прошлого чтения без разрыва), держится высоко или спокойно.
    static func swapLoad(_ history: [MacMemorySample], at index: Int) -> SwapLoad {
        guard history.indices.contains(index), let swap = history[index].swap else { return .calm }
        if index > 0, let before = history[index - 1].swap, swap > before, swap - before >= swapGrowth,
           history[index].at.timeIntervalSince(history[index - 1].at) <= gap { return .growing }
        let total = history[index].total
        return total > 0 && Double(swap) >= Double(total) * swapHighShare ? .high : .calm
    }

    /// Точки, где память нагружена: своп растёт или держится высоко; свопа не знаем — уровень macOS не «в норме».
    public static func loaded(_ history: [MacMemorySample]) -> [Bool] {
        health(history).map { $0 != .good }
    }

    /// Цвет каждой точки (#9818), как «Давление памяти» в Мониторинге системы: красный — macOS прямо сейчас
    /// вытесняет память на диск (своп растёт) или давление критическое; жёлтый — в свопе держится много (рабочие данные
    /// на диске) или давление повышено; иначе зелёный. Своп известен — решает он (WF242: «нагружена — когда своп»).
    public static func health(_ history: [MacMemorySample]) -> [MacHealth] {
        history.indices.map { index in
            guard history[index].swap != nil else {
                switch history[index].level ?? .normal {
                case .normal: return .good
                case .warn: return .warn
                case .critical: return .bad
                }
            }
            switch swapLoad(history, at: index) {
            case .growing: return .bad
            case .high: return .warn
            case .calm: return .good
            }
        }
    }

    /// Слово подписи про своп сейчас (цветом `health` последней точки); спокойно — пусто.
    static func swapWord(_ history: [MacMemorySample]) -> String {
        switch swapLoad(history, at: history.count - 1) {
        case .growing: return "своп растёт"
        case .high: return "много в свопе"
        case .calm: return ""
        }
    }

    /// «в свопе 1,2 ГБ»; свопа нет, не знаем или меньше 0,1 ГБ — nil.
    public static func swapText(_ sample: MacMemorySample) -> String? {
        guard let swap = sample.swap, tenths(swap) > 0 else { return nil }
        return "в свопе \(gigabytes(swap)) ГБ"
    }

    /// Вся подпись одной строкой (озвучка, тесты).
    public static func caption(_ history: [MacMemorySample]) -> String {
        let parts = captionParts(history)
        return [parts.word, parts.rest].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Куски линии без разрывов: индексы точек истории.
    public static func segments(_ history: [MacMemorySample]) -> [[Int]] {
        var result: [[Int]] = []
        for index in history.indices {
            if index > 0, history[index].at.timeIntervalSince(history[index - 1].at) <= gap, !result.isEmpty {
                result[result.count - 1].append(index)
            } else {
                result.append([index])
            }
        }
        return result
    }

    /// Ближайшая по времени точка к доле 0…1 оси X (наведение на график).
    public static func nearest(_ history: [MacMemorySample], fraction: Double) -> Int? {
        guard let first = history.first, let last = history.last else { return nil }
        let span = last.at.timeIntervalSince(first.at)
        guard span > 0 else { return 0 }
        let target = first.at.addingTimeInterval(span * Swift.min(1, Swift.max(0, fraction)))
        return history.indices.min { abs(history[$0].at.timeIntervalSince(target)) < abs(history[$1].at.timeIntervalSince(target)) }
    }
}

/// Чтение из ядра: `sysctl` и `host_statistics64`.
enum MemoryReader {
    /// `vm.swapusage` → занято в файле подкачки, байт.
    static func swapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0, size == MemoryLayout<xsw_usage>.size else { return nil }
        return usage.xsu_used
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, size == MemoryLayout<Int32>.size else { return nil }
        return Int(value)
    }

    static func usedBytes() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MacMemory.used(internalPages: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
                              wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count),
                              pageSize: UInt64(vm_kernel_page_size))
    }
}

/// Опрос раз в минуту на своей очереди; история — в памяти. `onUpdate` зовётся на главном потоке и только пока
/// панель открыта (`watch(true)`, WF164): закрыта — монитор молча копит 3 ч (два `sysctl` и `host_statistics64`
/// раз в минуту, доли миллисекунды), главный поток и SwiftUI не трогает.
public final class MacMemoryMonitor {
    private let queue = DispatchQueue(label: "pimp.memory", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var history: [MacMemorySample] = []
    /// Файл истории (#10215): после перезапуска Пимпа график продолжается.
    private let file: ChartHistoryFile<MemoryRow>?
    /// Панель открыта — точки уходят в `onUpdate` (только на очереди монитора).
    private var delivering = false
    public var onUpdate: (([MacMemorySample]) -> Void)?
    /// Три главных пожирателя (#11620) — на главном потоке, как `onUpdate`, и тоже только пока панель открыта.
    public var onEaters: (([MemoryEater]) -> Void)?

    public init(file: URL? = nil) { self.file = file.map(ChartHistoryFile.init(url:)) }

    public var running: Bool { timer != nil }

    /// Первое чтение сразу, дальше — раз в минуту.
    public func start() {
        guard timer == nil else { return }
        queue.async { [weak self] in
            guard let self = self, let file = self.file, self.history.isEmpty else { return }
            let now = Date()
            self.history = file.load().map { $0.sample }
                .filter { now.timeIntervalSince($0.at) < MacMemory.window && $0.at <= now && $0.value != nil }
                .suffix(MacMemory.capacity).map { $0 }
        }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: MacMemory.interval, leeway: .seconds(10))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    /// Выключили — опроса нет, история забыта (включат — начнётся заново).
    public func stop() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in
            self?.history = []
            self?.file?.save([])
            DispatchQueue.main.async { self?.onUpdate?([]) }
        }
    }

    /// Одно чтение (на очереди монитора).
    public func readNow() -> MacMemorySample {
        dispatchPrecondition(condition: .onQueue(queue))
        let sample = MacMemorySample(at: Date(),
                                     pressure: MacMemory.pressure(available: MemoryReader.sysctlInt("kern.memorystatus_level")),
                                     level: MacMemory.level(raw: MemoryReader.sysctlInt("kern.memorystatus_vm_pressure_level")),
                                     used: MemoryReader.usedBytes(), total: ProcessInfo.processInfo.physicalMemory,
                                     swap: MemoryReader.swapUsedBytes())
        return sample
    }

    /// Панель открылась (true) или закрылась (false). Вернёт историю на сейчас — панель рисует её сразу,
    /// без прыжка высоты.
    @discardableResult
    public func watch(_ on: Bool) -> [MacMemorySample] {
        queue.sync {
            delivering = on
            if on { deliverEaters() }
            return history
        }
    }

    /// Кто съел память (#11620) — отдельно от точки, чтобы история не ждала обхода процессов.
    private func deliverEaters() {
        guard onEaters != nil else { return }
        queue.async { [weak self] in
            let eaters = MemoryEaters.read()
            DispatchQueue.main.async { self?.onEaters?(eaters) }
        }
    }

    /// Одно чтение в историю, как по таймеру (замер и тесты).
    func tickNow() { queue.sync { tick() } }

    private func tick() {
        history = MacMemory.append(readNow(), to: history)
        file?.save(history.map(MemoryRow.init))
        guard delivering else { return }
        let snapshot = history
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) }
        deliverEaters()
    }
}
