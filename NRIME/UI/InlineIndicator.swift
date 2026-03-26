import Cocoa
import InputMethodKit

final class InlineIndicator {
    static let shared = InlineIndicator()

    private var panel: NSPanel?
    private var textField: NSTextField?
    private var fadeTimer: Timer?
    private let displayDuration: TimeInterval = 1.0
    private let fadeDuration: TimeInterval = 0.3

    private init() {}

    /// Whether the indicator is currently visible (not yet faded out).
    var isVisible: Bool {
        guard let panel = panel else { return false }
        return panel.isVisible && panel.alphaValue > 0
    }

    /// Update position while visible (e.g., on keystroke). Does not reset fade timer.
    /// Only moves if TextInputGeometry returns a valid caret rect (not mouse fallback).
    func updatePosition(client: (any IMKTextInput)?) {
        guard isVisible, let panel = panel else { return }
        // Only update if we get a real caret position (not mouse fallback)
        guard let result = TextInputGeometry.caretRect(for: client) else { return }
        let panelSize = panel.frame.size
        let gap: CGFloat = 4
        let x: CGFloat
        if result.source == .attributesAtZero {
            // X from attributesAtZero is unreliable — keep current position
            return
        } else {
            x = TextInputGeometry.indicatorAnchorX(for: result.rect) + gap
        }
        let aboveY = result.rect.origin.y + result.rect.height + gap
        if let screenFrame = TextInputGeometry.screenFrame(containing: result.rect),
           aboveY + panelSize.height > screenFrame.maxY {
            panel.setFrameOrigin(NSPoint(x: x, y: result.rect.origin.y - panelSize.height - gap))
        } else {
            panel.setFrameOrigin(NSPoint(x: x, y: aboveY))
        }
    }

    /// Show the mode indicator near the caret position.
    /// `client` is used to obtain the caret rect from IMKTextInput.
    func show(for mode: InputMode, client: (any IMKTextInput)? = nil) {
        fadeTimer?.invalidate()

        let labelWidth: CGFloat = mode.label.count > 1 ? 36 : 26
        let panelSize = NSSize(width: labelWidth, height: 24)

        // Build panel once, reuse thereafter
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

        // Update label, resize, and show
        textField.stringValue = mode.label
        panel.setContentSize(panelSize)
        panel.contentView?.frame = NSRect(origin: .zero, size: panelSize)
        textField.frame = NSRect(origin: .zero, size: panelSize)
        let origin = caretOrigin(from: client, panelSize: panelSize)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1.0
        panel.orderFront(nil)

        // Fade out after delay
        fadeTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = self.fadeDuration
                self.panel?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.panel?.orderOut(nil)
            })
        }
    }

    // MARK: - Private

    private func caretOrigin(from client: (any IMKTextInput)?, panelSize: NSSize) -> NSPoint {
        if let result = TextInputGeometry.caretRect(for: client) {
            let lineHeightRect = result.rect
            let gap: CGFloat = 4

            // For attributesAtZero fallback, X is unreliable (points to line start).
            // Use current panel position if visible, or mouse X as last resort.
            let x: CGFloat
            if result.source == .attributesAtZero {
                if let panel, panel.isVisible {
                    x = panel.frame.origin.x
                } else {
                    x = NSEvent.mouseLocation.x + gap
                }
            } else {
                x = TextInputGeometry.indicatorAnchorX(for: lineHeightRect) + gap
            }

            // Prefer above the caret; if that goes off-screen, show below
            let aboveY = lineHeightRect.origin.y + lineHeightRect.height + gap
            if let screenFrame = TextInputGeometry.screenFrame(containing: lineHeightRect),
               aboveY + panelSize.height > screenFrame.maxY {
                // Show below the caret
                return NSPoint(x: x, y: lineHeightRect.origin.y - panelSize.height - gap)
            }
            return NSPoint(x: x, y: aboveY)
        }

        if let panel, panel.isVisible {
            return panel.frame.origin
        }

        // Fallback: position near the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        if let screenFrame = TextInputGeometry.screenFrame(containing: mouseLocation) {
            return NSPoint(
                x: max(screenFrame.minX, min(mouseLocation.x - 12, screenFrame.maxX - panelSize.width)),
                y: max(screenFrame.minY, min(mouseLocation.y + 16, screenFrame.maxY - panelSize.height))
            )
        }
        return NSPoint(
            x: mouseLocation.x - 12,
            y: mouseLocation.y + 16
        )
    }
}
