import AppKit
import ClaudeAX
import CoreImage.CIFilterBuiltins
import PassKit
import SwiftUI

// Окно «Поддержать автора» (WF108, #8179; переделано в WF227, #9406, макет `docs/37.html`, кадры 37.3–37.5):
// сверху — кому платят (фото, имя, город, Instagram), по городу — короткая сводка; ниже — счёт людей «Друзья
// Пимпа» вместо шкалы денег и способы оплаты. Способ появляется, только когда его адрес есть в donate.json
// (`Donate.methods`): Apple Pay → Safari, «Картой» и Kaspi → браузер по умолчанию, «Криптой» — адрес и QR в окне.
// Способов нет — одна тихая строка «оплату подключаю», кнопок в никуда нет. Сети нет: всё из donate.json
// (`DonateStore`, решения — `Donate` в ClaudeAX, тесты `DonateTests`). Оплату мы не видим: «Спасибо!» — только по
// возвратной ссылке `pimpmyclaude://donate/thanks`, счёт людей растёт только от нового donate.json.

final class DonateModel: ObservableObject {
    enum Selection: Equatable { case preset(Int), own }
    enum Pay: Equatable { case idle, opening, opened, ok, failed, cancelled }
    enum Via { case applePay, card, kaspi }

    @Published var config: DonateConfig
    @Published var selection: Selection = .preset(5000)
    @Published var own = ""
    @Published var pay = Pay.idle
    @Published var via = Via.applePay
    @Published var cryptoOpen = false
    @Published var coin = 0
    @Published var copied = false
    /// Открыта сводка об авторе (нажали на город).
    @Published var bioOpen = false
    var reduceMotion = false

    init(config: DonateConfig) {
        self.config = config
        resetSelection()
    }

    func resetSelection() {
        selection = .preset(config.amounts.contains(5000) ? 5000 : config.amounts.first ?? 0)
        own = ""
    }

    var methods: [Donate.Method] { Donate.methods(config) }
    var showsAmounts: Bool { Donate.showsAmounts(config) }

    var amount: Int {
        switch selection {
        case .preset(let value): return value
        case .own: return min(Int(own) ?? 0, DonateConfig.maxAmount)
        }
    }

    func url(_ via: Via) -> URL? {
        let template: String?
        switch via {
        case .applePay: template = config.applePay
        case .card: template = config.card
        case .kaspi: template = config.kaspi
        }
        return Donate.payURL(template, amount: showsAmounts ? amount : nil)
    }
}

// MARK: - окно

final class DonateWindowController: NSObject, NSWindowDelegate {
    private let store = DonateStore()
    private var window: NSWindow?
    private var model: DonateModel?
    private var monitor: Any?
    private var timer: Timer?
    private var stateGeneration = 0
    private var copyGeneration = 0

    /// Конфиг для панели и меню: свежий по mtime.
    func config() -> DonateConfig? { store.current() }

    /// Видны ли входы: окну есть что показать и «Показывать „Поддержать“» не выключен.
    var entriesVisible: Bool {
        Donate.entriesVisible(store.current(), hidden: UserDefaults.standard.bool(forKey: Donate.hiddenKey))
    }

