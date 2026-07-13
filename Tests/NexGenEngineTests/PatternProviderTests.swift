import Foundation
import Testing
@testable import MusicvideoPlugin
@testable import NexGenEngine

/// The pack's PatternProviding seam — the agent-callable path to the library (#185 second half).
@Suite("Pattern provider", .serialized)
struct PatternProviderTests {
    private func provider() throws -> any PatternProviding {
        PackCatalog.register(MusicvideoPack())
        return try #require(PackCatalog.registry(activePack: "musicvideo").patternProvider,
                            "musicvideo should register a PatternProviding")
    }

    @Test("suggest returns scored patterns as JSON with id/name/score/why/sources")
    func suggest() throws {
        let data = try provider().suggest(
            visualMedium: nil, mood: nil, perceivedBPM: nil, concept: nil, figures: nil, aspect: nil,
            maxResults: 5, allowGenreCross: false)
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(!array.isEmpty)
        let first = try #require(array.first)
        #expect(first["id"] as? String != nil)
        #expect(first["name"] as? String != nil)
        #expect(first["score"] as? Int != nil)
        #expect(first["why"] as? String != nil)
        #expect(first["sources"] as? [Any] != nil)
    }

    @Test("get returns the full pattern JSON for a real id, nil for an unknown one")
    func getById() throws {
        let p = try provider()
        // Discover a real id from suggest, then load it.
        let sugg = try JSONSerialization.jsonObject(
            with: try p.suggest(visualMedium: nil, mood: nil, perceivedBPM: nil, concept: nil,
                                figures: nil, aspect: nil, maxResults: 1, allowGenreCross: false)) as? [[String: Any]]
        let id = try #require(sugg?.first?["id"] as? String)

        let data = try #require(try p.get(id: id), "a suggested id must be loadable")
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["id"] as? String == id)
        #expect(obj["framing_mix"] != nil)   // the field PATTERN_DRIFT + the measured contract consume
        #expect(obj["asl_range"] != nil)

        #expect(try p.get(id: "no-such-pattern-xyz") == nil)
        #expect(try p.get(id: "   ") == nil)
    }
}
