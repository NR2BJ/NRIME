import Cocoa
import InputMethodKit

final class InlineIndicator {
    static let shared = InlineIndicator()

    private var panel: NSPanel?
    private var textField: NSTextField?
    private var fadeTimer: Timer?
    private var isFading = false
    private var pendingMode: InputMode?  // set when show() can't find caret position
    private let displayDuration: TimeInterval = 1.0
    private let fadeDuration: TimeInterval = 0.3

    private init() {}

    /// Whether the indicator is actively displayed (not fading or hidden).
    var isVisible: Bool {
        guard let panel = panel else { return false }
        return panel.isVisible && panel.alphaValue > 0 && !isFading
    }

    /// Whether we have a pending show waiting for a valid caret position.
    var hasPendingShow: Bool { pendingMode != nil }

    /// Update position while visible (e.g., on keystroke). Does not reset fade timer.
    /// Also resolves pending shows if a valid caret position is found.
    func updatePosition(client: (any IMKTextInput)?) {
        // Resolve pending show first
        if let mode = pendingMode {
            if let result = TextInputGeometry.caretRect(for: client),
               result.source != .attributesAtZero {
                pendingMode = nil
                showAtPosition(result: result)
            }
            return
        }

        guard isVisible, let panel = panel else { return }
        // During composition, many apps return bogus caret positions (field start).
        // Freeze indicator position until composition ends.
        if let client = client {
            let markedRange = client.markedRange()
            if markedRange.location != NSNotFound && markedRange.length > 0 {
                return
            }
        }
        // Only update if we get a real caret position
        guard let result = TextInputGeometry.caretRect(for: client) else { return }
        if result.source == .attributesAtZero { return }

        let panelSize = panel.frame.size
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

    /// Show the mode indicator near the caret position.
    /// If caret position can't be determined, defers display until updatePosition resolves it.
    func show(for mode: InputMode, client: (any IMKTextInput)? = nil) {
        fadeTimer?.invalidate()
        pendingMode = nil

        ensurePanel(for: mode)

        // Try to get a precise caret position
        if let result = TextInputGeometry.caretRect(for: client),
           result.source != .attributesAtZero {
            showAtPosition(result: result)
        } else {
            // Can't find caret — defer until updatePosition gets a valid position
            pendingMode = mode
            // Set a timeout: if no valid position within displayDuration, cancel
            fadeTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
                self?.pendingMode = nil
            }
        }
    }

    // MARK: - Private

    private func showAtPosition(result: TextInputGeometry.CaretResult) {
        guard let panel = panel else { return }

        let panelSize = panel.frame.size
        let gap: CGFloat = 4
        let x = TextInputGeometry.indicatorAnchorX(for: result.rect) + gap
        let aboveY = result.rect.origin.y + result.rect.height + gap

        let origin: NSPoint
        if let screenFrame = TextInputGeometry.screenFrame(containing: result.rect),
           aboveY + panelSize.height > screenFrame.maxY {
            origin = NSPoint(x: x, y: result.rect.origin.y - panelSize.height - gap)
        } else {
            origin = NSPoint(x: x, y: aboveY)
        }

        panel.setFrameOrigin(origin)
        isFading = false
        panel.alphaValue = 1.0
        panel.orderFront(nil)

        // Fade out after delay
        fadeTimer?.invalidate()
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

    private func ensurePanel(for mode: InputMode) {
        let labelWidth: CGFloat = mode.label.count > 1 ? 36 : 26
        let panelSize = NSSize(width: labelWidth, height: 24)

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
