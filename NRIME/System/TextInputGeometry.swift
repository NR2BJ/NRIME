import Cocoa
import InputMethodKit

enum TextInputGeometry {

    /// Describes the confidence level of a caret position result.
    enum CaretSource {
        /// `firstRect` returned a precise, narrow rect.
        case precise
        /// `attributes(forCharacterIndex: caretIndex)` was used.
        case attributesAtCaret
        /// `attributes(forCharacterIndex: 0)` — only Y/height are reliable; X is the line start.
        case attributesAtZero
        /// Accessibility API (AXUIElement) provided the caret bounds.
        case accessibility
    }

    struct CaretResult {
        let rect: NSRect
        let source: CaretSource
    }
    static func caretRect(for client: (any IMKTextInput)?) -> CaretResult? {
        guard let client else { return nil }

        // 1. Accessibility API — most accurate across all apps.
        //    Uses AXUIElementSetMessagingTimeout to cap latency at 10ms.
        if let axRect = accessibilityCaretRect(), isUsableCaretRect(axRect) {
            return CaretResult(rect: axRect, source: .accessibility)
        }

        // 2. Try firstRect — precise positioning for well-behaving apps.
        //    Reject suspiciously wide rects (Electron apps return the entire input field).
        for range in candidateRanges(for: client) {
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rect = client.firstRect(forCharacterRange: range, actualRange: &actualRange)
            if isUsableCaretRect(rect)
                && !shouldDeferSuspiciousFirstRect(rect, requestedRange: range, actualRange: actualRange) {
                return CaretResult(rect: rect, source: .precise)
            }
        }

        // 3. Fallback: attributes at caret index.
        if let index = caretIndex(for: client) {
            var lineHeightRect = NSRect.zero
            client.attributes(forCharacterIndex: index, lineHeightRectangle: &lineHeightRect)
            if isUsableCaretRect(lineHeightRect) {
                return CaretResult(rect: lineHeightRect, source: .attributesAtCaret)
            }
        }

        // 4. Fallback: attributes at index 0.
        //    Only Y and height are reliable — X points to the line start, not the caret.
        var zeroRect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &zeroRect)
        if isUsableCaretRect(zeroRect) {
            return CaretResult(rect: zeroRect, source: .attributesAtZero)
        }

