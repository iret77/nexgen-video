import Foundation

/// A location's persistent 3D reference (#166) — the spatial anchor every shot of that location
/// derives its view from.
///
/// The problem it exists for: image and video models hold no 3D model of a space. Across the shots of
/// one location they cannot keep the geometry fixed — where the doors are, what the opposite wall
/// looks like, that the tree stays put — and they fail the rule a 2D net structurally cannot honour:
/// **what was on the left must be on the right in the reverse shot**. Characters are covered by the
/// bible's multi-angle sheets; scenes were not.
///
/// The fix is that every view of a location is cut from ONE master panorama (`EquirectProjector`), so
/// the consistency is not asked for — it is a property of the construction. This type is the record of
/// that: the panorama, the POV set's GEOMETRY (not just the images that happen to sit on disk), and
/// where the panorama came from.
///
/// Replaces the free-form `[String: String]` the bible carried, of which only `panorama` was ever read.
/// Decoding stays tolerant of that old shape — an existing bible carries `{panorama: …}` and nothing
/// else, and decodes here with an empty POV set rather than needing a migration.
public struct Scene3D: Codable, Sendable, Equatable {
    /// One POV's geometry, recorded alongside the image it produced.
    ///
    /// `name` is deliberately the `Location.sheets` key: it is what a shot's `locationView` names and
    /// what `LOCATION_VIEW_MISSING` validates against, so the geometry and the sheet are the same fact
    /// under one identifier rather than two things to keep in step.
    public struct PovRecord: Codable, Sendable, Equatable {
        public var name: String
        public var yaw: Double
        public var pitch: Double
        public var fov: Double

        public init(name: String, yaw: Double, pitch: Double, fov: Double) {
            self.name = name
            self.yaw = yaw
            self.pitch = pitch
            self.fov = fov
        }

        public init(_ spec: PovSpec) {
            self.init(name: spec.name, yaw: spec.yawDegrees,
                      pitch: spec.pitchDegrees, fov: spec.fovHorizontalDegrees)
        }

        public var spec: PovSpec {
            PovSpec(name: name, yawDegrees: yaw, pitchDegrees: pitch, fovHorizontalDegrees: fov)
        }
    }

    /// The equirectangular master, project-home-relative. Every POV is cut from THIS image — which is
    /// why opposite walls are the same wall.
    public var panorama: String
    /// The POV set that was cut, as geometry. Empty when none has been extracted yet.
    public var povs: [PovRecord]
    /// What built the panorama (`marble`, a photogrammetry pass, a hand-shot pano) — provenance, so a
    /// later reader knows how much to trust the space rather than guessing from the file.
    public var provider: String

    public init(panorama: String = "", povs: [PovRecord] = [], provider: String = "") {
        self.panorama = panorama
        self.povs = povs
        self.provider = provider
    }

    private enum CodingKeys: String, CodingKey {
        case panorama, povs, provider
    }

    /// Every field optional on the wire: a bible written before the POV set was recorded carries only
    /// `panorama`, and must keep decoding.
    ///
    /// ⚠️ Unknown keys are IGNORED, not preserved. The free-form map this replaced round-tripped any
    /// key it was given (`mesh`, `splats`, …); this type keeps only what it declares. Harmless today —
    /// nothing in the app WRITES the bible, so no decode→encode round-trip happens on a user's file —
    /// but the moment a bible writer exists, re-saving an old bible would silently drop keys it didn't
    /// know. Add those keys here (or an explicit preserve-unknowns pass) BEFORE writing bibles.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        panorama = try c.decodeIfPresent(String.self, forKey: .panorama) ?? ""
        povs = try c.decodeIfPresent([PovRecord].self, forKey: .povs) ?? []
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
    }

    /// True when this location has no spatial anchor yet — the normal state before a panorama exists.
    public var isEmpty: Bool { panorama.trimmingCharacters(in: .whitespaces).isEmpty && povs.isEmpty }

    /// The recorded POV set as specs, for the geometry helpers.
    public var specs: [PovSpec] { povs.map(\.spec) }
}
