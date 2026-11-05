import AppKit
import ClaudeAX
import SwiftUI

// MARK: выключатели

struct Switch: View {
    let on: Bool
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? accent : Color.white.opacity(0.16))
            Circle().fill(on ? PanelColor.ink : Color.white).frame(width: 13, height: 13).padding(2)
        }
        .frame(width: 28, height: 17)
        .animation(PanelSpring.press, value: on)
    }
}

// MARK: настройки (§7)

/// Сводки и строки листа «Настройки» — что сейчас выбрано, одной строкой справа у группы.
enum SettingsText {
    /// Строка права управлять Терминалом (#10464).
    static func terminalAccess(_ access: PanelTerminals.Access) -> String {
        switch access {
        case .allowed: return "Управление Терминалом — разрешено"
        case .denied: return "Разрешить управлять Терминалом…"
        case .notAsked: return "Разрешить управлять Терминалом"
        }
    }

    /// Выключатель «Окон и Mac» (WF237, лист 48 — ответ 2.1): бывший «Меню на жёлтой кнопке окна» — меню снято, клавиши
    /// остались.
    static let pmpKeysTitle = "Клавиши PMP в Claude"
    static let pmpKeysHelp = "⌥⌘N новое окно, ⌥⌘↑ ⌥⌘↓ развернуть и свернуть, ⇧⌘N обкэшить, ⌥⌘A расставить, ⌥⌘S показать, "
        + "⌥⌘D прокрутить — пока Claude впереди."

    /// Группа «Окна и Mac» — все выключатели, кроме двух из «Дополнительно».
    static func windowToggles(_ toggles: [PanelToggle]) -> [PanelToggle] {
        toggles.filter { $0.id != AutomationDefaults.allowOnceKey && $0.id != AutomationDefaults.continueKey }
    }

    /// «3 с» / «нет» — сводка группы «Задержка» (WF180: «не "отправка", а "задержка"»).
    static func enter(_ delay: SendDelaySetting) -> String { delay.on ? "\(delay.seconds) с" : "нет" }

    /// «Bypass» или пусто; строки «ответ в …» с WF129 нет — ответов из панели больше нет (#9023).
    static func chats(bypass: Bool) -> String { bypass ? "Bypass" : "" }

    /// С WF245 выключатель один — название проекта: таймеров у закреплённых чатов нет с page-64.
    static func pinned(_ look: PinnedLook) -> String { look.folder ? "с проектом" : "без проекта" }

    static func windows(_ toggles: [PanelToggle]) -> String {
        let list = windowToggles(toggles)
        if list.contains(where: { $0.needsAccess }) { return "нужен доступ" }
        let on = list.filter { $0.on }.count
        return on == list.count ? "всё включено" : "включено \(on) из \(list.count)"
    }

    static func claudeVersion(_ patch: StatusIcon.Patch) -> String? {
        switch patch {
        case .installed(let version, _), .notInstalled(let version), .lost(let version, _): return version
        case .claudeNotFound, .unknown: return nil
        }
    }

    /// Строка Claude в «Обновлениях»: что с обновлением сейчас; `ready` — есть что ставить («Обновить»).
    static func update(_ block: PimpPanelText.UpdateBlock) -> (text: String, ready: Bool) {
        switch block {
        case .none: return ("последняя версия", false)
        case .available(let version, _, _): return ("вышла \(version)", false)
        case .downloading: return ("качаю обновление", false)
        case .verifying(let version, _): return ("проверяю \(version)", false)
        case .ready(let version, _), .timely(let version, _), .busy(let version, _): return ("скачалась \(version)", true)
        case .planned(let version): return ("\(version) — при запуске", true)
        case .snoozed: return ("обновление отложено", true)
        case .installing(let version, _): return ("ставлю \(version)", false)
        case .done(let version): return ("поставлена \(version)", false)
        case .failed(let why): return (why, false)
        }
    }

    static func updates(_ block: PimpPanelText.UpdateBlock, patch: StatusIcon.Patch) -> String {
        if block == .none { return claudeVersion(patch).map { "Claude \($0)" } ?? "" }
        return update(block).text
    }

    /// «по ширине · поля 32» — выбор блока «Текст» (WF167).
    static func text(justify: Bool, padding: Int) -> String { (justify ? "по ширине" : "влево") + " · поля \(padding)" }

    /// «Сам нажимать „Allow once“» (#9998, слово Элвиса 16.10.2026 20:38: «Как обезьяна сижу, нажимаю allow once каждый
    /// раз») — как до 1.10.23, для чатов без Bypass; сводка группы «Дополнительно» — когда включён.
    static let autoAllowTitle = "Сам нажимать «Allow once»"
    static let autoAllowHelp = "В чатах с Bypass permissions PMP жмёт «Allow once» всегда; здесь — для остальных чатов. Удаление, выкладку, деньги и пароли не подтверждает"
    static let autoAllowCaption = "Для чатов без Bypass: в Bypass жмёт всегда. Удаление, выкладку, деньги и пароли — нет."
    static func more(autoAllow: Bool) -> String { autoAllow ? "Allow — сам" : "" }

