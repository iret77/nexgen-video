import Foundation
import Testing
@testable import MusicvideoPlugin

/// Krumhansl-Schmuckler key detection (B3). Tests the pure algorithm over chroma
/// vectors (the DSP pipeline itself SIGTRAPs under swiftpm, #118, so key detection
/// is exercised via the pure `detect(chroma:)` entry point).
///
/// Feeding `detect` the exact K-K profile of a key gives Pearson 1.0 for that key
/// and < 1.0 for every other rotation/mode — so the expected key is the unique
/// winner. That grounds the assertions in ground truth instead of hand-tuned
/// "musical" chroma that could ambiguously resolve to a relative/neighbor key.
@Suite("musical key (Krumhansl-Schmuckler)")
struct MusicalKeyTests {
    @Test("the C-major profile reads as C major")
    func cMajor() {
        #expect(MusicalKey.detect(chroma: MusicalKey.keyProfile(tonic: 0, major: true)) == "C major")
    }

    @Test("major/minor discrimination: the A-minor profile reads as A minor, not its relative C major")
    func aMinor() {
        #expect(MusicalKey.detect(chroma: MusicalKey.keyProfile(tonic: 9, major: false)) == "A minor")
    }

    @Test("transposition + note naming: the G-major profile reads as G major")
    func gMajor() {
        #expect(MusicalKey.detect(chroma: MusicalKey.keyProfile(tonic: 7, major: true)) == "G major")
    }

    @Test("every one of the 24 keys round-trips through detect")
    func allKeys() {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        for t in 0..<12 {
            #expect(MusicalKey.detect(chroma: MusicalKey.keyProfile(tonic: t, major: true)) == "\(names[t]) major")
            #expect(MusicalKey.detect(chroma: MusicalKey.keyProfile(tonic: t, major: false)) == "\(names[t]) minor")
        }
    }

    @Test("degenerate chroma yields no key")
    func degenerate() {
        #expect(MusicalKey.detect(chroma: [Double](repeating: 0, count: 12)) == nil)   // silence
        #expect(MusicalKey.detect(chroma: [Double](repeating: 1, count: 12)) == nil)   // flat / atonal
        #expect(MusicalKey.detect(chroma: [1, 2, 3]) == nil)                           // wrong length
    }
}
