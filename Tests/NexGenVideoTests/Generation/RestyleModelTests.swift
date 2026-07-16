import Foundation
import Testing
@testable import NexGenVideo
import NexGenEngine

/// #223 — Gen-4 Aleph on the source-video edit path, and the profile selecting itself from the model.
@Suite("restyle model wiring (#223)")
@MainActor
struct RestyleModelTests {

    @Test("Aleph is registered as a source-video edit model")
    func alephRequiresSourceVideo() throws {
        let model = try #require(RunwayModelRegistry.model(for: "runway/gen4_aleph"))
        #expect(model.apiModel == "gen4_aleph")
        // requiresSourceVideo is what routes it to the edit path AND selects the restyle prompt profile.
        #expect(RunwayModelRegistry.requiresSourceVideo(model))
        // The i2v models must NOT be treated as restyles.
        let gen45 = try #require(RunwayModelRegistry.model(for: "runway/gen4.5"))
        #expect(!RunwayModelRegistry.requiresSourceVideo(gen45))
    }

    @Test("Aleph advertises no durations — the output follows the source clip")
    func alephHasNoDurationKnob() throws {
        let model = try #require(RunwayModelRegistry.model(for: "runway/gen4_aleph"))
        guard case .video(let caps) = model.entry.uiCapabilities else {
            Issue.record("expected video capabilities"); return
        }
        // A duration here would be a knob that does nothing.
        #expect(caps.durations.isEmpty)
        // The source clip is the input; it takes no reference images.
        #expect(caps.maxTotalReferences == 0)
        #expect(!caps.requiresReferenceImage)
    }

    @Test("Aleph is a Runway model and resolves to the Runway provider")
    func alephRoutesToRunway() {
        #expect(RunwayModelRegistry.isRunwayModel("runway/gen4_aleph"))
        #expect(ProviderManifest.nominalProvider(forModelId: "runway/gen4_aleph") == .runway)
    }

    @Test("it was the first model on the edit path — which is no longer a facade")
    func editPathNowHasAModel() {
        // generateVideoEdit and the submission's requiresSourceVideo branch existed with nothing
        // routing to them. If this ever returns empty again, the edit path is dead code once more.
        let editModels = RunwayModelRegistry.models.filter { RunwayModelRegistry.requiresSourceVideo($0) }
        #expect(!editModels.isEmpty)
    }
}
