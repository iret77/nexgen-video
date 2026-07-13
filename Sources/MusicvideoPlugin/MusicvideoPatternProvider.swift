import Foundation
import NexGenEngine

/// The musicvideo pack's `PatternProviding` implementation — the live wire from the agent's
/// `suggest_patterns`/`get_pattern` tools to the ported pattern library. Scores/loads real patterns and
/// returns JSON the host relays. Fixes the agent-path half of the pattern regression (#185).
public struct MusicvideoPatternProvider: PatternProviding {
    public init() {}

    public func suggest(
        visualMedium: String?, mood: String?, perceivedBPM: Double?, concept: String?,
        figures: String?, aspect: String?, maxResults: Int, allowGenreCross: Bool
    ) throws -> Data {
        let scored = try Patterns.scorePatterns(
            visualMedium: visualMedium.flatMap(VisualMedium.init(rawValue:)),
            mood: mood.flatMap(MoodBand.init(rawValue:)),
            perceivedBPM: perceivedBPM,
            concept: concept.flatMap(ConceptType.init(rawValue:)),
            figures: figures.flatMap(FigurePresence.init(rawValue:)),
            aspect: aspect.flatMap(AspectRatio.init(rawValue:)),
            maxResults: max(1, maxResults), minScore: 0, allowGenreCross: allowGenreCross)
        let array: [[String: Any]] = scored.map { pattern, score in
            [
                "id": pattern.id,
                "name": pattern.name,
                "score": score.score,
                "why": score.hitSummary(),
                "sources": pattern.references.flatMap(\.sources).map { ["label": $0.label, "url": $0.url] },
            ]
        }
        return try JSONSerialization.data(withJSONObject: array, options: [.sortedKeys])
    }

    public func get(id: String) throws -> Data? {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
            let pattern = try Patterns.loadAllPatterns().first(where: { $0.id == trimmed }) else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(pattern)
    }
}