    func show() {
        guard let config = store.current(), Donate.windowAvailable(config) else { return }
        if let window = window, let model = model {
            apply(config, to: model)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = DonateModel(config: config)
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.model = model
        let controller = NSHostingController(rootView: DonateView(model: model, actions: actions(),
                                                                  photo: DonatePhoto.image))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.title = "Поддержать автора"
        // Тема — как у системы (WF227): окно читается и в светлой.
        window.backgroundColor = DonateColor.windowBackground
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        startWatching()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Вернулись со страницы оплаты: «Спасибо!» или «Отменено». Окно закрыто — откроем.
    func handleReturn(_ answer: Donate.Return) {
        if window == nil { show() }
        guard let model = model else { return }
        model.cryptoOpen = false
        model.bioOpen = false
        set(answer == .thanks ? .ok : .cancelled)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        stopWatching()
        stateGeneration += 1
        window = nil
        model = nil
    }

    // MARK: действия

    private func actions() -> DonateView.Actions {
        DonateView.Actions(
            pay: { [weak self] via in self?.pay(via) },
            reopen: { [weak self] in
                guard let self = self, let model = self.model else { return }
                self.pay(model.via)
            },
            cancel: { [weak self] in self?.set(.cancelled) },
            copy: { [weak self] address in self?.copy(address) },
            open: { url in NSWorkspace.shared.open(url) })
    }

    private func pay(_ via: DonateModel.Via) {
        guard let model = model, let url = model.url(via) else { return }
        model.via = via
        model.cryptoOpen = false
        set(.opening)
        let generation = stateGeneration
        let app: URL? = via == .applePay
            ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
            : NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        let failed = { [weak self] in
            guard let self = self, generation == self.stateGeneration else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            self.set(.failed)
        }
        guard let app = app else { return failed() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if error != nil { return failed() }
                guard let self = self, generation == self.stateGeneration else { return }
                self.set(.opened)
            }
        }
    }

    /// Смена состояния оплаты; «Спасибо!» и «Отменено» сами уходят в обычное (4,5 и 2,5 с).
    private func set(_ pay: DonateModel.Pay) {
        guard let model = model else { return }
        stateGeneration += 1
        let generation = stateGeneration
        withAnimation(model.reduceMotion ? nil : .easeOut(duration: 0.18)) { model.pay = pay }
        let back: TimeInterval? = pay == .ok ? 4.5 : pay == .cancelled ? 2.5 : nil
        if let back = back {
            DispatchQueue.main.asyncAfter(deadline: .now() + back) { [weak self] in
                guard let self = self, generation == self.stateGeneration else { return }
                self.set(.idle)
            }
        }
    }

    private func copy(_ address: String) {
        guard let model = model else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        model.copied = true
        copyGeneration += 1
        let generation = copyGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self = self, generation == self.copyGeneration else { return }
            self.model?.copied = false
        }
    }

    // MARK: новый donate.json и клавиши

    private func apply(_ config: DonateConfig, to model: DonateModel) {
        guard config != model.config else { return }
        model.config = config
        if case .preset(let value) = model.selection, !config.amounts.contains(value) { model.resetSelection() }
        if model.coin >= config.crypto.count { model.coin = 0 }
        if config.crypto.isEmpty { model.cryptoOpen = false }
        // Из файла убрали всё, пока окно открыто, — окну нечего показать.
        if !Donate.windowAvailable(config) { close() }
    }

    private func startWatching() {
        // Файл правят руками — пока окно открыто, смотрим mtime раз в 2 с (сети нет).
        let tick = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self, let model = self.model else { return }
            if let config = self.store.current() { self.apply(config, to: model) } else { self.close() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = self.window, event.window === window else { return event }
            if event.keyCode == 53 { self.escape(); return nil }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "w" {
                self.close()
                return nil
            }
            return event
        }
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Esc: ждём оплату — отмена, сводка — назад, своя сумма — к подсказкам, открыта крипта — свернуть,
    /// иначе — закрыть.
    private func escape() {
        guard let model = model else { return close() }
        switch model.pay {
        case .opening, .opened: set(.cancelled)
        default:
            if model.bioOpen {
                withAnimation(model.reduceMotion ? nil : .easeOut(duration: 0.18)) { model.bioOpen = false }
            } else if model.selection == .own {
                model.resetSelection()
            } else if model.cryptoOpen {
                model.cryptoOpen = false
            } else {
                close()
            }
        }
    }
}

// MARK: - вид

/// Контраст текста числом (WF227): цвет PMP человек выбирает сам, а текстом и заливкой он должен
/// читаться на тёмном и на светлом окне.
enum DonateTone {
    static let darkBackground: UInt32 = 0x262628
    static let lightBackground: UInt32 = 0xF5F5F7
    /// Порог для текста (WCAG AA).
    static let textContrast = 4.5

    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Цвет как текст на фоне: шагами тянем к белому (фон тёмный) или к чёрному (светлый), пока контраст
    /// не дойдёт до порога.
    static func readable(_ hex: UInt32, on background: UInt32) -> UInt32 {
        let target: Double = luminance(background) < 0.5 ? 255 : 0
        var color = hex
        for step in 0...20 where contrast(color, background) < textContrast {
            let share = Double(step) / 20
            func mix(_ shift: UInt32) -> UInt32 {
                let value = Double((hex >> shift) & 0xFF)
                return UInt32((value + (target - value) * share).rounded()) << shift
            }
            color = mix(16) | mix(8) | mix(0)
        }
        return color
    }

