import Cocoa
import InputMethodKit

/// Custom candidate window replacing IMKCandidates.
/// Provides direct control over selection highlight, candidate list, and positioning.
final class CandidatePanel {

    // MARK: - Public Properties

    /// All candidate strings (full list across all pages).
    private(set) var candidates: [String] = []

    /// Currently selected index in the full candidate list.
    private(set) var selectedIndex: Int = 0

    /// Number of candidates per page.
    let pageSize = 9

    // MARK: - Private UI

    private var panel: NSPanel?
    private var stackView: NSStackView?
    private var pageLabel: NSTextField?
    private var rowViews: [CandidateRowView] = []

    // MARK: - Public API

    /// Show the candidate panel with the given candidates, positioned near the caret.
    func show(candidates: [String], selectedIndex: Int = 0, client: (any IMKTextInput)? = nil) {
        self.candidates = candidates
        self.selectedIndex = max(0, min(selectedIndex, candidates.count - 1))

        if candidates.isEmpty {
            hide()
            return
        }

        buildPanel()
        updateDisplay()

        if let panel = panel {
            let origin = caretOrigin(from: client, panelWidth: panel.frame.width)
            panel.setFrameOrigin(origin)
            panel.orderFront(nil)
        }
    }

    /// Hide the panel.
    func hide() {
        panel?.orderOut(nil)
    }

    /// Whether the panel is currently visible.
    func isVisible() -> Bool {
        return panel?.isVisible ?? false
    }