    /// «Новый чат по блоку передачи» (слово Элвиса 11.10.2026 07:00: «Это что значит?») — имя и подпись словами владельца.
    static let continueTitle = "Сам открывать новый чат"
    static let continueCaption = "Чат написал блок «ОТКРОЙ НОВЫЙ ЧАТ» — PMP сам открывает новый с его текстом и моделью. Пока ты печатаешь — ждёт."

    /// Строка под переключателем Bypass: текст и вид (нет ссылки — `link == false`).
    static func permission(_ value: BypassNew.Permission) -> (text: String, good: Bool, warn: Bool, link: Bool) {
        switch value {
        case .allowed: return ("✓ Режим разрешён в Claude", true, false, false)
        case .notAllowed: return ("Сначала разреши режим в настройках Claude", false, true, true)
        case .blockedByOrg: return ("Bypass выключен организацией", false, true, false)
        case .unknown: return ("Проверю, когда Claude запустится", false, false, false)
        }
    }
}

/// Лист «Настройки» за шестерёнкой (WF126 §7): группы-карточки, открыта всегда одна, справа — что выбрано.
struct SettingsSheet: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.settingsGroup = nil
                    model.sheet = .panel
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PanelColor.sub)
                    Text("Настройки").font(.system(size: 13, weight: .semibold)).foregroundColor(PanelColor.text)
                    Spacer()
                }
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .handCursor()
            .help("Назад (Esc)")
            SettingsGroupCard(model: model, group: .text, title: "Текст",
                              summary: SettingsText.text(justify: model.textJustify, padding: model.sidePadding)) {
                TextGroup(model: model)
            }
            SettingsGroupCard(model: model, group: .font, title: "Шрифт панели", summary: model.typography.name) {
                TypographyGroup(model: model)
            }
            SettingsGroupCard(model: model, group: .enter, title: "Задержка",
                              summary: SettingsText.enter(model.sendDelay)) { EnterGroup(model: model) }
            SettingsGroupCard(model: model, group: .chats, title: "Чаты",
                              summary: SettingsText.chats(bypass: model.bypassNew)) { ChatsGroup(model: model) }
            SettingsGroupCard(model: model, group: .pinned, title: "Закреплённые чаты",
                              summary: SettingsText.pinned(model.pinnedLook)) { PinnedGroup(model: model) }
            SettingsGroupCard(model: model, group: .windows, title: "Окна и Mac",
                              summary: SettingsText.windows(model.toggles)) { windowsGroup }
            SettingsGroupCard(model: model, group: .updates, title: "Обновления",
                              summary: SettingsText.updates(model.update, patch: model.patch)) { updatesGroup }
            SettingsGroupCard(model: model, group: .more, title: "Дополнительно",
                              summary: SettingsText.more(autoAllow: autoAllowToggle?.on ?? false)) { moreGroup }
            footer.padding(.top, 2)
        }
    }

    var autoAllowToggle: PanelToggle? {
        model.toggles.first { $0.id == AutomationDefaults.allowOnceKey }
    }

    var autoAllowBinding: Binding<Bool> {
        Binding(get: { autoAllowToggle?.on ?? false }, set: { on in
            guard let toggle = autoAllowToggle, toggle.on != on else { return }
            model.actions.toggle(toggle.id)
        })
    }

    // MARK: группы без своего состояния

    private var windowsGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsText.windowToggles(model.toggles)) { toggle in
                SettingsSwitchRow(title: toggle.title, on: toggle.on, needsAccess: toggle.needsAccess,
                                  help: toggle.toolTip) { model.actions.toggle(toggle.id) }
            }
            TempMinMenu(selected: model.tempMin) { model.pickTempMin($0) }
            SettingsActionRow(title: "Разрешения macOS…", chevron: true) { model.actions.setup() }
            // #10464: право управлять Терминалом — заголовки окон терминалов и показ окна по нажатию в панели.
            SettingsActionRow(title: SettingsText.terminalAccess(model.terminalAccess),
                              color: model.terminalAccess == .allowed ? PanelColor.sub : PanelColor.text,
                              chevron: model.terminalAccess != .allowed) { model.askTerminalAccess() }
        }
    }

    private var updatesGroup: some View {
        let update = SettingsText.update(model.update)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                VersionRow(title: "Claude \(SettingsText.claudeVersion(model.patch) ?? "—")", text: update.text,
                           good: model.update == .none)
                Spacer(minLength: 6)
                if update.ready { SmallButton(title: "Обновить") { Self.pressUpdate(model) } }
            }
            .frame(minHeight: 36)
            ForEach(model.selfUpdate.rows, id: \.title) { row in
                VersionRow(title: "\(row.title) \(row.version)", text: row.text, good: row.good).frame(minHeight: 36)
            }
            SettingsSwitchRow(title: "Обновлять PMP и Viewer самим", on: model.selfUpdate.on,
                              help: "Новая версия скачивается заранее, проверяется по подписи автора и встаёт при запуске Claude или PMP",
                              caption: nil) {
                model.actions.selfUpdate(!model.selfUpdate.on)
            }
            SettingsActionRow(title: "Снять патч…", color: PanelColor.danger) { model.actions.uninstall() }
        }
    }

    /// «Обновить» в группе: сперва лист «Панель» — там карточка обновления со всеми состояниями
    /// (вопрос «идут чаты — обновить всё равно?» рисуется только там), потом само обновление. Скрытая крестиком
    /// карточка (#10765) возвращается — иначе вопрос было бы негде показать.
    static func pressUpdate(_ model: PanelModel) {
        withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
            model.settingsGroup = nil
            model.sheet = .panel
            model.hiddenUpdateVersion = nil
        }
        model.actions.update()
    }

    private var moreGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            // «Запросы команды» сняты словом Элвиса 11.10.2026 07:00; «Allow once» вернулся 16.10 (#9998).
            if let toggle = autoAllowToggle {
                SettingsSwitchRow(title: toggle.title, on: toggle.on, help: toggle.toolTip,
                                  caption: SettingsText.autoAllowCaption) {
                    autoAllowBinding.wrappedValue = !toggle.on
                }
            }
            if let toggle = model.toggles.first(where: { $0.id == AutomationDefaults.continueKey }) {
                SettingsSwitchRow(title: SettingsText.continueTitle, on: toggle.on, mixed: toggle.mixed,
                                  help: toggle.toolTip, caption: SettingsText.continueCaption) {
                    model.actions.toggle(toggle.id)
                }
            }
            AutoRetryRows(model: model)
            rickRow
            SettingsActionRow(title: model.archiving ? "Сохраняю чаты…" : "Сохранить все чаты в архив",
                              color: model.archiving ? PanelColor.sub : PanelColor.text) {
                guard !model.archiving else { return }
                model.actions.archiveChats()
            }
            .disabled(model.archiving)
            .help("Все чаты Claude Code одним zip с оглавлением — на склад «_Не удалять/Склад чатов Claude»")
            SettingsActionRow(title: "Открыть PimpViewer") { model.actions.showViewer() }
                .help("Все HTML и фото всех чатов одной лентой")
            // Виджеты панели (WF129, #9043): порядок и ширина блоков — как было.
            SettingsActionRow(title: model.layout.isStandard ? "Блоки панели — как было" : "Блоки панели — вернуть как было",
                              color: model.layout.isStandard ? PanelColor.sub : PanelColor.text) {
                model.changeLayout { $0 = .standard }
            }
            .disabled(model.layout.isStandard)
            .help("Порядок и ширина блоков меняются ручкой в углу блока и правым кликом")
            if model.donateAvailable {
                // Одна тихая строка без цифр (WF227, кадр 37.9): счёт и способы оплаты живут только в окне.
                SettingsActionRow(title: "Поддержать автора") { model.actions.donate() }
                    .help("Окно «Поддержать автора»: кто делает PMP и как сказать спасибо")
            }
        }
    }

    /// Рик — житель Пимпа (WF216): у тех, кто ставил Пимп раньше, — тихая строка, пока папки Rick нет.
    @ViewBuilder private var rickRow: some View {
        switch model.rick {
        case .hidden: EmptyView()
        case .done(let path):
            // Путь — своей строкой под кнопкой, как подпись у «Поставить Рика»: рядом с кнопкой он не помещается.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Рик стоит").font(.system(size: 13)).foregroundColor(PanelColor.text)
                    Spacer(minLength: 6)
                    SmallButton(title: "Показать в Finder", primary: false) { model.actions.revealRick() }
                }
                .frame(minHeight: 28)
                // WF253: путь целиком — переносится, а не режется «…» посередине.
                Text(path).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
        case .idle, .running, .failed:
            let running = model.rick == .running
            VStack(alignment: .leading, spacing: 0) {
                SettingsActionRow(title: running ? "Ставлю Рика…" : "Поставить Рика",
                                  color: running ? PanelColor.sub : PanelColor.text) {
                    guard !running else { return }
                    model.actions.installRick()
                }
                .disabled(running)
                Text(model.rick.caption).font(.system(size: 11))
                    .foregroundColor(model.rick.isFailed ? PanelColor.warn : PanelColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
        }
    }

    /// «О программе» · «Выйти ⌘Q» — подписи-ссылки одной строкой (§7.7; «Снять патч…» — в «Обновлениях»).
    private var footer: some View {
        HStack(spacing: 6) {
            FooterLink(title: "О программе") { model.actions.about() }
            Text("·").font(.system(size: 11)).foregroundColor(PanelColor.sub)
            FooterLink(title: "Выйти ⌘Q") { model.actions.quit() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

/// Карточка группы, как у PimpTray (#10308): заголовок 40 pt — имя подписью набора (капсом серым) слева, сводка справа,
/// шеврон вниз или вверх; открыта — волосок под заголовком и содержимое.
private struct SettingsGroupCard<Content: View>: View {
    @ObservedObject var model: PanelModel
    let group: SettingsGroup
    let title: String
    let summary: String
    @ViewBuilder let content: () -> Content
    @State private var hover = false
    @Environment(\.panelType) private var type

    var body: some View {
        let open = model.settingsGroup == group
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(model.reduceMotion ? .easeOut(duration: 0.15) : PanelSpring.settings) {
                    model.settingsGroup = open ? nil : group
                }
            } label: {
                HStack(spacing: 8) {
                    type.label.text(title).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 6)
                    // WF253: длинная сводка (текст ошибки обновления) не режется «…» — её нет, слова внутри группы.
                    ViewThatFits(in: .horizontal) {
                        Text(summary).font(.system(size: 11))
                            .foregroundColor(summary == "нужен доступ" ? PanelColor.warn : PanelColor.sub).fixedSize()
                        Color.clear.frame(width: 0, height: 0)
                    }
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PanelColor.sub)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Color.white.opacity(hover ? 0.06 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .onHover { hover = $0 }
            .handCursor()
            .accessibilityLabel(title)
            .accessibilityValue(open ? "Открыто" : "Свёрнуто")
            if open {
                Rectangle().fill(PanelColor.frame).frame(height: 1).padding(.horizontal, 12)
                content()
                    .padding(EdgeInsets(top: 6, leading: 12, bottom: 10, trailing: 12))
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .card()
    }
}

/// Строка-переключатель группы: подпись 13, справа — `Switch` (или «нужен доступ» / «сохранённые»), под ней — подпись 11.
struct SettingsSwitchRow: View {
    let title: String
    let on: Bool
    var needsAccess = false
    var mixed = false
    var help = ""
    var caption: String?
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13)).foregroundColor(PanelColor.text).lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 6)
                    if needsAccess {
                        Text("нужен доступ").font(.system(size: 11, weight: .semibold)).foregroundColor(PanelColor.warn)
                    } else if mixed {
                        Text("сохранённые").font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    } else {
                        Switch(on: on)
                    }
                }
                .frame(minHeight: 28)
                if let caption = caption {
                    Text(caption).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, caption == nil ? 0 : 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(hover ? 0.06 : 0)))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : PanelSpring.press, value: hover)
        .handCursor()
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(needsAccess ? "нужен доступ" : (on ? "Включено" : "Выключено"))
    }
}

