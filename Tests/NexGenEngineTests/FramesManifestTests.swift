import Foundation
import Testing
@testable import NexGenEngine

@Suite("FramesManifest")
struct FramesManifestTests {
    @Test("upserting creates the shot, appends by role, replaces same-role frames")
    func upsert() {
        var m = FramesManifest(project: "p", generated: "t")
        m = m.upserting(shotId: "s001", keyframeStrategy: "start_end",
                        frame: FrameEntry(role: "start", path: "a.png", providerPrompt: "v1"))
        #expect(m.shots.count == 1)
        #expect(m.shot("s001")?.frames.count == 1)

        m = m.upserting(shotId: "s001", keyframeStrategy: "start_end",
                        frame: FrameEntry(role: "end", path: "b.png", providerPrompt: "v2"))
        #expect(m.shot("s001")?.frames.count == 2)   // different role → appended

        m = m.upserting(shotId: "s001", keyframeStrategy: "start_end",
                        frame: FrameEntry(role: "start", path: "a2.png", providerPrompt: "v3"))
        #expect(m.shot("s001")?.frames.count == 2)   // same role → replaced, not appended
        #expect(m.shot("s001")?.frames.first { $0.role == "start" }?.path == "a2.png")
        #expect(m.shot("s001")?.keyframeStrategy == "start_end")
    }

    @Test("JSON round-trips with snake_case keys")
    func roundTrip() throws {
        let m = FramesManifest(project: "p", generated: "t", shots: [
            ShotFrames(shotId: "s001", keyframeStrategy: "start", frames: [
                FrameEntry(role: "start", path: "media/g.png", runwayModel: "fal:nano",
                           providerPrompt: "compiled", multiRefHints: ["Image 1: hero"])])])
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(m)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"provider_prompt\""))
        #expect(json.contains("\"shot_id\""))
        #expect(json.contains("\"runway_model\""))
        #expect(try JSONDecoder().decode(FramesManifest.self, from: data) == m)
    }

    @Test("a legacy manifest missing the optional per-frame fields still decodes")
    func lenientDecode() throws {
        let json = """
        {"project":"p","generated":"t","shots":[{"shot_id":"s001","frames":[{"role":"start","path":"a.png"}]}]}
        """
        let m = try JSONDecoder().decode(FramesManifest.self, from: Data(json.utf8))
        let frame = m.shot("s001")?.frames.first
        #expect(frame?.providerPrompt == "")     // absent → empty (what builder_bypass flags)
        #expect(frame?.approved == false)
        #expect(m.shot("s001")?.keyframeStrategy == "start")
    }
}