    /// Move selection up by 1.
    func moveUp() {
        guard !candidates.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
            updateDisplay()
        }
    }

    /// Move selection down by 1.
    func moveDown() {
        guard !candidates.isEmpty else { return }
        if selectedIndex < candidates.count - 1 {
            selectedIndex += 1
            updateDisplay()
        }
    }

    /// Move to the previous page.
    func pageUp() {
        guard !candidates.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - pageSize)
        updateDisplay()
    }

    /// Move to the next page.
    func pageDown() {
        guard !candidates.isEmpty else { return }
        selectedIndex = min(candidates.count - 1, selectedIndex + pageSize)
        updateDisplay()
    }

    /// Select a candidate at a specific index.
    func select(at index: Int) {
        guard index >= 0 && index < candidates.count else { return }
        selectedIndex = index
        updateDisplay()
    }

    /// Get the currently selected candidate string, or nil if empty.
    func currentSelection() -> String? {
        guard selectedIndex >= 0 && selectedIndex < candidates.count else { return nil }
        return candidates[selectedIndex]
    }

    /// Current page number (0-based).
    var currentPage: Int {
        return selectedIndex / pageSize
    }

    /// Total number of pages.
    var totalPages: Int {
        return candidates.isEmpty ? 0 : ((candidates.count - 1) / pageSize) + 1
    }

    // MARK: - Private: Panel Construction

    private func buildPanel() {
        // Reuse existing panel if possible
        if panel != nil {
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Use panel's built-in contentView as container (no Auto Layout for sizing)
        let container = panel.contentView!
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 6
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 0.5

        // StackView and pageLabel use manual frames set in updateDisplay()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        let pageLabel = NSTextField(labelWithString: "")
        pageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.alignment = .center

        container.addSubview(stack)
        container.addSubview(pageLabel)

        self.panel = panel
        self.stackView = stack
        self.pageLabel = pageLabel
    }

    // MARK: - Private: Display Update

    private func updateDisplay() {
        guard let stackView = stackView, let pageLabel = pageLabel, let panel = panel else { return }

        // Remove old rows
        for view in rowViews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowViews.removeAll()

        // Calculate current page items
        let pageStart = currentPage * pageSize
        let pageEnd = min(pageStart + pageSize, candidates.count)
        let pageItems = Array(candidates[pageStart..<pageEnd])

        // Determine width based on longest candidate
        var maxWidth: CGFloat = 160
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
        for item in pageItems {
            let size = (item as NSString).size(withAttributes: attrs)
            maxWidth = max(maxWidth, size.width + 50) // 50 for number label + padding
        }
        maxWidth = min(maxWidth, 400) // cap

        // Build rows
        for (i, item) in pageItems.enumerated() {
            let globalIndex = pageStart + i
            let isSelected = (globalIndex == selectedIndex)
            let number = (i + 1) % 10 // 1-9, then 0

            let row = CandidateRowView(
                number: number == 0 ? 0 : number,
                text: item,
                isSelected: isSelected,
                width: maxWidth
            )
            stackView.addArrangedSubview(row)
            rowViews.append(row)
        }

        // Layout calculations
        let rowHeight: CGFloat = 24
        let topPadding: CGFloat = 4
        let bottomPadding: CGFloat = 4
        let pageLabelHeight: CGFloat = 16
        let pageLabelSpacing: CGFloat = 2
        let showPageLabel = totalPages > 1
        let pageIndicatorHeight: CGFloat = showPageLabel ? (pageLabelSpacing + pageLabelHeight) : 0
        let stackHeight = CGFloat(pageItems.count) * rowHeight
        let totalHeight = topPadding + stackHeight + pageIndicatorHeight + bottomPadding

        // Resize panel first (this also resizes contentView)
        var frame = panel.frame
        let oldHeight = frame.height
        frame.size = NSSize(width: maxWidth, height: totalHeight)
        // Adjust origin so panel grows upward (keep bottom-left stable)
        frame.origin.y += (oldHeight - totalHeight)
        panel.setFrame(frame, display: true)

        // Position stackView and pageLabel with manual frames (no Auto Layout conflicts)
        stackView.frame = NSRect(x: 0, y: bottomPadding + pageIndicatorHeight,
                                 width: maxWidth, height: stackHeight)

        // Update page indicator
        if showPageLabel {
            pageLabel.stringValue = "\(currentPage + 1)/\(totalPages)"
            pageLabel.isHidden = false
            pageLabel.frame = NSRect(x: 0, y: bottomPadding,
                                     width: maxWidth, height: pageLabelHeight)
        } else {
            pageLabel.isHidden = true
        }

        // Update container background for appearance changes
        if let container = panel.contentView {
            container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    // MARK: - Private: Positioning

    private func caretOrigin(from client: (any IMKTextInput)?, panelWidth: CGFloat) -> NSPoint {
        if let client = client {
            var lineHeightRect = NSRect.zero
            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect)

            if lineHeightRect != .zero {
                let x = lineHeightRect.origin.x
                // Position below the caret
                let y = lineHeightRect.origin.y - (panel?.frame.height ?? 200) - 2

                // Ensure panel stays on screen
                if let screen = NSScreen.main {
                    let clampedX = min(x, screen.visibleFrame.maxX - panelWidth)
                    let clampedY = max(y, screen.visibleFrame.minY)
                    return NSPoint(x: max(clampedX, screen.visibleFrame.minX), y: clampedY)
                }
                return NSPoint(x: x, y: y)
            }
        }

        // Fallback: near mouse
        let mouseLocation = NSEvent.mouseLocation
        return NSPoint(x: mouseLocation.x, y: mouseLocation.y - 200)
    }
}

// MARK: - CandidateRowView

/// A single row in the candidate panel: [number] [text]
private class CandidateRowView: NSView {
    private let rowHeight: CGFloat = 24

    init(number: Int, text: String, isSelected: Bool, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: rowHeight))

        wantsLayer = true

        if isSelected {
            layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        let textColor: NSColor = isSelected ? .white : .labelColor
        let secondaryColor: NSColor = isSelected ? .init(white: 1, alpha: 0.7) : .secondaryLabelColor

        // Number label
        let numberLabel = NSTextField(labelWithString: number > 0 ? "\(number)." : "")
        numberLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        numberLabel.textColor = secondaryColor
        numberLabel.frame = NSRect(x: 6, y: 0, width: 22, height: rowHeight)

        // Text label
        let textLabel = NSTextField(labelWithString: text)
        textLabel.font = NSFont.systemFont(ofSize: 14)
        textLabel.textColor = textColor
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.frame = NSRect(x: 30, y: 0, width: width - 36, height: rowHeight)

        addSubview(numberLabel)
        addSubview(textLabel)

        // Fixed size
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: rowHeight),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
