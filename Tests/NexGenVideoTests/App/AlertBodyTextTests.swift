import AppKit
import Testing

@testable import NexGenVideo

/// `NSAlert.informativeText` hyphenates, which chopped a pack id mid-word in the field
/// ("musi-cvideo") — unacceptable for a name the user has to recognize. The body is our own label so
/// the paragraph style can forbid it; this pins that, because such a regression is silent.
@MainActor
@Suite("alert body forbids hyphenation")
struct AlertBodyTextTests {

    private func paragraphStyle(of view: NSView) -> NSParagraphStyle? {
        guard let field = view as? NSTextField, field.attributedStringValue.length > 0 else { return nil }
        return field.attributedStringValue
            .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }

    @Test("hyphenation is off and wrapping happens on word boundaries")
    func hyphenationDisabled() throws {
        let view = AppState.bodyText("Opening this project without the musicvideo pack falls back.")
        let style = try #require(paragraphStyle(of: view))
        #expect(style.hyphenationFactor == 0)
        #expect(style.lineBreakMode == .byWordWrapping)
    }

    @Test("the text survives verbatim — no truncation")
    func textIsIntact() throws {
        let text = "Built for a different version of NexGenVideo — update the pack."
        let field = try #require(AppState.bodyText(text) as? NSTextField)
        #expect(field.attributedStringValue.string == text)
        #expect(field.usesSingleLineMode == false)
    }

    @Test("the label is sized, so the alert can't clip the body to nothing")
    func labelHasSize() throws {
        let long = String(repeating: "wrapping across several lines. ", count: 4)
        let field = try #require(AppState.bodyText(long) as? NSTextField)
        #expect(field.frame.height > 0)
        #expect(field.frame.width > 0)
    }
}
