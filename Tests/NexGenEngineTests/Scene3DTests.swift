import Foundation
import Testing
@testable import MusicvideoPlugin
@testable import NexGenEngine

/// #166 — the scene-geometry half that isn't pixels: the typed 3D reference and the camera derivation
/// that makes a reverse shot land on real geometry instead of an invented wall.
@Suite("scene3d reference (#166)")
struct Scene3DTests {

    // MARK: - Reverse derivation

    @Test("the four cardinal walls all have an opposite")
    func cardinalWallsAllReverse() {
        #expect(Scene3DCamera.viewsWithoutReverse(in: defaultFourWallPovs).isEmpty)
        #expect(Scene3DCamera.reverse(of: "wide_front", in: defaultFourWallPovs)?.name == "wide_back")
        #expect(Scene3DCamera.reverse(of: "wide_back", in: defaultFourWallPovs)?.name == "wide_front")
        #expect(Scene3DCamera.reverse(of: "wide_left", in: defaultFourWallPovs)?.name == "wide_right")
        #expect(Scene3DCamera.reverse(of: "wide_right", in: defaultFourWallPovs)?.name == "wide_left")
    }

    /// The relationship that the original port got wrong: it asserted `back == −front` as VECTORS,
    /// which only holds for a level camera. The real POVs are tilted 5° down, and a camera turned
    /// around is still tilted 5° DOWN — so the vector identity fails while the views are still
    /// genuinely opposite. Reverses are a HEADING relation.
    @Test("reverses hold at a tilt, where the old vector identity does not")
    func reversesHoldAtTilt() {
        let front = PovSpec(name: "f", yawDegrees: 0)     // pitch −5 by default
        let back = PovSpec(name: "b", yawDegrees: 180)
        #expect(front.pitchDegrees == -5 && back.pitchDegrees == -5)
        // The vector identity the old test asserted is FALSE here — the tilt doesn't flip.
        #expect(back.forwardDirection != -front.forwardDirection)
        // The heading relation is what actually holds, and it's what we derive on.
        #expect(Scene3DCamera.areReverses(front, back))
    }

    @Test("yawDelta takes the short way around the wrap")
    func yawDeltaWraps() {
        #expect(Scene3DCamera.yawDelta(from: 170, to: -170) == 20)
        #expect(Scene3DCamera.yawDelta(from: -170, to: 170) == -20)
        #expect(Scene3DCamera.yawDelta(from: 0, to: 180) == 180)
        #expect(Scene3DCamera.yawDelta(from: 0, to: 0) == 0)
    }

    @Test("a POV set with no opposing view reports its orphans rather than inventing one")
    func orphanViewsReported() {
        let half = [PovSpec(name: "front", yawDegrees: 0), PovSpec(name: "right", yawDegrees: 90)]
        #expect(Scene3DCamera.reverse(of: "front", in: half) == nil)
        #expect(Set(Scene3DCamera.viewsWithoutReverse(in: half)) == Set(["front", "right"]))
    }

    @Test("nearest view resolves a heading across the wrap")
    func nearestAcrossWrap() {
        #expect(Scene3DCamera.nearest(toYaw: 170, in: defaultFourWallPovs)?.name == "wide_back")
        #expect(Scene3DCamera.nearest(toYaw: -175, in: defaultFourWallPovs)?.name == "wide_back")
        #expect(Scene3DCamera.nearest(toYaw: 10, in: defaultFourWallPovs)?.name == "wide_front")
        #expect(Scene3DCamera.nearest(toYaw: 0, in: []) == nil)
    }

    // MARK: - Typed schema

    @Test("a bible written before the POV set existed still decodes — no migration needed")
    func decodesLegacyFreeFormShape() throws {
        // The old shape was a free-form string map of which only `panorama` was ever read.
        let json = Data(#"{"panorama":"bible/room/pano.png"}"#.utf8)
        let scene3d = try JSONDecoder().decode(Scene3D.self, from: json)
        #expect(scene3d.panorama == "bible/room/pano.png")
        #expect(scene3d.povs.isEmpty)
        #expect(scene3d.provider.isEmpty)
    }

    @Test("an absent scene3d is an empty reference, not an error")
    func decodesEmpty() throws {
        let scene3d = try JSONDecoder().decode(Scene3D.self, from: Data("{}".utf8))
        #expect(scene3d.isEmpty)
    }

    @Test("the POV set round-trips as geometry, and its names are the sheet keys")
    func roundTripsGeometry() throws {
        let scene3d = Scene3D(
            panorama: "bible/room/pano.png",
            povs: defaultFourWallPovs.map(Scene3D.PovRecord.init),
            provider: "marble")
        let decoded = try JSONDecoder().decode(Scene3D.self, from: try JSONEncoder().encode(scene3d))
        #expect(decoded == scene3d)
        // The recorded geometry reconstructs the same specs the extractor cut with.
        #expect(decoded.specs.map(\.name) == defaultFourWallPovs.map(\.name))
        #expect(Scene3DCamera.reverse(of: "wide_front", in: decoded.specs)?.name == "wide_back")
    }
}

/// The scene3d_geometry check — the audit that keeps the geometry guarantee from quietly lapsing.
@Suite("scene3d_geometry check (#166)")
struct Scene3DGeometryCheckTests {
    static func location(
        _ id: String, sheets: [String: String] = [:], scene3d: Scene3D = Scene3D()
    ) throws -> Location {
        try Location(id: id, name: id, visualPrompt: "a room", sheets: sheets, scene3d: scene3d)
    }

