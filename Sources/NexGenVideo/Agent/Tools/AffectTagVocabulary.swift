import Foundation

/// The affect vocabulary the `record_affect` tool schema constrains the agent to (#214). The host does
/// not link the musicvideo pack, so this mirrors `MusicvideoPlugin.AffectTag`'s raw values as a wire
/// contract. `AffectTagVocabularyParityTests` (which links both) fails if the two ever drift, so this
/// stays honest without a compile-time dependency across the seam.
enum AffectTagVocabulary {
    static let all: [String] = [
        "aggressive", "anthemic", "cinematic", "confrontational", "dark", "dreamy", "euphoric",
        "fragile", "high_energy", "humorous", "intimate", "introspective", "ironic", "melancholic",
        "meditative", "narrative", "playful", "poetic", "rebellious", "romantic", "surreal", "tense",
        "triumphant", "urgent", "warm",
    ]
}
