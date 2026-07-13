import Foundation

/// A pack-provided, agent-callable director-pattern query surface. The generic engine declares the
/// seam; a format pack (e.g. musicvideo) registers a concrete provider that reads its own pattern
/// library and returns JSON the host's agent tools relay. JSON (`Data`) is the currency so the engine
/// stays agnostic of the pack's `Pattern` schema — the same dependency-inversion the audio-ML seams use.
///
/// This is the sanctioned path to the pattern library the predecessor had and the port lost (#185): the
/// agent discovers patterns via `suggest` and loads one via `get`, instead of the ported YAMLs sitting
/// as dead data with no caller.
public protocol PatternProviding: Sendable {
    /// Top-N patterns matching the given brief dimensions (raw enum strings the agent supplies; nil =
    /// unconstrained on that axis), returned as a JSON array of `{id, name, score, why, sources}`.
    /// `allowGenreCross` lifts the visual-medium veto. Throws only on an internal library error.
    func suggest(
        visualMedium: String?, mood: String?, perceivedBPM: Double?, concept: String?,
        figures: String?, aspect: String?, maxResults: Int, allowGenreCross: Bool
    ) throws -> Data

    /// The full pattern for `id` as JSON (framing_mix, asl_range, camera vocabulary, lighting signature,
    /// section arc, references, triggers), or nil when no pattern has that id.
    func get(id: String) throws -> Data?
}