    static func bible(_ locations: [Location]) throws -> Bible {
        try Bible(project: "p", generated: "t", generator: "g", locations: locations)
    }

    /// A shotlist is only a carrier here — the check reads the bible's locations, not the shots. It
    /// still needs one shot, because an empty shotlist is invalid by construction (`.emptyShots`).
    static func ctx(_ bible: Bible) throws -> AuditContext {
        AuditContext(
            shotlist: try Shotlist(
                schema_: shotlistSchemaVersion, mode: .beat, project: "p",
                song: try Song(title: "t", audioPath: "a.wav", analysisPath: "a.json",
                               bpm: 120, tempoMultiplier: 1, durationS: 180),
                generated: "t", generator: "g",
                shots: [try Shot(id: "s001", section: "verse", timeStart: 0, timeEnd: 4, durationS: 4,
                                 type: .performance, description: "d", visualPrompt: "p", mood: "m")]),
            bible: bible)
    }

    static let fullSet = Scene3D(
        panorama: "bible/room/pano.png",
        povs: defaultFourWallPovs.map(Scene3D.PovRecord.init), provider: "marble")

    @Test("a panorama with sheets but no recorded POV geometry is flagged")
    func unrecordedPovs() throws {
        let loc = try Self.location(
            "room", sheets: ["wide_front": "bible/room/scene3d/povs/wide_front.png"],
            scene3d: Scene3D(panorama: "bible/room/pano.png"))
        let findings = try MusicvideoChecks.scene3dGeometryCheck(try Self.ctx(try Self.bible([loc])))
        #expect(findings.contains { $0.code == "SCENE3D_POVS_UNRECORDED" })
    }

    @Test("a location with no panorama at all is silent — nothing has been cut yet")
    func noPanoramaIsSilent() throws {
        let loc = try Self.location("room", sheets: ["wide": "bible/room/wide.png"])
        #expect(try MusicvideoChecks.scene3dGeometryCheck(try Self.ctx(try Self.bible([loc]))).isEmpty)
    }

    @Test("a full cardinal POV set with matching sheets passes clean")
    func fullSetPasses() throws {
        var sheets: [String: String] = [:]
        for pov in defaultFourWallPovs { sheets[pov.name] = "bible/room/scene3d/\(pov.name).png" }
        let loc = try Self.location("room", sheets: sheets, scene3d: Self.fullSet)
        #expect(try MusicvideoChecks.scene3dGeometryCheck(try Self.ctx(try Self.bible([loc]))).isEmpty)
    }

    @Test("a POV set that can't cover a reverse angle is flagged")
    func viewWithoutReverse() throws {
        let half = Scene3D(
            panorama: "bible/room/pano.png",
            povs: [PovSpec(name: "front", yawDegrees: 0), PovSpec(name: "right", yawDegrees: 90)]
                .map(Scene3D.PovRecord.init),
            provider: "marble")
        let loc = try Self.location("room", sheets: ["front": "f.png", "right": "r.png"], scene3d: half)
        let findings = try MusicvideoChecks.scene3dGeometryCheck(try Self.ctx(try Self.bible([loc])))
        #expect(findings.contains { $0.code == "SCENE3D_VIEW_WITHOUT_REVERSE" })
    }

    @Test("a sheet that was never cut from the panorama is flagged as outside the guarantee")
    func straySheet() throws {
        var sheets: [String: String] = [:]
        for pov in defaultFourWallPovs { sheets[pov.name] = "bible/room/scene3d/\(pov.name).png" }
        sheets["hand_made_detail"] = "bible/room/detail.png"
        let loc = try Self.location("room", sheets: sheets, scene3d: Self.fullSet)
        let findings = try MusicvideoChecks.scene3dGeometryCheck(try Self.ctx(try Self.bible([loc])))
        let stray = try #require(findings.first { $0.code == "SCENE3D_SHEET_NOT_IN_POV_SET" })
        #expect(stray.message.contains("hand_made_detail"))
    }
}
