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

    /// Memorize last good caret position to prevent jumping to (0,0) on failure.
    /// (Inspired by fcitx5-macos coordinate memorization strategy.)
    private static var lastGoodResult: CaretResult?

    static func caretRect(for client: (any IMKTextInput)?) -> CaretResult? {
        guard let client else { return lastGoodResult }

        let markedRange = client.markedRange()
        let isComposing = markedRange.location != NSNotFound && markedRange.length > 0

        // During active composition, many apps return bogus caret positions
        // (e.g., field start instead of cursor). If we have a known good position,
        // keep it stable until composition ends.
        if isComposing, let last = lastGoodResult {
            return last
        }

        // 1. Try firstRect — precise positioning for well-behaving apps.
        //    Reject suspiciously wide rects (Electron apps return the entire input field).
        for range in candidateRanges(for: client) {
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rect = client.firstRect(forCharacterRange: range, actualRange: &actualRange)
            if isUsableCaretRect(rect)
                && !shouldDeferSuspiciousFirstRect(rect, requestedRange: range, actualRange: actualRange) {
                let result = CaretResult(rect: rect, source: .precise)
                lastGoodResult = result
                return result
            }
        }

        // 2. Fallback: attributes at caret index (fcitx5/Squirrel primary method).
        if let index = caretIndex(for: client) {
            var lineHeightRect = NSRect.zero
            client.attributes(forCharacterIndex: index, lineHeightRectangle: &lineHeightRect)
            if isUsableCaretRect(lineHeightRect) {
                let result = CaretResult(rect: lineHeightRect, source: .attributesAtCaret)
                lastGoodResult = result
                return result
            }
        }

        // 3. Fallback: attributes at index 0.
        //    Only Y and height are reliable — X points to the line start, not the caret.
        //    Do NOT save as lastGoodResult — the unreliable X would poison future lookups.
        var zeroRect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &zeroRect)
        if isUsableCaretRect(zeroRect) {
            return CaretResult(rect: zeroRect, source: .attributesAtZero)
        }

        // 4. Accessibility API fallback — most accurate but can be slow.
        //    Uses length:1 to work around macOS zero-length selection bug.
        //    Sets AXEnhancedUserInterface for Electron/Chromium apps.
        if let axRect = accessibilityCaretRect(), isUsableCaretRect(axRect) {
            let result = CaretResult(rect: axRect, source: .accessibility)
            lastGoodResult = result
            return result
        }

        // All methods failed: return last known good position
        return lastGoodResult
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

        // During composition (markedRange exists), prefer selectedRange within marked text.
        // Many apps return the field start for markedRange end position, so avoid that.
        if isPreferredSelectedRange(selectedRange, relativeTo: markedRange) {
            ranges.append(selectedRange)
            if selectedRange.length == 0 {
                ranges.append(NSRange(location: selectedRange.location, length: 1))
            }
        }

        // Only use markedRange as fallback when selectedRange is unavailable
        if ranges.isEmpty, markedRange.location != NSNotFound {
            let caretLocation = markedRange.location + markedRange.length
            ranges.append(NSRange(location: caretLocation, length: 0))
            ranges.append(NSRange(location: caretLocation, length: 1))
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
    /// Uses PID-direct access with 10ms timeout.
    /// Applies Input Source Pro's techniques:
    ///   - length:1 to work around macOS zero-length kAXBoundsForRange bug
    ///   - AXEnhancedUserInterface for Electron/Chromium apps
    private static func accessibilityCaretRect() -> NSRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.01) // 10ms

        // Activate AX on Electron/Chromium apps (they hide their AX tree by default)
        if let bundleId = frontApp.bundleIdentifier, !bundleId.hasPrefix("com.apple.") {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
        }

        var focusedElementValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue) == .success else {
            return nil
        }
        let focusedElement = focusedElementValue as! AXUIElement

        // Try WebKit/Chromium-specific text markers first (Input Source Pro strategy)
        if let webRect = webAreaCaretRect(focusedElement) {
            return webRect
        }

        // Standard AX: selected text range → bounds
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        // Use length:1 instead of length:0 to work around macOS bug
        // where kAXBoundsForRangeParameterizedAttribute returns kAXErrorNoValue for zero-length.
        var caretRange = CFRange(location: max(range.location, 0), length: 1)
        guard let caretRangeValue = AXValueCreate(.cfRange, &caretRange) else {
            return nil
        }

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

        return convertFromQuartz(axBounds)
    }

    /// WebKit/Chromium-specific caret detection using text markers.
    /// (Input Source Pro's findWebAreaCursor strategy)
    private static func webAreaCaretRect(_ element: AXUIElement) -> NSRect? {
        var markerRangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeValue) == .success else {
            return nil
        }

        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRangeValue!,
            &boundsValue
        ) == .success else {
            return nil
        }

        var axBounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &axBounds) else {
            return nil
        }

        return convertFromQuartz(axBounds)
    }

    /// Convert Quartz (top-left origin) coordinates to AppKit (bottom-left origin).
    private static func convertFromQuartz(_ quartzRect: CGRect) -> NSRect? {
        guard let screenHeight = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: quartzRect.midX, y: 0))
        })?.frame.height ?? NSScreen.main?.frame.height else {
            return nil
        }

        let flippedY = screenHeight - quartzRect.origin.y - quartzRect.size.height
        return NSRect(x: quartzRect.origin.x, y: flippedY, width: max(quartzRect.size.width, 1), height: quartzRect.size.height)
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