/// Строка-кнопка группы: наведение — фон светлее.
struct SettingsActionRow: View {
    let title: String
    var color: Color = PanelColor.text
    var chevron = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13)).foregroundColor(color)
                Spacer(minLength: 6)
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PanelColor.sub)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(hover ? 0.06 : 0)))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { hover = $0 }
        .handCursor()
    }
}

/// Сегменты 24 pt: выбранный — заливка акцентом.
struct Segments<Value: Hashable>: View {
    let items: [(value: Value, title: String)]
    let selected: Value
    /// Подсказка сегмента под курсором; nil — без неё.
    var help: (Value) -> String? = { _ in nil }
    let pick: (Value) -> Void
    @Environment(\.pmpAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let chosen = item.value == selected
                Button { if !chosen { pick(item.value) } } label: {
                    Text(item.title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundColor(chosen ? PanelColor.ink : PanelColor.text)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(chosen ? accent : Color.white.opacity(hovered == index ? 0.14 : 0.08)))
                }
                .buttonStyle(PressStyle())
                .onHover { inside in
                    if inside { hovered = index } else if hovered == index { hovered = nil }
                }
                .animation(reduceMotion ? nil : PanelSpring.press, value: hovered)
                .handCursor()
                .help(help(item.value) ?? "")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

/// Подпись над сегментами: имя 13 и пояснение 11.
private func settingsLabel(_ title: String, _ hint: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(title).font(.system(size: 13)).foregroundColor(PanelColor.text)
        if let hint = hint { Text(hint).font(.system(size: 11)).foregroundColor(PanelColor.sub) }
        Spacer(minLength: 0)
    }
    .padding(.top, 6)
}

struct FooterLink: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11)).foregroundColor(hover ? PanelColor.text : PanelColor.sub)
                .underline(hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .handCursor()
    }
}

