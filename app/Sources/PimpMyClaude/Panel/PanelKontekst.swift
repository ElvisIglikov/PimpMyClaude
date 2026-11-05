import ClaudeAX
import SwiftUI

/// Строка «Сторож контекста» в панели: `ok` — строки нет.
enum KontekstInstall: Equatable {
    case ok
    case missing
    case running
    case failed(String)

    init(_ outcome: KontekstGuard.Outcome) {
        switch outcome {
        case .installed: self = .ok
        case .failed(let why): self = .failed(why)
        }
    }

    /// Зачем сторож — простыми словами; эту же фразу показывает окно первого запуска.
    static let why = "Каждый шаг большого чата заново перечитывает весь чат, поэтому подписка горит быстрее. "
        + "На 140 000 токенов сторож скажет чату записать, где остановился. "
        + "Чат ответит «готов к смене»: открой новый чат и напиши «продолжи с HANDOFF.md»."
}

/// Нет сторожа — видно сразу под шапкой. Крестика нет: работать без него нельзя (раздел 0 пожеланий).
struct KontekstGuardCard: View {
    @ObservedObject var model: PanelModel
    @Environment(\.panelType) private var type

    var body: some View {
        let running = model.kontekst == .running
        VStack(alignment: .leading, spacing: 8) {
            type.label.text("Сторож контекста не стоит")
            Text(KontekstInstall.why).font(.system(size: 11)).foregroundColor(PanelColor.sub)
                .fixedSize(horizontal: false, vertical: true)
            BigButton(title: running ? "Ставлю сторож…" : "Поставить сторож", enabled: !running) {
                model.actions.installKontekst()
            }
            if case .failed(let why) = model.kontekst {
                Text("Сторож не встал: \(why)").font(.system(size: 11)).foregroundColor(PanelColor.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