    /// Текст на заливке: тёмный или белый — какой читается.
    static func ink(on fill: UInt32) -> UInt32 {
        contrast(0x1C1C1E, fill) >= contrast(0xFFFFFF, fill) ? 0x1C1C1E : 0xFFFFFF
    }
}

/// Цвета окна: тёмная тема — графит панели, светлая — свои (WF227). Каждый цвет сам меняется с темой окна.
enum DonateColor {
    private static func ns(_ hex: UInt32) -> NSColor { PMPAccent.fromHex(hex) }

    private static func adaptive(dark: @escaping () -> UInt32, light: @escaping () -> UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            ns(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark() : light())
        }
    }

    private static func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(nsColor: adaptive(dark: { dark }, light: { light }))
    }

    static let windowBackground = adaptive(dark: { DonateTone.darkBackground }, light: { DonateTone.lightBackground })
    static let background = Color(nsColor: windowBackground)
    static let text = adaptive(0xECECEE, 0x1C1C1E)
    static let sub = adaptive(0x9B9BA1, 0x636368)
    static let frame = adaptive(0x3A3A3D, 0xD9D9DE)
    static let good = adaptive(0x5FB884, 0x24693F)
    static let bad = adaptive(0xD9695F, 0xB3372C)
    static let warn = adaptive(0xEFC65C, 0x7A5800)
    static let chip = text.opacity(0.06)
    static let cell = text.opacity(0.1)

    /// Цвет PMP заливкой: на светлом окне — вариант для светлой строки меню (графит там тёмный).
    static var accent: Color {
        let accent = PMPAccent.current
        return Color(nsColor: adaptive(dark: { accent.hex }, light: { accent.lightBarHex }))
    }

    /// Цвет PMP текстом (ссылки): дотянут до читаемого на фоне окна.
    static var link: Color {
        let accent = PMPAccent.current
        return Color(nsColor: adaptive(dark: { DonateTone.readable(accent.hex, on: DonateTone.darkBackground) },
                                       light: { DonateTone.readable(accent.hex, on: DonateTone.lightBackground) }))
    }

    /// Текст на заливке цветом PMP.
    static var onAccent: Color {
        let accent = PMPAccent.current
        return Color(nsColor: adaptive(dark: { DonateTone.ink(on: accent.hex) },
                                       light: { DonateTone.ink(on: accent.lightBarHex) }))
    }

    static var chipOn: Color { accent.opacity(0.18) }
}

/// Фото автора из бандла (WF227, #9406: новое фото, без очков; кладёт `tools/bundle.sh`).
enum DonatePhoto {
    static let image: NSImage? = Bundle.main.url(forResource: "ElvisPhoto", withExtension: "jpg")
        .flatMap { NSImage(contentsOf: $0) }
}

/// Что окно говорит об авторе (слово Элвиса 10.10.2026: только имя, город и одна строка).
private enum DonateAuthor {
    static let name = "Элвис Игликов"
    static let city = "Шемонаиха, Казахстан"
    static let region = "Шемонаиха, Восточный Казахстан"
    static let line = "Делаю Пимпа один, вместе с нейронками. Он бесплатный и таким останется."
    static let about = "Делаю программы для Mac — один, вместе с нейронками."
}

/// Нажатие — пружина, наведение — чуть светлее (как выключатели панели).
private struct DonatePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hovering { hover in
            configuration.label
                .contentShape(Rectangle())
                .brightness(hover ? 0.06 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(PanelSpring.press, value: configuration.isPressed)
        }
    }
}

private struct Hovering<Content: View>: View {
    @State private var hover = false
    let content: (Bool) -> Content
    init(@ViewBuilder _ content: @escaping (Bool) -> Content) { self.content = content }
    var body: some View { content(hover).onHover { hover = $0 } }
}

