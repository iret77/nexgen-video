import Foundation
import Testing
@testable import NexGenVideo
import MusicvideoPlugin

/// #214 — the `record_affect` tool schema constrains the agent to an affect vocabulary the host spells
/// out by hand (`AffectTagVocabulary`), because the app target does not link the pack. This asserts it
/// mirrors `MusicvideoPlugin.AffectTag` exactly, so a new affect tag can't silently fall out of the
/// tool schema (the agent could then never select it) — the drift fails CI instead.
@Suite("affect tag vocabulary parity")
struct AffectTagVocabularyParityTests {
    @Test("the host tool vocabulary matches the pack's AffectTag raw values exactly")
    func parity() {
        let pack = Set(AffectTag.allCases.map(\.rawValue))
        let host = Set(AffectTagVocabulary.all)
        let missing = pack.subtracting(host)
        let extra = host.subtracting(pack)
        #expect(missing.isEmpty, "record_affect vocabulary is missing affect tags present in AffectTag")
        #expect(extra.isEmpty, "record_affect vocabulary has tags absent from AffectTag")
        // No duplicates crept into the hand-maintained list.
        #expect(AffectTagVocabulary.all.count == Set(AffectTagVocabulary.all).count)
    }
}
