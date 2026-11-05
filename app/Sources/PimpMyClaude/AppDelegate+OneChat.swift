import AppKit
import ClaudeAX

extension AppDelegate {
    // MARK: - «Всё в одном чате» без Рика (#9552, К-OC)

    func wireOneChat() {
        ax.onRickSetupRequest = { [weak self] in self?.showRickSetup() }
    }

    /// Кнопка «Всё в одном чате» в окне Claude, а папки Rick нет: панель у часов — лист «Настройки», группа
    /// «Дополнительно» со строкой «Поставить Рика». Без проверки `closedJustNow`, как у кнопки «PMP»: клик в окне Claude
    /// сам закрывает открытую панель, а здесь её надо открыть.
    func showRickSetup() {
        openPanel()
        // Строку «Поставить Рика» `onOpen` пересчитывает только на открытии — панель могла быть уже открыта.
        switch panel.model.rick {
        case .running, .done: break
        case .hidden, .idle, .failed: panel.model.rick = RickKit.isPresent ? .hidden : .idle
        }
        panel.showSheet(.settings)
        panel.change { panel.model.settingsGroup = .more }
    }
}