// MARK: «Задержка» (§7.2; WF180)

/// «Задержка» (WF180, слово Элвиса 09.10 02:50: «Отправка по Enter 3 секунды; "второй Enter" — не второй, а Enter, пока
/// идёт отсчёт; Shift+Enter убери вообще; "Сделать баннер на завтра" — убери… не "отправка", а "задержка"»): сегменты
/// задержки, Enter во время отсчёта — выключатель «отменить», Esc — отмена всегда, звук, показ в окне. Строки — тем же
/// видом, что остальные группы: подпись слева, значение справа; без эмодзи.
enum EnterGroupText {
    static let secondItems: [(value: EnterKeys.Second, title: String)] = [(.cancel, "отменяет"), (.send, "отправляет сразу")]
    static let keysHint = "Подсказка: Esc отменяет отправку, ⇧Enter, ⌘Enter и ⌥Enter переносят строку."
}

/// Строка «Обновлений»: продукт с версией и что с ним; всё хорошо — цветом акцента (слово 03.11.2026), красный и янтарь — см. `PanelColor.good`.
private struct VersionRow: View {
    let title: String
    let text: String
    let good: Bool
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13)).foregroundColor(PanelColor.text)
            Text(text).font(.system(size: 11)).foregroundColor(good ? PanelColor.good(accent) : PanelColor.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EnterGroup: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let delay = model.sendDelay
        let keys = model.enterKeys
        VStack(alignment: .leading, spacing: 2) {
            Segments(items: PanelCountdown.delayItems,
                     selected: delay.on ? delay.seconds : 0) { seconds in
                model.actions.sendDelay(seconds != 0, seconds == 0 ? delay.seconds : seconds)
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
            if delay.on {
                // Выбор из двух (слово Элвиса 11.10.2026 07:00: «Как бы вторую нужно. Кому-то нравится ещё раз Enter»).
                HStack {
                    Text("Enter во время отсчёта").font(.system(size: 13)).foregroundColor(PanelColor.text)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 28)
                Segments(items: EnterGroupText.secondItems, selected: keys.second) { second in
                    model.actions.enterKeys(EnterKeys(second: second, shift: keys.shift))
                }
                .padding(.bottom, 4)
                CountdownSoundMenu(selected: model.countdownSound) { model.actions.countdownSound($0) }
                SettingsActionRow(title: "Показать в окне Claude", chevron: true) {
                    model.actions.previewSendDelay(delay.seconds)
                }
                .help("Показать отсчёт в окне Claude, ничего не отправляя")
            }
            if let line = model.sendDelayLine {
                Text(line).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if delay.on {
                // Клавиши — не настройки, а подсказка: мелко и серым, под всеми строками.
                Text(EnterGroupText.keysHint).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }
}

/// «Градусы у часов» (#10289): с какой температуры значок показывает градусы; ниже — только проценты.
private struct TempMinMenu: View {
    let selected: Int
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Градусы у часов").font(.system(size: 13)).foregroundColor(PanelColor.text)
            Spacer(minLength: 6)
            Menu {
                ForEach(StatusIcon.tempMinChoices, id: \.self) { value in
                    Button { if value != selected { pick(value) } } label: {
                        let name = StatusIcon.tempMinName(value)
                        if value == selected { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            } label: {
                Text(StatusIcon.tempMinName(selected)).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .handCursor()
        }
        .frame(minHeight: 28)
        .help("Ниже порога у часов только проценты; macOS говорит «перегрев» — градусы видны всегда")
        .accessibilityLabel("Градусы у часов: \(StatusIcon.tempMinName(selected))")
    }
}

/// «Звук» (WF151, #9108; WF180 — без эмодзи): строка «Звук · выбранный», по нажатию — список из пяти, галка у текущего.
private struct CountdownSoundMenu: View {
    let selected: CountdownSound
    let pick: (CountdownSound) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Звук").font(.system(size: 13)).foregroundColor(PanelColor.text)
            Spacer(minLength: 6)
            Menu {
                ForEach(CountdownSound.allCases, id: \.self) { sound in
                    Button { if sound != selected { pick(sound) } } label: {
                        if sound == selected { Label(sound.name, systemImage: "checkmark") } else { Text(sound.name) }
                    }
                }
            } label: {
                Text(selected.name).font(.system(size: 11)).foregroundColor(PanelColor.sub)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .handCursor()
        }
        .frame(minHeight: 28)
        .accessibilityLabel("Звук отсчёта: \(selected.name)")
    }
}

// MARK: «Значок» (WF180, WF189)

/// «Значок» (WF180; WF189 — под «Цвет PMP», слово Элвиса 09.10 04:00: «варианты отображения в строке меню, как
/// раньше… иконками чик-чик-чик, можно было выбрать. Как с цветами сделай»): картинки вариантов (`StatusIcon.Variant`)
/// сеткой по четыре на полосе цвета строки меню, последний ряд — двумя широкими (по две колонки); выбранный в рамке,
/// имя — подсказкой.
struct IconGroup: View {
    @ObservedObject var model: PanelModel
    static let columns = 4
    static let spacing: CGFloat = 6

    /// #11170 (WF297): ряды сетки — варианты по четыре, а широкие со сводкой проектов («⏳ 3 · ✋ 1 · WF 27/27») — на
    /// свободные колонки последнего ряда и дальше во всю ширину: втроём в ряд они ужимались вдвое и не читались.
    static var rows: [[(variant: StatusIcon.Variant, span: Int)]] {
        let all = StatusIcon.Variant.allCases
        let narrow = all.filter { !$0.showsProjects }
        var rows = stride(from: 0, to: narrow.count, by: columns).map { start in
            narrow[start..<min(start + columns, narrow.count)].map { (variant: $0, span: 1) }
        }
        for variant in all where variant.showsProjects {
            let used = rows.last.map { $0.reduce(0) { $0 + $1.span } } ?? columns
            if used < columns { rows[rows.count - 1].append((variant, columns - used)) }
            else { rows.append([(variant, columns)]) }
        }
        return rows
    }

    var body: some View {
        Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row, id: \.variant) { cell in
                        IconTile(image: IconSample.image(cell.variant, accent: model.shownAccent.nsColor,
                                                         projects: summary, limits: model.limits),
                                 name: cell.variant.name, selected: model.iconVariant == cell.variant) {
                            if model.iconVariant != cell.variant { model.actions.iconVariant(cell.variant) }
                        }
                        .gridCellColumns(cell.span)
                    }
                }
            }
        }
    }

    /// Сводка проектов на образце: настоящая, если проекты уже читали.
    private var summary: String {
        guard let snapshot = model.projects else { return IconSample.projects }
        let text = PanelTiles.summary(PanelTiles.groups(snapshot, now: model.now))
        return text.isEmpty ? IconSample.projects : text
    }
}

