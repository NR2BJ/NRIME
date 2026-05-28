import Cocoa
import InputMethodKit

final class InlineIndicator {
    static let shared = InlineIndicator()

    private var panel: NSPanel?
    private var textField: NSTextField?
    private var fadeTimer: Timer?
    private var isFading = false
    private let displayDuration: TimeInterval = 1.0
    private let fadeDuration: TimeInterval = 0.3

    private init() {}

    var isVisible: Bool {
        guard let panel = panel else { return false }
        return panel.isVisible && panel.alphaValue > 0 && !isFading
    }

    /// Show the mode indicator.
    ///   "caret" — attributes(forCharacterIndex: 0), fail = don't show
    ///   "mouse" — NSEvent.mouseLocation, always works
    func show(for mode: InputMode, client: (any IMKTextInput)? = nil) {
        fadeTimer?.invalidate()

        let labelWidth: CGFloat = mode.label.count > 1 ? 36 : 26
        let panelSize = NSSize(width: labelWidth, height: 24)

        ensurePanel(for: mode, size: panelSize)
        guard let panel = panel else { return }

        let gap: CGFloat = 4
        let origin: NSPoint

        if Settings.shared.indicatorPositionMode == "mouse" {
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x + gap, y: mouse.y + gap)
        } else {
            // "caret" — use attributes(forCharacterIndex: 0)
            guard let client = client else { return }
            var rect = NSRect.zero
            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
            guard rect.height > 0 && !rect.equalTo(.zero) else { return }
            let onScreen = NSScreen.screens.contains { $0.frame.intersects(rect.insetBy(dx: -50, dy: -50)) }
            guard onScreen else { return }

            let aboveY = rect.origin.y + rect.height + gap
            if let screenFrame = TextInputGeometry.screenFrame(containing: rect),
               aboveY + panelSize.height > screenFrame.maxY {
                origin = NSPoint(x: rect.origin.x + gap, y: rect.origin.y - panelSize.height - gap)
            } else {
                origin = NSPoint(x: rect.origin.x + gap, y: aboveY)
            }
        }

        // Suppress screen corner failures
        if origin.x < 20 && origin.y < 20 { return }

        panel.setFrameOrigin(origin)
        panel.level = OverlayWindowLevel.frontmostOverlayLevel
        isFading = false
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        fadeTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isFading = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = self.fadeDuration
                self.panel?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.isFading = false
                self?.panel?.orderOut(nil)
            })
        }
    }

    // MARK: - Private

    private func ensurePanel(for mode: InputMode, size panelSize: NSSize) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.ignoresMouseEvents = true
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true

            let backgroundView = NSView(frame: NSRect(origin: .zero, size: panelSize))
            backgroundView.wantsLayer = true
            backgroundView.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.85).cgColor
            backgroundView.layer?.cornerRadius = 6

            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            tf.textColor = .white
            tf.alignment = .center
            tf.frame = NSRect(origin: .zero, size: panelSize)
            backgroundView.addSubview(tf)

            p.contentView = backgroundView
            self.panel = p
            self.textField = tf
        }

        guard let panel = panel, let textField = textField else { return }
        textField.stringValue = mode.label
        panel.setContentSize(panelSize)
        panel.contentView?.frame = NSRect(origin: .zero, size: panelSize)
        textField.frame = NSRect(origin: .zero, size: panelSize)
    }
}
