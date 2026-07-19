import Foundation
import Testing

@testable import NexGenVideo

/// Text documents in the media library — story scripts, outlines, notes. They are source MATERIAL the
/// pipeline reads, not something that can be cut into the timeline. The trap this guards: `.text`
/// already means "a title clip with no source file", so a script on disk must NOT reuse it.
@Suite("document assets")
struct DocumentAssetTests {

    @Test("script extensions import as documents")
    func scriptExtensionsMap() {
        for ext in ["txt", "md", "markdown", "rtf", "fountain"] {
            #expect(ClipType(fileExtension: ext) == .document)
        }
    }

    @Test("a document is NOT the title-clip kind")
    func documentIsNotTitleText() {
        // `.text` means "no source media" to the timeline (TimelineInputController keys on it). A
        // file-backed script mapped to `.text` would be treated as having no file at all.
        #expect(ClipType(fileExtension: "md") != .text)
        #expect(ClipType.document.isVisual == false)
    }

    @Test("the media kinds that already worked still map the same way")
    func existingMappingsUnchanged() {
        #expect(ClipType(fileExtension: "mp4") == .video)
        #expect(ClipType(fileExtension: "wav") == .audio)
        #expect(ClipType(fileExtension: "png") == .image)
        #expect(ClipType(fileExtension: "lottie") == .lottie)
        #expect(ClipType(fileExtension: "exe") == nil)
    }

    @Test("a document can never become a timeline clip")
    func documentIsNotPlaceable() {
        #expect(ClipType.document.isPlaceable == false)
        for placeable in [ClipType.video, .audio, .image, .text, .lottie] {
            #expect(placeable.isPlaceable)
        }
    }

    @Test("compatibility never pairs a document with a track")
    func documentIsCompatibleWithNothing() {
        // Without this, `isVisual`-style reasoning could let a document land on a video track.
        for other in ClipType.allCases {
            #expect(ClipType.document.isCompatible(with: other) == false)
            #expect(other.isCompatible(with: .document) == false)
        }
    }

    @Test("the visual kinds still accept each other")
    func visualCompatibilityIntact() {
        #expect(ClipType.video.isCompatible(with: .image))
        #expect(ClipType.image.isCompatible(with: .text))
        #expect(ClipType.audio.isCompatible(with: .audio))
        #expect(ClipType.audio.isCompatible(with: .video) == false)
    }

    @Test("a document has an icon and a label of its own")
    func documentPresents() {
        #expect(ClipType.document.sfSymbolName == "doc.text")
        #expect(ClipType.document.trackLabel == "Document")
        #expect(ClipType.document.trackLabelPrefix == "D")
    }
}
