import ClaudeAX
import Foundation

/// Сторож контекста (пожелания 03.11.2026, раздел 0): проверка при открытии панели и раз в минуту с `show(state:)`,
/// одна кнопка установки.
extension AppDelegate {
    /// Идущую установку не трогаем; ошибка держится, пока сторож не встал, иначе её смыло бы следующим открытием.
    func refreshKontekst() {
        let installed = KontekstGuard.isInstalled
        switch panel.model.kontekst {
        case .running: break
        case .failed: if installed { panel.model.kontekst = .ok }
        case .ok, .missing: panel.model.kontekst = installed ? .ok : .missing
        }
    }

    func installKontekst() {
        guard panel.model.kontekst != .running else { return }
        panel.change { panel.model.kontekst = .running }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = KontekstGuard.install()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.panel.change { self.panel.model.kontekst = KontekstInstall(outcome) }
                self.refreshIcon()
            }
        }
    }
}
