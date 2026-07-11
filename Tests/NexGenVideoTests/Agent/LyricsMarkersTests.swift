import Foundation
import Testing
@testable import NexGenVideo

@Suite("Lyrics section markers")
struct LyricsMarkersTests {
    @Test("extracts [Section] markers in order, ignoring plain lines, blanks, and empty brackets")
    func extracts() {
        let text = """
        [Intro]

        [Verse 1]
        walking down the street
        [Chorus]
        she runs the show
        [ ]
        [Verse 2]
        """
        #expect(AgentService.lyricsSectionMarkers(text) == ["Intro", "Verse 1", "Chorus", "Verse 2"])
    }

    @Test("lyrics without markers yield no sections")
    func none() {
        #expect(AgentService.lyricsSectionMarkers("just\nsome\nplain lyrics").isEmpty)
    }
}

@Suite("Identity slug")
struct IdentitySlugTests {
    @Test("names become filesystem-safe folder slugs")
    func slugs() {
        #expect(AgentService.identitySlug("Claude Mouse") == "claude-mouse")
        #expect(AgentService.identitySlug("  The AI Cat!!  ") == "the-ai-cat")
        #expect(AgentService.identitySlug("Café_déjà 2") == "café-déjà-2")
        #expect(AgentService.identitySlug("---") == "")
    }
}