/// Образцы вариантов значка: та же кисть, что у строки меню (`StatusIconArt`), на тёмной полосе.
enum IconSample {
    static let projects = "⏳ 2 · WF 3/8"

    /// #11170 (WF297): числа — настоящие лимиты, что у часов; их ещё не читали — прежний образец 37/24/8.
    static func look(_ variant: StatusIcon.Variant, projects: String = projects, limits: ClaudeLimits? = nil,
                     now: Date = Date()) -> StatusIcon.Look {
        let limits = limits ?? ClaudeLimits(at: now, plan: nil, fiveHour: .init(used: 24, resetsAt: nil),
                                            weekly: .init(used: 37, resetsAt: nil), fable: .init(used: 8, resetsAt: nil),
                                            source: "api")
        let base = StatusIcon.look(mode: variant.mode, limits: limits, patch: .unknown, phase: .idle, now: now)
        return StatusIcon.compose(base, variant: variant, summary: projects, toolTip: "")
    }

    static func image(_ variant: StatusIcon.Variant, accent: NSColor, projects: String = projects,
                      limits: ClaudeLimits? = nil) -> NSImage {
        StatusIconArt.image(look(variant, projects: projects, limits: limits), dark: true, accent: accent)
    }
}

/// Плитка варианта значка — тем же видом, что плитка цвета (`ColorTile`): высота 28, скругление 8, рамка
/// выбранного 2 pt снаружи.
private struct IconTile: View {
    let image: NSImage
    let name: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            // WF210 (#9379 п. 2): картинка шире плитки ужимается, а не распирает блок — настоящая сводка проектов
            // («⏳ 3 · ✋ 5 · WF 127/133») на двух широких плитках не помещалась в ряд и сдвигала всю панель влево.
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: AccentCard.tile)
                .background(shape.fill(PanelColor.hex(0x1C1C1E)))
                .overlay(shape.strokeBorder(Color.white.opacity(hovering ? 0.30 : 0.18), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PanelColor.text, lineWidth: selected ? 2 : 0).padding(-3))
                .scaleEffect(hovering ? 1.04 : 1)
                .animation(PanelSpring.press, value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .handCursor()
        .help(name)
        .accessibilityLabel("Значок: " + name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: «Чаты» (§7.3)

private struct ChatsGroup: View {
    @ObservedObject var model: PanelModel
    @Environment(\.pmpAccent) private var accent

    var body: some View {
        let line = SettingsText.permission(model.bypassPermission)
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("+").font(.system(size: 15)).foregroundColor(PanelColor.sub)
                    ForEach(Array(ChatSample.chips(bypass: model.bypassNew).enumerated()), id: \.offset) { index, text in
                        chip(text, lit: index == 0 && model.bypassNew)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PanelColor.hex(0x2B2440)))
                Text("так начнётся новый чат из PMP").font(.system(size: 11)).foregroundColor(PanelColor.sub)
            }
            .accessibilityElement(children: .combine)
            SettingsSwitchRow(title: BypassNew.menuTitle, on: model.bypassNew,
                              caption: "Claude не спрашивает разрешений: сам правит файлы и запускает команды. Включай только для своих проектов. PMP ставит Bypass в каждом открытом чате и в новых; чат, где ты сам выбрал режим, не трогает. Claude один раз на проект спросит подтверждение — подтверди сам.") {
                model.actions.bypassNew(!model.bypassNew)
            }
            .padding(.top, 4)
            Text(line.text).font(.system(size: 11, weight: line.good || line.warn ? .semibold : .regular))
                .foregroundColor(line.good ? PanelColor.good(accent) : (line.warn ? PanelColor.warn : PanelColor.sub))
            if line.link {
                LinkButton(title: model.claudeSettingsFailed ? "Claude → Settings…" : "Открыть настройки Claude") {
                    model.actions.openClaudeSettings()
                }
                .handCursor()
            }
        }
    }

    private func chip(_ text: String, lit: Bool) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            .foregroundColor(lit ? accent : PanelColor.sub)
            .padding(.horizontal, 5).frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(lit ? accent : Color.clear, lineWidth: 1))
    }
}

