import AppKit

/// Короткая плашка по центру экрана — то же, что `hs.alert.show` в Lua-модулях
/// (авто-Allow сообщает о нажатии, ⌘Q — как выйти). Окно без рамки, не забирает фокус
/// и не ловит мышь, поэтому разрешений не требует и ничего не перехватывает.
final class HUD {
    private var window: NSWindow?
    private var hide: DispatchWorkItem?

    func show(_ text: String, seconds: TimeInterval = 1.5) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding = NSSize(width: 24, height: 14)
        let size = NSSize(width: min(label.frame.width, 620) + padding.width * 2,
                          height: label.frame.height + padding.height * 2)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.minY + visible.height * 0.18)

        let panel = window ?? makeWindow()
        window = panel
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        if let box = panel.contentView {
            box.subviews.forEach { $0.removeFromSuperview() }
            label.frame = NSRect(x: padding.width, y: padding.height,
                                 width: size.width - padding.width * 2, height: label.frame.height)
            label.autoresizingMask = [.width]
            box.addSubview(label)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.window else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func stop() {
        hide?.cancel()
        hide = nil
        window?.orderOut(nil)
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let panel = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let box = NSView(frame: .zero)
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        box.layer?.cornerRadius = 12
        box.autoresizingMask = [.width, .height]
        panel.contentView = box
        return panel
    }
}
