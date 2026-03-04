import Cocoa
import InputMethodKit

final class InlineIndicator {
    static let shared = InlineIndicator()

    private var panel: NSPanel?
    private var textField: NSTextField?
    private var fadeTimer: Timer?
    private let displayDuration: TimeInterval = 0.5
    private let fadeDuration: TimeInterval = 0.3

    private init() {}

    /// Show the mode indicator near the caret position.
    /// `client` is used to obtain the caret rect from IMKTextInput.
    func show(for mode: InputMode, client: (any IMKTextInput)? = nil) {
        fadeTimer?.invalidate()

        let panelSize = NSSize(width: 36, height: 28)

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

        // Update label and show
        textField.stringValue = mode.label
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
        // Try to get caret rect from the IMKTextInput client
        if let client = client {
            var lineHeightRect = NSRect.zero
            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect)

            if lineHeightRect != .zero {
                let gap: CGFloat = 4
                let x = lineHeightRect.origin.x + lineHeightRect.width + gap

                // Prefer above the caret; if that goes off-screen, show below
                let aboveY = lineHeightRect.origin.y + lineHeightRect.height + gap
                if let screen = NSScreen.main, aboveY + panelSize.height > screen.visibleFrame.maxY {
                    // Show below the caret
                    return NSPoint(x: x, y: lineHeightRect.origin.y - panelSize.height - gap)
                }
                return NSPoint(x: x, y: aboveY)
            }
        }

        // Fallback: position near the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        return NSPoint(
            x: mouseLocation.x + 16,
            y: mouseLocation.y + 16
        )
    }
}