/// #11169 (WF297): образец нового чата словами — режим, модель, усилие, а не «BY 055 HI».
enum ChatSample {
    static func chips(bypass: Bool) -> [String] {
        [bypass ? "Bypass" : "Ask permissions", "Opus 5.5", "high"]
    }
}

// MARK: «Закреплённые чаты» (§7.4)

/// С WF245 выключателя «Таймер кеша» нет: таймеров у закреплённых чатов страница не рисует с page-64. Поле `clock`
/// команды `pinned-look` остаётся в контракте (страница его принимает и ничего с ним не делает) и уходит как хранилось.

private struct PinnedGroup: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let look = model.pinnedLook
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Pinned").font(.system(size: 11)).foregroundColor(PanelColor.sub)
                row(look, project: "VkusnoffKz", title: "Корзина и варианты…")
                row(look, project: "Rick", title: "Рик чат для Элвиса")
                row(look, project: "PimpMyClaude", title: "Ночь 07.10")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PanelColor.hex(0x2A1640)))
            .animation(model.reduceMotion ? nil : PanelSpring.press, value: look)
            .accessibilityElement(children: .combine)
            Text("так выглядит список слева").font(.system(size: 11)).foregroundColor(PanelColor.sub)
            SettingsSwitchRow(title: "Название проекта", on: look.folder,
                              caption: "имя папки перед названием чата") {
                model.actions.pinnedLook(PinnedLook(folder: !look.folder))
            }
            .padding(.top, 4)
        }
    }

    private func row(_ look: PinnedLook, project: String, title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(PanelColor.sub).frame(width: 4, height: 4)
            if look.folder {
                Text(project).font(.system(size: 11)).foregroundColor(PanelColor.text)
                    .padding(.horizontal, 5).frame(height: 16)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.10)))
                    .transition(.opacity)
            }
            Text(title).font(.system(size: 13)).foregroundColor(PanelColor.text).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: «Шрифт панели» (WF255)

