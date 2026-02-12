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

    /// Number of candidates per page in list mode.
    let pageSize = 9

    /// Whether the panel is in grid (expanded) mode.
    private(set) var isGridMode: Bool = false

    /// Number of columns in grid mode.
    private let gridColumns = 5

    /// Number of rows in grid mode.
    private let gridRows = 6

    /// Grid page size (columns × rows).
    var gridPageSize: Int { gridColumns * gridRows }

    /// Effective page size depending on current mode.
    var effectivePageSize: Int { isGridMode ? gridPageSize : pageSize }

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

        // Reset grid mode when showing from hidden state
        if !(panel?.isVisible ?? false) {
            isGridMode = false
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
        isGridMode = false
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
        selectedIndex = max(0, selectedIndex - effectivePageSize)
        updateDisplay()
    }

    /// Move to the next page.
    func pageDown() {
        guard !candidates.isEmpty else { return }
        selectedIndex = min(candidates.count - 1, selectedIndex + effectivePageSize)
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
        return selectedIndex / effectivePageSize
    }

    /// Total number of pages.
    var totalPages: Int {
        return candidates.isEmpty ? 0 : ((candidates.count - 1) / effectivePageSize) + 1
    }

    // MARK: - Grid Mode

    /// Toggle grid mode on/off, repositioning the panel.
    func toggleGridMode(client: (any IMKTextInput)? = nil) {
        isGridMode = !isGridMode
        updateDisplay()
        repositionPanel(client: client)
    }

    /// Exit grid mode (return to list), keeping the panel visible.
    /// Note: Tab toggles grid/list. Escape always hides the panel entirely.
    func exitGridMode(client: (any IMKTextInput)? = nil) {
        guard isGridMode else { return }
        isGridMode = false
        updateDisplay()
        repositionPanel(client: client)
    }

    /// Move selection left by 1 in grid mode.
    func moveLeft() {
        guard isGridMode, !candidates.isEmpty, selectedIndex > 0 else { return }
        selectedIndex -= 1
        updateDisplay()
    }

    /// Move selection right by 1 in grid mode.
    func moveRight() {
        guard isGridMode, !candidates.isEmpty, selectedIndex < candidates.count - 1 else { return }
        selectedIndex += 1
        updateDisplay()
    }

    /// Move selection up by one row (gridColumns) in grid mode.
    func moveUpGrid() {
        guard isGridMode, !candidates.isEmpty else { return }
        let newIndex = selectedIndex - gridColumns
        if newIndex >= 0 {
            selectedIndex = newIndex
            updateDisplay()
        }
    }

    /// Move selection down by one row (gridColumns) in grid mode.
    func moveDownGrid() {
        guard isGridMode, !candidates.isEmpty else { return }
        let newIndex = selectedIndex + gridColumns
        if newIndex < candidates.count {
            selectedIndex = newIndex
            updateDisplay()
        }
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
        if isGridMode {
            updateGridDisplay()
        } else {
            updateListDisplay()
        }
    }

    private func updateListDisplay() {
        guard let stackView = stackView, let pageLabel = pageLabel, let panel = panel else { return }

        // Remove old views
        clearStackView()

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

    private func updateGridDisplay() {
        guard let stackView = stackView, let pageLabel = pageLabel, let panel = panel else { return }

        // Remove old views
        clearStackView()

        let pageStart = currentPage * gridPageSize
        let pageEnd = min(pageStart + gridPageSize, candidates.count)
        let pageItems = Array(candidates[pageStart..<pageEnd])

        // Calculate cell width based on longest candidate on this page
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        var maxCellWidth: CGFloat = 60
        for item in pageItems {
            let size = (item as NSString).size(withAttributes: attrs)
            maxCellWidth = max(maxCellWidth, size.width + 16)
        }
        maxCellWidth = min(maxCellWidth, 120)

        let cellHeight: CGFloat = 26
        let sidePadding: CGFloat = 4
        let panelWidth = maxCellWidth * CGFloat(gridColumns) + sidePadding * 2

        let actualRows = (pageItems.count + gridColumns - 1) / gridColumns
        for row in 0..<actualRows {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 0
            rowStack.alignment = .centerY

            for col in 0..<gridColumns {
                let idx = row * gridColumns + col
                guard idx < pageItems.count else { break }
                let globalIdx = pageStart + idx
                let isSelected = globalIdx == selectedIndex

                let cell = CandidateGridCellView(
                    text: pageItems[idx],
                    isSelected: isSelected,
                    width: maxCellWidth,
                    height: cellHeight
                )
                rowStack.addArrangedSubview(cell)
            }
            stackView.addArrangedSubview(rowStack)
        }

        // Layout
        let topPadding: CGFloat = 4
        let bottomPadding: CGFloat = 4
        let pageLabelHeight: CGFloat = 16
        let pageLabelSpacing: CGFloat = 2
        let showPageLabel = totalPages > 1
        let pageIndicatorHeight: CGFloat = showPageLabel ? (pageLabelSpacing + pageLabelHeight) : 0
        let gridHeight = CGFloat(actualRows) * cellHeight
        let totalHeight = topPadding + gridHeight + pageIndicatorHeight + bottomPadding

        var frame = panel.frame
        let oldHeight = frame.height
        frame.size = NSSize(width: panelWidth, height: totalHeight)
        frame.origin.y += (oldHeight - totalHeight)
        panel.setFrame(frame, display: true)

        stackView.frame = NSRect(x: sidePadding, y: bottomPadding + pageIndicatorHeight,
                                 width: panelWidth - sidePadding * 2, height: gridHeight)

        if showPageLabel {
            pageLabel.stringValue = "\(currentPage + 1)/\(totalPages)"
            pageLabel.isHidden = false
            pageLabel.frame = NSRect(x: 0, y: bottomPadding,
                                     width: panelWidth, height: pageLabelHeight)
        } else {
            pageLabel.isHidden = true
        }

        if let container = panel.contentView {
            container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    /// Remove all arranged subviews from the stack.
    private func clearStackView() {
        guard let stackView = stackView else { return }
        for view in rowViews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowViews.removeAll()
        // Also remove any grid row stacks
        for subview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
    }

    /// Reposition the panel after a size change (e.g., grid toggle).
    private func repositionPanel(client: (any IMKTextInput)? = nil) {
        guard let panel = panel else { return }
        let origin = caretOrigin(from: client, panelWidth: panel.frame.width)
        panel.setFrameOrigin(origin)
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

// MARK: - CandidateGridCellView

/// A single cell in the grid-mode candidate panel.
private class CandidateGridCellView: NSView {

    init(text: String, isSelected: Bool, width: CGFloat, height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        wantsLayer = true

        if isSelected {
            layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
            layer?.cornerRadius = 3
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        let textColor: NSColor = isSelected ? .white : .labelColor

        let textLabel = NSTextField(labelWithString: text)
        textLabel.font = NSFont.systemFont(ofSize: 13)
        textLabel.textColor = textColor
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.alignment = .center
        textLabel.frame = NSRect(x: 2, y: 0, width: width - 4, height: height)
        addSubview(textLabel)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: height),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
