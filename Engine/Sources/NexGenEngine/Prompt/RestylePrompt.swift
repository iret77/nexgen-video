import Foundation

/// The composition-preserving prompt profile (#223, #166) — the OPPOSITE of a generation prompt.
///
/// A restyle re-renders existing footage: the look changes, the film does not. Surfaces, light and
/// colour are the target; perspective, camera angle, composition and the exact position of every
/// element must survive 1:1. That inverts every instinct a generative prompt encodes — a generator is
/// asked to invent, a restyle is asked to invent *nothing* — so it needs its own template and its own
/// lint rather than riding the generation profile.
///
/// Port of `RESTYLE_TEMPLATE` (`musicvideo/bible/scene3d/restyle.py:17-25`). Built once, used twice:
/// the video-to-video restyle pass on delivered/imported clips (#223) and the scene-3d clay→style
/// still pass (#166) share this discipline exactly.
public enum RestylePrompt {
    /// The preservation clause, composed into every restyle prompt DETERMINISTICALLY — the engine
    /// states it, rather than asking the agent to remember to.
    ///
    /// The Python template ends "Do not add, remove, move, or duplicate any element." The DISCIPLINE
    /// ports; that phrasing does not. This engine holds — on evidence, which is why `PositivePhrasing`
    /// and the Seedance builder's positive constraints exist — that negations weaken a prompt, and
    /// `PROMPT_CONTAINS_NEGATION` flags them. Porting the words literally would import a practice this
    /// codebase deliberately rejects AND fire a false lint on every single restyle. So the no-invention
    /// rule is stated positively, which says exactly the same thing to the model.
    public static let preservationClause =
        "Apply the style to surfaces, lighting, and colour only. Keep the perspective, camera angle, "
        + "composition, and the EXACT position of every element 1:1 from the input. Every element in "
        + "the output is one that already exists in the input, in the same place and the same count."

    /// Compose a restyle instruction from the desired style. The style is the ONLY free variable; the
    /// preservation clause is fixed.
    public static func instruction(style: String) -> String {
        let trimmed = style.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return preservationClause }
        return "Restyle the input to: \(trimmed). " + preservationClause
    }

    /// Verbs that ask the model to CHANGE THE FILM rather than its look. In a generation prompt these
    /// are ordinary; in a restyle they contradict the one guarantee the pass makes, so they block —
    /// caught before the render, not after it has quietly re-staged the shot.
    ///
    /// Whole-word matched, so "additional grain" passes. It is deliberately blunt about intent, not
    /// target: "remove grain" is a SURFACE ask and still trips, because distinguishing it from "remove
    /// the lamp" needs to understand the noun, and guessing there would let real re-staging through.
    /// The finding names the way out, and it is the way the house wants it written anyway — state the
    /// result positively ("clean, grain-free surfaces"), not as a removal.
    static let inventionVerbs = [
        "add", "adds", "adding", "insert", "inserts", "inserting",
        "remove", "removes", "removing", "delete", "deletes", "deleting",
        "move", "moves", "moving", "reposition", "repositions", "repositioning",
        "duplicate", "duplicates", "duplicating",
        "replace", "replaces", "replacing",
    ]

    /// Phrases that name a COMPOSITIONAL change — reframing the shot is not restyling it.
    static let recompositionPhrases = [
        "zoom in", "zoom out", "pan to", "crop to", "reframe", "new camera angle",
        "different angle", "wider shot", "closer shot", "change the framing",
    ]

    public struct Finding: Sendable, Equatable {
        public let code: String
        public let message: String
        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    /// Lint a restyle INTENT (the author's ask, before composition). Findings are blocking: every one
    /// of them means the prompt is asking for something a composition-preserving pass cannot honour, so
    /// the model would either ignore it or silently break the guarantee. Both are worth a cheap refusal
    /// instead of an expensive render.
    public static func lintIntent(_ intent: String) -> [Finding] {
        let lower = intent.lowercased()
        var out: [Finding] = []
        if let verb = inventionVerbs.first(where: { containsWord(lower, $0) }) {
            out.append(Finding(
                code: "RESTYLE_ASKS_INVENTION",
                message: "a restyle changes the LOOK, not the film — \"\(verb)\" asks it to change what "
                    + "is in the shot, and this pass keeps every element's identity and position 1:1. "
                    + "If you meant a SURFACE (\"\(verb) grain\"), say the result instead: "
                    + "\"clean, grain-free surfaces\". If you really meant the shot's contents, that's "
                    + "an edit/inpaint pass, not a restyle."))
        }
        if let phrase = recompositionPhrases.first(where: { lower.contains($0) }) {
            out.append(Finding(
                code: "RESTYLE_ASKS_RECOMPOSITION",
                message: "\"\(phrase)\" asks for a different framing, which a restyle cannot do — it "
                    + "keeps the perspective, camera angle and composition of the input. Reframe on the "
                    + "timeline (or crop) instead."))
        }
        return out
    }

    /// Whole-word containment — so "addition" doesn't trip on "add" and "removed" doesn't trip twice.
    /// Deliberately simple and ASCII-boundary based: the vocabulary is fixed English craft terms.
    static func containsWord(_ haystack: String, _ word: String) -> Bool {
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: word, range: searchRange) {
            let beforeOK = found.lowerBound == haystack.startIndex
                || !haystack[haystack.index(before: found.lowerBound)].isLetter
            let afterOK = found.upperBound == haystack.endIndex
                || !haystack[found.upperBound].isLetter
            if beforeOK && afterOK { return true }
            guard found.upperBound < haystack.endIndex else { return false }
            searchRange = found.upperBound..<haystack.endIndex
        }
        return false
    }
}
