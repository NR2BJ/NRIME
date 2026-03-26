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

    /// Whether the indicator is actively displayed (not fading or hidden).
    var isVisible: Bool {
        guard let panel = panel else { return false }
        return panel.isVisible && panel.alphaValue > 0 && !isFading
    }

    /// Show the mode indicator near the caret position.
    func show(for mode: InputMode, client: (any IMKTextInput)? = nil) {
        fadeTimer?.invalidate()

        let labelWidth: CGFloat = mode.label.count > 1 ? 36 : 26
        let panelSize = NSSize(width: labelWidth, height: 24)

        ensurePanel(for: mode, size: panelSize)
        guard let panel = panel else { return }

        // Get position — use whatever caretRect returns, including attributesAtZero.
        // Only skip if caretRect returns nil entirely.
        let origin: NSPoint
        if let result = TextInputGeometry.caretRect(for: client) {
            let gap: CGFloat = 4
            let x: CGFloat
            if result.source == .attributesAtZero {
                // Y is reliable, X is line start — use current panel X if visible, otherwise use rect X
                if panel.isVisible {
                    x = panel.frame.origin.x
                } else {
                    x = result.rect.origin.x + gap
                }
            } else {
                x = TextInputGeometry.indicatorAnchorX(for: result.rect) + gap
            }
            let aboveY = result.rect.origin.y + result.rect.height + gap
            if let screenFrame = TextInputGeometry.screenFrame(containing: result.rect),
               aboveY + panelSize.height > screenFrame.maxY {
                origin = NSPoint(x: x, y: result.rect.origin.y - panelSize.height - gap)
            } else {
                origin = NSPoint(x: x, y: aboveY)
            }
        } else if let client = client {
            // caretRect failed — try raw firstRect at position 0 as last resort
            var actual = NSRange(location: NSNotFound, length: 0)
            let rawRect = client.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: &actual)
            if rawRect.height > 0 && !rawRect.equalTo(.zero) {
                let gap: CGFloat = 4
                origin = NSPoint(x: rawRect.origin.x + gap, y: rawRect.origin.y + rawRect.height + gap)
            } else {
                return
            }
        } else {
            return
        }

        panel.setFrameOrigin(origin)
        isFading = false
        panel.alphaValue = 1.0
        panel.orderFront(nil)

        // Electron/Chromium: IMKit may return stale coordinates on the first call.
        // Re-check position after a short delay to catch updated caret rect.
        if let client = client {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, let panel = self.panel, panel.isVisible, !self.isFading else { return }
                if let result = TextInputGeometry.caretRect(for: client),
                   result.source != .attributesAtZero {
                    let gap: CGFloat = 4
                    let x = TextInputGeometry.indicatorAnchorX(for: result.rect) + gap
                    let aboveY = result.rect.origin.y + result.rect.height + gap
                    if let screenFrame = TextInputGeometry.screenFrame(containing: result.rect),
                       aboveY + panelSize.height > screenFrame.maxY {
                        panel.setFrameOrigin(NSPoint(x: x, y: result.rect.origin.y - panelSize.height - gap))
                    } else {
                        panel.setFrameOrigin(NSPoint(x: x, y: aboveY))
                    }
                }
            }
        }

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