/// «Шрифт панели» (WF255; слово Элвиса 17.10.2026 06:00 по листу 47: «эти берём по шрифтам и возможность выбора
/// сделай»): наборы строками — образец «50%» героем набора, имя его подписью, у выбранного галка. Нажатие — вся
/// панель сразу этим набором; чем набор хорош — подсказкой.
private struct TypographyGroup: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(PanelTypography.all, id: \.number) { type in
                TypographyRow(type: type, selected: model.typography == type) { model.chooseTypography(type) }
            }
        }
        .padding(.top, 2)
    }
}

/// Строка набора: высота у всех одна (44), образец процентов — в колонке 64 слева, имена — по одной линии.
private struct TypographyRow: View {
    let type: PanelTypography
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    @Environment(\.pmpAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Образец — герой набора в 0,6 его кегля: крупный набор и в списке крупнее.
    static let sampleScale: CGFloat = 0.6

    var body: some View {
        Button { if !selected { action() } } label: {
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    scaled(type.hero).text("50").fixedSize()
                    scaled(type.unit).text("%").fixedSize()
                }
                .frame(width: 64, alignment: .leading)
                // Имя подписью набора; не входит — обычным текстом 13, без «…».
                ViewThatFits(in: .horizontal) {
                    type.label.text(type.name).fixedSize()
                    Text(type.name).font(.system(size: 13)).foregroundColor(PanelColor.text).fixedSize()
                }
                Spacer(minLength: 6)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent).opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.08 : (hover ? 0.06 : 0))))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : PanelSpring.press, value: hover)
        .handCursor()
        .help(type.hint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Шрифт панели: \(type.name)")
        .accessibilityHint(type.hint)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func scaled(_ style: PanelTextStyle) -> PanelTextStyle {
        var copy = style
        copy.size = (style.size * Self.sampleScale).rounded()
        return copy
    }
}

// MARK: «Текст» (WF167, #9168)

/// Выравнивание ответов и поля по бокам — для всех окон сразу; быстрый ползунок «↔️ Поля» на «−» остаётся.
private struct TextGroup: View {
    @ObservedObject var model: PanelModel
    static let alignItems: [(value: Bool, title: String)] = [(false, "Влево"), (true, "По ширине")]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextPreview(justify: model.textJustify, padding: model.sidePadding)
                .animation(model.reduceMotion ? nil : PanelSpring.press, value: model.textJustify)
                .animation(model.reduceMotion ? nil : PanelSpring.press, value: model.sidePadding)
            Text("так ляжет ответ в окне Claude").font(.system(size: 11)).foregroundColor(PanelColor.sub)
            settingsLabel("Выравнивание")
            Segments(items: Self.alignItems, selected: model.textJustify) { model.actions.textJustify($0) }
            settingsLabel("Поля", "по бокам, px")
            MarkSlider(value: model.sidePadding) { model.actions.sidePadding($0) }
            // WF210 (#9398, К-CA): служебные строки под ответом — расход и состояние; «Работа идёт» остаётся.
            SettingsSwitchRow(title: CleanAnswers.title, on: model.cleanAnswers, caption: CleanAnswers.caption) {
                model.actions.cleanAnswers(!model.cleanAnswers)
            }
            .padding(.top, 4)
        }
    }
}

