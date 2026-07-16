import Foundation
import Testing
@testable import NexGenEngine

/// #223 / #166 — the composition-preserving prompt profile. A restyle changes the LOOK, not the film;
/// these pin the discipline that makes that true, and the refusals that keep an impossible ask from
/// reaching a paid render.
@Suite("restyle prompt profile (#223)")
struct RestylePromptTests {

    // MARK: - The clause

    @Test("the preservation clause names what may change and what must not")
    func clauseCarriesTheDiscipline() {
        let clause = RestylePrompt.preservationClause.lowercased()
        // What may change.
        #expect(clause.contains("surfaces"))
        #expect(clause.contains("lighting"))
        #expect(clause.contains("colour"))
        // What must not.
        #expect(clause.contains("perspective"))
        #expect(clause.contains("camera angle"))
        #expect(clause.contains("composition"))
        // The explicit no-invention rule.
        #expect(clause.contains("do not add, remove, move, or duplicate"))
    }

    @Test("the instruction carries the style and always keeps the clause")
    func instructionKeepsClause() {
        let text = RestylePrompt.instruction(style: "charcoal drawing")
        #expect(text.contains("charcoal drawing"))
        #expect(text.contains(RestylePrompt.preservationClause))
    }

    @Test("an empty style still yields the clause — never an empty instruction")
    func emptyStyleStillPreserves() {
        #expect(RestylePrompt.instruction(style: "   ") == RestylePrompt.preservationClause)
    }

    // MARK: - Refusing what a restyle cannot do

    @Test("an intent that asks the pass to invent is refused")
    func refusesInvention() {
        for intent in [
            "add a neon sign above the door",
            "remove the car from the street",
            "move the singer to the left",
            "replace the guitar with a violin",
            "duplicate the crowd",
        ] {
            let findings = RestylePrompt.lintIntent(intent)
            #expect(findings.contains { $0.code == "RESTYLE_ASKS_INVENTION" },
                    "expected an invention finding for: \(intent)")
        }
    }

    @Test("an intent that asks for a different framing is refused")
    func refusesRecomposition() {
        for intent in ["zoom in on her face", "reframe to a wider shot", "give me a new camera angle"] {
            #expect(RestylePrompt.lintIntent(intent).contains { $0.code == "RESTYLE_ASKS_RECOMPOSITION" },
                    "expected a recomposition finding for: \(intent)")
        }
    }

    @Test("a real restyle intent passes clean")
    func acceptsRestyle() {
        for intent in [
            "charcoal drawing, heavy grain, muted paper tones",
            "neon-noir grading with wet asphalt highlights",
            "claymation surfaces, soft studio light",
            "make it look like a faded 1970s super-8 print",
        ] {
            #expect(RestylePrompt.lintIntent(intent).isEmpty, "should pass: \(intent)")
        }
    }

    @Test("whole-word matching — a style word that merely contains a verb doesn't trip the lint")
    func wholeWordMatching() {
        // "additional"/"addition" contain "add"; "removed" is a real verb form and SHOULD trip.
        #expect(RestylePrompt.lintIntent("additional grain and paper texture").isEmpty)
        #expect(!RestylePrompt.lintIntent("remove the lamp").isEmpty)
        #expect(RestylePrompt.containsWord("add a sign", "add"))
        #expect(!RestylePrompt.containsWord("additional grain", "add"))
    }

    @Test("the lint is case-insensitive")
    func caseInsensitive() {
        #expect(!RestylePrompt.lintIntent("ADD a neon sign").isEmpty)
        #expect(!RestylePrompt.lintIntent("Zoom In on the door").isEmpty)
    }
}