/// Круглое фото; файла нет — нейтральный круг с силуэтом.
private struct DonateAvatar: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                DonateColor.chip.overlay(Image(systemName: "person.fill").font(.system(size: size * 0.42))
                    .foregroundColor(DonateColor.sub))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DonateColor.frame, lineWidth: 1))
        .accessibilityLabel("Фото автора")
    }
}

struct DonateView: View {
    struct Actions {
        var pay: (DonateModel.Via) -> Void
        var reopen: () -> Void
        var cancel: () -> Void
        var copy: (String) -> Void
        var open: (URL) -> Void
    }

    @ObservedObject var model: DonateModel
    let actions: Actions
    let photo: NSImage?
    @FocusState private var ownFocused: Bool
    @Environment(\.colorScheme) private var scheme

    private var config: DonateConfig { model.config }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if model.bioOpen { bio } else { main }
            }
            .padding(EdgeInsets(top: 40, leading: 18, bottom: 14, trailing: 18))
            divider
            Text(Donate.unofficial)
                .font(.system(size: 11)).foregroundColor(DonateColor.sub)
                .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
        }
        .frame(width: 420)
        .background(DonateColor.background)
    }

    private var divider: some View {
        Rectangle().fill(DonateColor.frame).frame(height: 1)
    }

    // MARK: главный вид

    private var main: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !model.methods.isEmpty { friends }
            if model.pay != .idle || !model.methods.isEmpty {
                paySection
            } else {
                // Способов оплаты в файле нет (WF227): честно одной тихой строкой, без кнопок в никуда.
                divider
                Text("Оплату ещё подключаю — скоро откроется.")
                    .font(.system(size: 12)).foregroundColor(DonateColor.sub)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            DonateAvatar(image: photo, size: 60)
            VStack(alignment: .leading, spacing: 0) {
                Text(DonateAuthor.name).font(.system(size: 15, weight: .semibold)).foregroundColor(DonateColor.text)
                textLink(DonateAuthor.city + " ›", help: "Коротко об авторе") { setBio(true) }
                    .padding(.top, 1)
                Text(DonateAuthor.line).font(.system(size: 12)).foregroundColor(DonateColor.sub)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                instagram.padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    /// Ссылка на Instagram — только когда имя есть в donate.json. Имя идёт дословно и без подчёркивания:
    /// у «_elvis.kz_» подчёркивания по краям — часть адреса (#9394), разметка и линия под текстом их съедают.
    @ViewBuilder private var instagram: some View {
        if let handle = config.instagram, let url = Donate.instagramURL(handle) {
            textLink("Instagram @" + handle, help: url.absoluteString) { actions.open(url) }
        }
    }

    private func setBio(_ open: Bool) {
        withAnimation(model.reduceMotion ? nil : .easeOut(duration: 0.18)) { model.bioOpen = open }
    }

    // MARK: сводка об авторе

    private var bio: some View {
        VStack(alignment: .leading, spacing: 14) {
            textLink("‹ Назад", help: "Esc") { setBio(false) }
            HStack(alignment: .center, spacing: 14) {
                DonateAvatar(image: photo, size: 84)
                VStack(alignment: .leading, spacing: 0) {
                    Text(DonateAuthor.name).font(.system(size: 15, weight: .semibold)).foregroundColor(DonateColor.text)
                    Text(DonateAuthor.region).font(.system(size: 12.5)).foregroundColor(DonateColor.text)
                        .padding(.top, 1)
                    Text(DonateAuthor.about).font(.system(size: 12)).foregroundColor(DonateColor.sub)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    instagram.padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            if !model.methods.isEmpty {
                accentButton("Поддержать", enabled: true) { setBio(false) }
            }
        }
    }

    // MARK: счёт людей

    private var friends: some View {
        let friends = Donate.friends(config.people)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Друзья Пимпа").font(.system(size: 13.5, weight: .semibold)).foregroundColor(DonateColor.text)
                Spacer()
                Text(Donate.group(config.people)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    .foregroundColor(DonateColor.text)
            }
            if friends.cells > 0 {
                HStack(spacing: friends.cells > 50 ? 1 : friends.cells > 25 ? 2 : 3) {
                    ForEach(0..<friends.cells, id: \.self) { index in
                        RoundedRectangle(cornerRadius: friends.cells > 50 ? 1 : 2, style: .continuous)
                            .fill(index < friends.filled ? DonateColor.accent : DonateColor.cell)
                    }
                }
                .frame(height: 8)
                .padding(.top, 1)
            }
            Text(friends.note).font(.system(size: 11.5)).foregroundColor(DonateColor.sub)
            divider
            Text("На что: Claude для работы над Пимпом и новый Mac.")
                .font(.system(size: 11.5)).foregroundColor(DonateColor.sub)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DonateColor.chip))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DonateColor.frame, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: оплата

    @ViewBuilder private var paySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.pay {
            case .opening:
                status(spinner: true, "Открываю страницу оплаты…", color: DonateColor.text)
                hintLine(Text(payDetail))
            case .opened:
                status(spinner: true, model.via == .applePay ? "Ждём оплату в Safari" : "Ждём оплату в браузере",
                       color: DonateColor.text)
                HStack(spacing: 4) {
                    Text("Оплатил — вернись сюда ·").font(.system(size: 11.5)).foregroundColor(DonateColor.sub)
                    link("открыть ещё раз", actions.reopen)
                    Text("·").font(.system(size: 11.5)).foregroundColor(DonateColor.sub)
                    link("отмена", actions.cancel)
                    kbd("Esc")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            case .ok:
                status(spinner: false, "✓ Спасибо!", color: DonateColor.good)
                hintLine(Text("Счёт друзей обновится с новой версией Пимпа"))
            case .failed:
                status(spinner: false, model.via == .applePay ? "Safari не открылся — ссылка в буфере"
                                                              : "Браузер не открылся — ссылка в буфере", color: DonateColor.bad)
                HStack(spacing: 4) {
                    Text("Вставь её в любой браузер ·").font(.system(size: 11.5)).foregroundColor(DonateColor.sub)
                    link("ещё раз", actions.reopen)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            case .cancelled:
                status(spinner: false, "Отменено — ничего не списано", color: DonateColor.sub)
            case .idle:
                if model.showsAmounts { amounts }
                idleButtons
            }
        }
    }

    private var payDetail: String {
        let way: String
        switch model.via {
        case .applePay: way = "Apple Pay"
        case .card: way = "картой"
        case .kaspi: way = "Kaspi"
        }
        return model.showsAmounts ? "\(Donate.tenge(model.amount)) · \(way)" : way
    }

    private var amounts: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(config.amounts, id: \.self) { value in
                    amountChip(title: Donate.tenge(value), sub: Donate.usd(value, rate: config.usdRate) ?? " ",
                               on: model.selection == .preset(value)) { model.selection = .preset(value) }
                }
                amountChip(title: "Своя", sub: config.usdRate == nil ? "₸" : "₸ и $", on: model.selection == .own) {
                    model.selection = .own
                    ownFocused = true
                }
            }
            if model.selection == .own {
                HStack(spacing: 6) {
                    TextField("сумма", text: Binding(get: { model.own }, set: { value in
                        model.own = String(value.filter(\.isASCIIDigitLike).prefix(7))
                    }))
                    .textFieldStyle(.roundedBorder).frame(width: 110).focused($ownFocused)
                    .accessibilityLabel("своя сумма, тенге")
                    Text("₸ \(model.amount > 0 ? Donate.usd(model.amount, rate: config.usdRate) ?? "" : "")")
                        .font(.system(size: 12)).foregroundColor(DonateColor.sub)
                    Spacer()
                    kbd("Esc")
                }
                .onAppear { ownFocused = true }
            }
        }
    }

    private func amountChip(title: String, sub: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundColor(DonateColor.text)
                Text(sub).font(.system(size: 11)).foregroundColor(DonateColor.sub)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? DonateColor.chipOn : DonateColor.chip))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(on ? DonateColor.accent : Color.clear, lineWidth: 1.2))
        }
        .buttonStyle(DonatePress())
    }

    /// Кнопки только тех способов, что есть в файле: первый — главной кнопкой (она на экране одна),
    /// остальные — текстом под ней. Одна крипта — её адрес открыт сразу.
    @ViewBuilder private var idleButtons: some View {
        let methods = model.methods
        let hasAmount = !model.showsAmounts || model.amount > 0
        switch methods.first {
        case .applePay:
            // Две колонки с общими строками: кнопка и подсказка — напротив QR, запасные способы — на одной
            // строке с подписью QR.
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(scheme == .dark ? Color.white : Color.black)
                        ApplePayButton(dark: scheme == .dark, enabled: hasAmount && model.url(.applePay) != nil) {
                            actions.pay(.applePay)
                        }
                        .id(scheme)
                    }
                    .frame(height: 44)
                    .opacity(hasAmount ? 1 : 0.45)
                    .accessibilityLabel("Apple Pay — откроется в Safari")
                    hintLine(hint(hasAmount: hasAmount, where_: "откроется в Safari, там Touch ID"))
                        .frame(height: DonateView.qrSide - 44 - 4)
                    if methods.count > 1 { altLinks(methods, hasAmount: hasAmount).frame(height: 16) }
                }
                // Та же страница оплаты — для iPhone: навёл камеру, там Apple Pay в два касания.
                VStack(spacing: 4) {
                    QRCode(text: model.url(.applePay)?.absoluteString, inset: 4)
                        .frame(width: DonateView.qrSide, height: DonateView.qrSide)
                    Text("с iPhone").font(.system(size: 12)).foregroundColor(DonateColor.sub).frame(height: 16)
                }
                .opacity(hasAmount ? 1 : 0.45)
            }
        case .card:
            accentButton("Оплатить картой", enabled: hasAmount && model.url(.card) != nil) { actions.pay(.card) }
            hintLine(hint(hasAmount: hasAmount, where_: "откроется в браузере"))
            if methods.count > 1 { altLinks(methods, hasAmount: hasAmount) }
        case .kaspi:
            accentButton("Оплатить через Kaspi", enabled: hasAmount && model.url(.kaspi) != nil) { actions.pay(.kaspi) }
            hintLine(hint(hasAmount: hasAmount, where_: "откроется в браузере"))
            if methods.count > 1 { altLinks(methods, hasAmount: hasAmount) }
        case .crypto, .none:
            EmptyView()
        }
        if !config.crypto.isEmpty, model.cryptoOpen || methods.first == .crypto { crypto }
        Text("Любая сумма — уже спасибо. Деньги приходят прямо Элвису.")
            .font(.system(size: 11.5)).foregroundColor(DonateColor.sub)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private static let qrSide: CGFloat = 64

    /// Запасные способы — все, кроме главной кнопки, текстом в одну строку.
    private func altLinks(_ methods: [Donate.Method], hasAmount: Bool) -> some View {
        HStack(spacing: 14) {
            ForEach(Array(methods.dropFirst().enumerated()), id: \.offset) { _, method in
                switch method {
                case .card: altLink("Картой", enabled: hasAmount && model.url(.card) != nil) { actions.pay(.card) }
                case .kaspi: altLink("Kaspi", enabled: hasAmount && model.url(.kaspi) != nil) { actions.pay(.kaspi) }
                case .crypto:
                    altLink("Криптой", on: model.cryptoOpen) {
                        model.cryptoOpen.toggle()
                        model.copied = false
                    }
                case .applePay: EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func hint(hasAmount: Bool, where_: String) -> Text {
        if !hasAmount { return Text("Впиши сумму") }
        guard model.showsAmounts else { return Text(where_) }
        let usd = Donate.usd(model.amount, rate: config.usdRate).map { " \($0)" } ?? ""
        return Text(Donate.tenge(model.amount)).bold().foregroundColor(DonateColor.text) + Text("\(usd) · \(where_)")
    }

    private var crypto: some View {
        let coins = config.crypto
        let coin = coins[min(model.coin, coins.count - 1)]
        return VStack(alignment: .leading, spacing: 8) {
            if coins.count > 1 {
                HStack(spacing: 4) {
                    ForEach(Array(coins.enumerated()), id: \.offset) { index, item in
                        Button { model.coin = index; model.copied = false } label: {
                            Text([item.coin, item.network].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundColor(index == model.coin ? DonateColor.onAccent : DonateColor.text)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(index == model.coin ? DonateColor.accent : DonateColor.chip))
                        }
                        .buttonStyle(DonatePress())
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                QRCode(text: coin.address, inset: 6).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(coin.address).font(.system(size: 11, design: .monospaced)).foregroundColor(DonateColor.text)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Button { actions.copy(coin.address) } label: {
                        Text(model.copied ? "Скопировано ✓" : "Скопировать адрес")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(model.copied ? DonateColor.good : DonateColor.text)
                            .padding(.horizontal, 12).frame(minHeight: 28)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DonateColor.chip))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(DonateColor.frame, lineWidth: 1))
                    }
                    .buttonStyle(DonatePress())
                    if !coin.network.isEmpty {
                        Text("Только сеть \(coin.network) — из другой сети перевод пропадёт.")
                            .font(.system(size: 11)).foregroundColor(DonateColor.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DonateColor.chip))
    }

    // MARK: кирпичи

    /// Главная кнопка, когда Apple Pay нет: заливка цветом PMP.
    private func accentButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(DonateColor.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DonateColor.accent))
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(DonatePress())
        .disabled(!enabled)
    }

    /// Ссылка цветом PMP (город, Instagram, «Назад»). Текст дословно, без разметки и без линии под ним;
    /// под мышь — полоса в 24 pt, строки при этом не раздвигаются.
    private func textLink(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: 12.5)).foregroundColor(DonateColor.link).lineLimit(1)
                .padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(DonatePress())
        .padding(.vertical, -4)
        .help(help)
    }

    /// Запасной способ оплаты — текстом под главной кнопкой.
    private func altLink(_ title: String, on: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: on ? .semibold : .regular)).underline()
                .foregroundColor(on ? DonateColor.text : DonateColor.sub)
                .padding(.vertical, 4).contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(DonatePress())
        .padding(.vertical, -4)
        .disabled(!enabled)
    }

    private func status(spinner: Bool, _ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            if spinner {
                if model.reduceMotion {
                    Circle().fill(DonateColor.accent).frame(width: 8, height: 8)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DonateColor.chip))
    }

    private func hintLine(_ text: Text) -> some View {
        text.font(.system(size: 11.5)).foregroundColor(DonateColor.sub).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func link(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5)).foregroundColor(DonateColor.link).underline()
        }
        .buttonStyle(.plain)
    }

    private func kbd(_ key: String) -> some View {
        Text(key).font(.system(size: 11, weight: .semibold)).foregroundColor(DonateColor.sub)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DonateColor.sub.opacity(0.5), lineWidth: 1))
    }
}

