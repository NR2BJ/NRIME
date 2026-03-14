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
    }

    struct CaretResult {
        let rect: NSRect
        let source: CaretSource
    }
    static func caretRect(for client: (any IMKTextInput)?) -> CaretResult? {
        guard let client else { return nil }

        // 1. Try firstRect — precise positioning for well-behaving apps.
        //    Reject suspiciously wide rects (Electron apps return the entire input field).
        for range in candidateRanges(for: client) {
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rect = client.firstRect(forCharacterRange: range, actualRange: &actualRange)
            if isUsableCaretRect(rect)
                && !shouldDeferSuspiciousFirstRect(rect, requestedRange: range, actualRange: actualRange) {
                return CaretResult(rect: rect, source: .precise)
            }
        }

        // 2. Fallback: attributes at caret index.
        if let index = caretIndex(for: client) {
            var lineHeightRect = NSRect.zero
            client.attributes(forCharacterIndex: index, lineHeightRectangle: &lineHeightRect)
            if isUsableCaretRect(lineHeightRect) {
                DeveloperLogger.shared.log(
                    "geometry",
                    "Using attributes rectangle at caret index",
                    metadata: ["characterIndex": "\(index)", "rect": lineHeightRect.logDescription]
                )
                return CaretResult(rect: lineHeightRect, source: .attributesAtCaret)
            }
        }

        // 3. Fallback: attributes at index 0 (approach used by Squirrel, AquaSKK, Fcitx5).
        //    Only Y and height are reliable — X points to the line start, not the caret.
        var zeroRect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &zeroRect)
        if isUsableCaretRect(zeroRect) {
            DeveloperLogger.shared.log(
                "geometry",
                "Using attributes rectangle at index 0 (vertical geometry only)",
                metadata: ["rect": zeroRect.logDescription]
            )
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