        return nil
    }

    static func screenFrame(containing rect: NSRect) -> NSRect? {
        bestScreenFrame(for: rect, screenFrames: NSScreen.screens.map(\.visibleFrame))
    }

    static func screenFrame(containing point: NSPoint) -> NSRect? {
        bestScreenFrame(for: NSRect(origin: point, size: .zero), screenFrames: NSScreen.screens.map(\.visibleFrame))
    }

    static func panelOriginX(for anchorRect: NSRect, panelWidth: CGFloat, within screenFrame: NSRect) -> CGFloat {
        let horizontalGap: CGFloat = 2
        let preferredRightwardX = anchorRect.maxX + horizontalGap
        if preferredRightwardX + panelWidth <= screenFrame.maxX {
            return max(preferredRightwardX, screenFrame.minX)
        }

        let rightAlignedToAnchorX = anchorRect.minX - panelWidth - horizontalGap
        let clampedRightAlignedX = max(screenFrame.minX, min(rightAlignedToAnchorX, screenFrame.maxX - panelWidth))
        return clampedRightAlignedX
    }

    static func indicatorAnchorX(for rect: NSRect) -> CGFloat {
        if rect.width <= 24 {
            return rect.maxX
        }
        return rect.maxX - 10
    }

    static func caretIndex(for client: any IMKTextInput) -> Int? {
        let selectedRange = client.selectedRange()
        let markedRange = client.markedRange()

        if isPreferredSelectedRange(selectedRange, relativeTo: markedRange) {
            return max(0, selectedRange.location)
        }

        if markedRange.location != NSNotFound {
            return max(0, markedRange.location + markedRange.length)
        }

        if selectedRange.location != NSNotFound {
            return max(0, selectedRange.location)
        }

        return nil
    }

    private static func candidateRanges(for client: any IMKTextInput) -> [NSRange] {
        var ranges: [NSRange] = []

        let selectedRange = client.selectedRange()
        let markedRange = client.markedRange()

        if isPreferredSelectedRange(selectedRange, relativeTo: markedRange) {
            ranges.append(selectedRange)
            if selectedRange.length == 0 {
                ranges.append(NSRange(location: selectedRange.location, length: 1))
            }
        }

        if markedRange.location != NSNotFound {
            let caretLocation = markedRange.location + markedRange.length
            ranges.append(NSRange(location: caretLocation, length: 0))
            ranges.append(markedRange)
        }

        if selectedRange.location != NSNotFound && !isPreferredSelectedRange(selectedRange, relativeTo: markedRange) {
            ranges.append(selectedRange)
            if selectedRange.length == 0 {
                ranges.append(NSRange(location: selectedRange.location, length: 1))
            }
        }

        return ranges
    }

    static func bestScreenFrame(for anchorRect: NSRect, screenFrames: [NSRect]) -> NSRect? {
        guard !screenFrames.isEmpty else { return nil }

        let anchorPoint = NSPoint(x: anchorRect.midX, y: anchorRect.midY)

        if let exactMatch = screenFrames.first(where: { frame in
            frame.contains(anchorPoint) || frame.intersects(anchorRect)
        }) {
            return exactMatch
        }

        return screenFrames.min { lhs, rhs in
            squaredDistance(from: anchorPoint, to: lhs) < squaredDistance(from: anchorPoint, to: rhs)
        }
    }

    private static func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return (dx * dx) + (dy * dy)
    }

    // MARK: - Accessibility API

    /// Query the focused UI element's caret bounds via AXUIElement.
    /// Uses PID-direct access and 50ms messaging timeout for speed.
    private static func accessibilityCaretRect() -> NSRect? {
        // Use PID-direct access instead of system-wide traversal (saves one IPC hop)
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.01) // 10ms timeout

        var focusedElementValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue) == .success else {
            return nil
        }
        let focusedElement = focusedElementValue as! AXUIElement

        // Get selected text range
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        // Use a zero-length range at the caret position for precise bounds
        var caretRange = CFRange(location: range.location, length: 0)
        guard let caretRangeValue = AXValueCreate(.cfRange, &caretRange) else {
            return nil
        }

        // Get bounds for the caret position
        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            caretRangeValue,
            &boundsValue
        ) == .success else {
            return nil
        }

        var axBounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &axBounds) else {
            return nil
        }

        // AX uses top-left origin; convert to AppKit bottom-left origin
        guard let screenHeight = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: axBounds.midX, y: 0)) })?.frame.height
                ?? NSScreen.main?.frame.height else {
            return nil
        }

        let flippedY = screenHeight - axBounds.origin.y - axBounds.size.height
        return NSRect(x: axBounds.origin.x, y: flippedY, width: max(axBounds.size.width, 1), height: axBounds.size.height)
    }

    private static func isUsableCaretRect(_ rect: NSRect) -> Bool {
        guard !rect.equalTo(.zero),
              rect.width >= 0,
              rect.height > 0 else {
            return false
        }

        guard let screenFrame = screenFrame(containing: rect) else {
            return false
        }

        let cornerTolerance: CGFloat = 1
        let pinnedToLowerLeftCorner =
            rect.minX <= screenFrame.minX + cornerTolerance &&
            rect.minY <= screenFrame.minY + cornerTolerance

        return !pinnedToLowerLeftCorner
    }

    private static func isPreferredSelectedRange(_ selectedRange: NSRange, relativeTo markedRange: NSRange) -> Bool {
        guard selectedRange.location != NSNotFound else { return false }
        guard markedRange.location != NSNotFound else { return true }

        let markedEnd = markedRange.location + markedRange.length
        return selectedRange.location >= markedRange.location && selectedRange.location <= markedEnd
    }

    private static func shouldDeferSuspiciousFirstRect(_ rect: NSRect, requestedRange: NSRange, actualRange: NSRange) -> Bool {
        guard isUsableCaretRect(rect) else { return false }
        guard rect.width > 40 else { return false }

        if requestedRange.length == 0 {
            return true
        }

        guard actualRange.location != NSNotFound, actualRange.length > 0 else {
            return false
        }

        let averageCharacterWidth = rect.width / CGFloat(actualRange.length)
        return averageCharacterWidth > 40
    }
}

private extension NSRect {
    var logDescription: String {
        String(format: "{x=%.1f,y=%.1f,w=%.1f,h=%.1f}", origin.x, origin.y, size.width, size.height)
    }
}