private extension Character {
    var isASCIIDigitLike: Bool { ("0"..."9").contains(self) }
}

/// Системная кнопка Apple Pay: знак рисует macOS (без entitlement рисуется — проверено на WF108).
/// На тёмном окне кнопка белая, на светлом — чёрная.
private struct ApplePayButton: NSViewRepresentable {
    let dark: Bool
    let enabled: Bool
    let action: () -> Void

    final class Coordinator: NSObject {
        var action: () -> Void = {}
        @objc func tap() { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .plain, paymentButtonStyle: dark ? .white : .black)
        button.cornerRadius = 10
        button.target = context.coordinator
        button.action = #selector(Coordinator.tap)
        return button
    }

    func updateNSView(_ button: PKPaymentButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = enabled
    }
}

/// QR: CoreImage, без сглаживания. Текста нет (сумма не вписана) — пустая плитка того же размера.
private struct QRCode: View {
    let text: String?
    let inset: CGFloat

    var body: some View {
        if let image = text.flatMap(Self.image) {
            Image(nsImage: image).interpolation(.none).resizable()
                .padding(inset).background(RoundedRectangle(cornerRadius: inset + 2).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: inset + 2).strokeBorder(DonateColor.frame, lineWidth: 1))
                .accessibilityLabel("QR-код")
        } else {
            RoundedRectangle(cornerRadius: inset + 2).fill(DonateColor.chip)
        }
    }

    static func image(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
