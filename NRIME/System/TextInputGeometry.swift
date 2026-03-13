import Cocoa
import InputMethodKit

enum TextInputGeometry {
    static func caretRect(for client: (any IMKTextInput)?) -> NSRect? {
        guard let client else { return nil }

        for range in candidateRanges(for: client) {
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rect = client.firstRect(forCharacterRange: range, actualRange: &actualRange)
            if rect != .zero {
                return rect
            }
        }

        guard let index = caretIndex(for: client) else { return nil }

        var lineHeightRect = NSRect.zero
        client.attributes(forCharacterIndex: index, lineHeightRectangle: &lineHeightRect)
        return lineHeightRect == .zero ? nil : lineHeightRect
    }

    static func screenFrame(containing rect: NSRect) -> NSRect? {
        bestScreenFrame(for: rect, screenFrames: NSScreen.screens.map(\.visibleFrame))
    }

    static func screenFrame(containing point: NSPoint) -> NSRect? {
        bestScreenFrame(for: NSRect(origin: point, size: .zero), screenFrames: NSScreen.screens.map(\.visibleFrame))
    }

    static func caretIndex(for client: any IMKTextInput) -> Int? {
        let selectedRange = client.selectedRange()
        if selectedRange.location != NSNotFound {
            return max(0, selectedRange.location)
        }

        let markedRange = client.markedRange()
        if markedRange.location != NSNotFound {
            return max(0, markedRange.location + markedRange.length)
        }

        return nil
    }

    private static func candidateRanges(for client: any IMKTextInput) -> [NSRange] {
        var ranges: [NSRange] = []

        let selectedRange = client.selectedRange()
        if selectedRange.location != NSNotFound {
            ranges.append(selectedRange)
            if selectedRange.length == 0 {
                ranges.append(NSRange(location: selectedRange.location, length: 1))
            }
        }

        let markedRange = client.markedRange()
        if markedRange.location != NSNotFound {
            let caretLocation = markedRange.location + markedRange.length
            ranges.append(NSRange(location: caretLocation, length: 0))
            ranges.append(markedRange)
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
}
