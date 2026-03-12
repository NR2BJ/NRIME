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
}
