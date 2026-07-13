import Foundation

/// Musical-key detection via the Krumhansl-Schmuckler algorithm. Replaces
/// `features.py::key_essentia` (Essentia's `KeyExtractor`, which was optional and
/// returned `None` when Essentia was absent — most installs). K-S is the classic,
/// fully-deterministic key-finder: correlate the track's average 12-bin chroma
/// against the 24 Krumhansl-Kessler tonal-hierarchy profiles (major/minor × 12
/// tonics); the best Pearson correlation names the key. Pure Swift, no native dep
/// — a strict upgrade over the "usually None" Essentia path.
///
/// The chroma is the same mel-band-energy proxy `Structure` already uses (not
/// CQT-chroma), so the key is an approximation — good enough to fill the schema's
/// `key` field, honest about its provenance, and never a crash. Output format
/// matches Essentia's `"<note> <scale>"` (e.g. `"C major"`, `"A minor"`).
public enum MusicalKey {
    /// Krumhansl-Kessler major/minor key profiles (tonal hierarchy weights), tonic at index 0.
    private static let majorProfile: [Double] =
        [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] =
        [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    private static let noteNames =
        ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Detect the key from a global 12-bin chroma vector (index 0 = C). Returns
    /// `nil` for a degenerate chroma (silence / flat energy) where no key is
    /// meaningful — mirroring the Python's `None`.
    public static func detect(chroma: [Double]) -> String? {
        guard chroma.count == 12, chroma.contains(where: { $0 > 0 }) else { return nil }

        var best: (corr: Double, name: String)?
        for tonic in 0..<12 {
            let major = rotated(majorProfile, tonic: tonic)
            let minor = rotated(minorProfile, tonic: tonic)
            if let c = pearson(chroma, major) {
                if best == nil || c > best!.corr { best = (c, "\(noteNames[tonic]) major") }
            }
            if let c = pearson(chroma, minor) {
                if best == nil || c > best!.corr { best = (c, "\(noteNames[tonic]) minor") }
            }
        }
        // A negative best correlation means the chroma matches no tonal profile — not a real key.
        guard let winner = best, winner.corr > 0 else { return nil }
        return winner.name
    }

    /// The expected chroma profile for a key (K-K weights rotated to `tonic`).
    /// Exposed for tests: feeding `detect` exactly this vector yields Pearson 1.0
    /// for `(tonic, major)` and < 1.0 for every other rotation/mode, so that key
    /// is the unique winner — ground truth without music-theory guesswork.
    static func keyProfile(tonic: Int, major: Bool) -> [Double] {
        rotated(major ? majorProfile : minorProfile, tonic: tonic)
    }

    /// Profile shifted so its tonic aligns with pitch class `tonic`: expected
    /// weight at pitch class `p` is `profile[(p - tonic) mod 12]`.
    private static func rotated(_ profile: [Double], tonic: Int) -> [Double] {
        (0..<12).map { profile[(($0 - tonic) % 12 + 12) % 12] }
    }

    /// Pearson correlation of two equal-length vectors; `nil` if either is constant.
    private static func pearson(_ a: [Double], _ b: [Double]) -> Double? {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n
        let mb = b.reduce(0, +) / n
        var cov = 0.0, va = 0.0, vb = 0.0
        for i in 0..<a.count {
            let da = a[i] - ma, db = b[i] - mb
            cov += da * db; va += da * da; vb += db * db
        }
        guard va > 0, vb > 0 else { return nil }
        return cov / (va * vb).squareRoot()
    }
}
