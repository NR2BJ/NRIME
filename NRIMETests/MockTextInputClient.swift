import Cocoa
import InputMethodKit

final class MockTextInputClient: NSObject, IMKTextInput {
    private(set) var insertedTexts: [String] = []
    private(set) var markedString: String = ""
    private(set) var markedSelectionRange: NSRange = NSRange(location: 0, length: 0)
    private var plainText: String = ""
    private var currentSelectionRange: NSRange = NSRange(location: 0, length: 0)
    private var explicitMarkedRange: NSRange?

    var firstRectResponse: NSRect = NSRect(x: 100, y: 100, width: 12, height: 18)
    var attributesRectResponse: NSRect = NSRect(x: 100, y: 100, width: 12, height: 18)
    private(set) var lastFirstRectRange: NSRange?
    private(set) var lastAttributesCharacterIndex: Int?

    var bundleID: String? = "com.nrime.tests"

    func insertText(_ string: Any!, replacementRange: NSRange) {
        let text = Self.plainString(from: string)
        insertedTexts.append(text)

        if hasMarkedText() {
            plainText += text
            markedString = ""
            markedSelectionRange = NSRange(location: 0, length: 0)
            explicitMarkedRange = nil
        } else {
            plainText += text
        }

        currentSelectionRange = NSRange(location: plainText.count, length: 0)
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        markedString = Self.plainString(from: string)
        markedSelectionRange = selectionRange
        currentSelectionRange = selectionRange
        explicitMarkedRange = markedString.isEmpty
            ? nil
            : NSRange(location: plainText.count, length: markedString.count)
    }

    func selectedRange() -> NSRange {
        currentSelectionRange
    }

    func markedRange() -> NSRange {
        if let explicitMarkedRange {
            return explicitMarkedRange
        }
        guard hasMarkedText() else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: plainText.count, length: markedString.count)
    }

    func hasMarkedText() -> Bool {
        !markedString.isEmpty
    }

    func unmarkText() {
        if !markedString.isEmpty {
            plainText += markedString
            markedString = ""
            markedSelectionRange = NSRange(location: 0, length: 0)
            currentSelectionRange = NSRange(location: plainText.count, length: 0)
            explicitMarkedRange = nil
        }
    }

    func validAttributesForMarkedText() -> [Any]! {
        []
    }

    func attributedSubstring(from range: NSRange) -> NSAttributedString? {
        guard range.location != NSNotFound else { return nil }
        let fullText = plainText + markedString
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= fullText.count else {
            return nil
        }
        let start = fullText.index(fullText.startIndex, offsetBy: range.location)
        let end = fullText.index(start, offsetBy: range.length)
        return NSAttributedString(string: String(fullText[start..<end]))
    }

    func attributes(forCharacterIndex index: Int, lineHeightRectangle rect: UnsafeMutablePointer<NSRect>?) -> [AnyHashable: Any]! {
        lastAttributesCharacterIndex = index
        rect?.pointee = attributesRectResponse
        return [:]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        lastFirstRectRange = range
        actualRange?.pointee = range
        return firstRectResponse
    }

    func length() -> Int {
        composedText.count
    }

    func characterIndex(
        for point: NSPoint,
        tracking mappingMode: IMKLocationToOffsetMappingMode,
        inMarkedRange: UnsafeMutablePointer<ObjCBool>?
    ) -> Int {
        inMarkedRange?.pointee = ObjCBool(hasMarkedText())
        return 0
    }

    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}

    func selectMode(_ modeIdentifier: String!) {}

    func supportsUnicode() -> Bool {
        true
    }

    func windowLevel() -> CGWindowLevel {
        CGWindowLevelForKey(.normalWindow)
    }

    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool {
        false
    }

    func uniqueClientIdentifierString() -> String! {
        "mock-client"
    }

    func string(from range: NSRange, actualRange: NSRangePointer?) -> String! {
        actualRange?.pointee = range
        return attributedSubstring(from: range)?.string
    }

    func bundleIdentifier() -> String? {
        bundleID
    }

    var composedText: String {
        plainText + markedString
    }

    func setSelectedRange(_ range: NSRange) {
        currentSelectionRange = range
    }

    func setMarkedRangeForTesting(_ range: NSRange?) {
        explicitMarkedRange = range
    }

    private static func plainString(from value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let string as NSString:
            return string as String
        case let attributed as NSAttributedString:
            return attributed.string
        default:
            return ""
        }
    }
}