/// Превью колонки ответа: абзац полосками; по ширине — строки до правого края, кроме последней; поля — отступ
/// с обеих сторон (половина пикселей окна — превью в половину ширины колонки).
private struct TextPreview: View {
    let justify: Bool
    let padding: Int
    static let ragged: [CGFloat] = [0.94, 0.82, 0.97, 0.88, 0.55]

    var body: some View {
        GeometryReader { geo in
            let inset = 6 + CGFloat(padding) / 2
            let width = max(0, geo.size.width - inset * 2)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Self.ragged.indices, id: \.self) { index in
                    let last = index == Self.ragged.count - 1
                    Capsule().fill(PanelColor.text.opacity(0.55))
                        .frame(width: width * (justify && !last ? 1 : Self.ragged[index]), height: 4)
                }
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 10)
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PanelColor.hex(0x262624)))
        .accessibilityElement()
        .accessibilityLabel("Так ляжет ответ: \(justify ? "по ширине" : "влево"), поля \(padding)")
    }
}

/// «Поля» 0…40: дорожка с отметками 24/32/40 (нажатие на число — встать на отметку), значение справа.
/// Тянуть и щёлкать по дорожке — живо, каждый шаг сразу в claude.json (лоадер подхватит за ~1 с).
struct MarkSlider: View {
    let value: Int
    var range = TextLook.paddingRange
    var marks = TextLook.paddingMarks
    /// Шаг значения: поля — по одному, размер отсчёта (WF242) — по десять.
    var step = 1
    var unit = "px"
    var label = "Поля по бокам"
    let change: (Int) -> Void
    @Environment(\.pmpAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var dragging = false
    private let knob: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GeometryReader { geo in
                let track = max(1, geo.size.width - knob)
                VStack(spacing: 2) {
                    ZStack(alignment: .topLeading) {
                        let fill = x(value, track) - knob / 2
                        Capsule().fill(Color.white.opacity(0.14)).frame(width: track, height: 4)
                            .position(x: knob / 2 + track / 2, y: 9)
                        Capsule().fill(accent).frame(width: fill, height: 4)
                            .position(x: knob / 2 + fill / 2, y: 9)
                        ForEach(marks, id: \.self) { mark in
                            Circle().fill(mark <= value ? PanelColor.ink.opacity(0.5) : PanelColor.sub)
                                .frame(width: 3, height: 3)
                                .position(x: x(mark, track), y: 9)
                        }
                        Circle().fill(Color.white)
                            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                            .frame(width: knob, height: knob)
                            .scaleEffect(hover || dragging ? 1.15 : 1)
                            .position(x: x(value, track), y: 9)
                    }
                    .frame(width: geo.size.width, height: 18)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            dragging = true
                            let next = snapped(at: drag.location.x, track)
                            if next != value { change(next) }
                        }
                        .onEnded { _ in dragging = false })
                    .onHover { hover = $0 }
                    ZStack(alignment: .topLeading) {
                        ForEach(marks, id: \.self) { mark in
                            Text("\(mark)").font(.system(size: 10)).monospacedDigit()
                                .foregroundColor(mark == value ? PanelColor.text : PanelColor.sub)
                                .fixedSize()
                                .frame(width: 26, height: 14)
                                .contentShape(Rectangle())
                                .onTapGesture { if mark != value { change(mark) } }
                                .handCursor()
                                .position(x: x(mark, track), y: 7)
                        }
                    }
                    .frame(width: geo.size.width, height: 14, alignment: .topLeading)
                }
            }
            .frame(height: 34)
            .animation(reduceMotion ? nil : PanelSpring.press, value: hover || dragging)
            Text(unit == "px" ? "\(value)" : "\(value) \(unit)").font(.system(size: 13)).monospacedDigit()
                .foregroundColor(PanelColor.text)
                .frame(width: unit == "px" ? 22 : 44, height: 18, alignment: .trailing)
        }
        .handCursor()
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { change(min(value + step, range.upperBound)) }
            case .decrement: if value > range.lowerBound { change(max(value - step, range.lowerBound)) }
            @unknown default: break
            }
        }
    }

    /// Центр бегунка для значения: от knob/2 до ширины − knob/2.
    private func x(_ value: Int, _ track: CGFloat) -> CGFloat {
        let span = CGFloat(range.upperBound - range.lowerBound)
        return knob / 2 + track * CGFloat(min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span
    }

    private func snapped(at location: CGFloat, _ track: CGFloat) -> Int {
        let span = Double(range.upperBound - range.lowerBound)
        let raw = Double((location - knob / 2) / track) * span + Double(range.lowerBound)
        let stepped = Int((raw / Double(step)).rounded()) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}
