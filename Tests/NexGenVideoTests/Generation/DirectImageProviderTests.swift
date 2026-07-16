import Foundation
import Testing
@testable import NexGenVideo

/// #212 — direct image providers (Google, OpenAI): fal is *a* way to images, not *the* way. These pin
/// the pure parts: availability filtering, the shared-id merge that makes one model reachable through
/// several providers, and the honest aspect mapping.
@Suite("direct image providers (#212)")
@MainActor
struct DirectImageProviderTests {

    // MARK: - Availability filtering (#159: only what the key really exposes)

    @Test("a Google model whose candidates the key doesn't expose is not offered at all")
    func googleDropsUnavailableModels() {
        #expect(GoogleModelRegistry.entries(availableModelIds: []).isEmpty)
        #expect(GoogleModelRegistry.entries(availableModelIds: ["some-unrelated-model"]).isEmpty)
    }

    @Test("a Google model resolves to whichever candidate id the key exposes")
    func googleResolvesCandidate() throws {
        let model = try #require(GoogleModelRegistry.models.first { $0.entry.id == "fal-ai/imagen4" })
        // Take the LAST candidate to prove it isn't just picking the first blindly.
        let fallback = try #require(model.apiModelCandidates.last)
        let entries = GoogleModelRegistry.entries(availableModelIds: [fallback])
        let entry = try #require(entries.first { $0.id == "fal-ai/imagen4" })
        let offer = try #require(entry.offers?.first)
        #expect(offer.provider == .google)
        #expect(offer.providerRef == fallback)
    }

    @Test("candidate order wins when the key exposes several")
    func googlePrefersFirstCandidate() throws {
        let model = try #require(GoogleModelRegistry.models.first { $0.entry.id == "fal-ai/imagen4" })
        let entries = GoogleModelRegistry.entries(availableModelIds: Set(model.apiModelCandidates))
        let offer = try #require(entries.first { $0.id == "fal-ai/imagen4" }?.offers?.first)
        #expect(offer.providerRef == model.apiModelCandidates.first)
    }

    @Test("an OpenAI model gated behind org verification is not offered")
    func openAIDropsUnavailableModels() {
        #expect(OpenAIModelRegistry.entries(availableModelIds: ["gpt-4o"]).isEmpty)
    }

    @Test("gpt-image-1 is offered when the key exposes it")
    func openAIOffersAvailableModel() throws {
        let entries = OpenAIModelRegistry.entries(availableModelIds: ["gpt-image-1"])
        let entry = try #require(entries.first)
        #expect(entry.id == "openai/gpt-image-1")
        let offer = try #require(entry.offers?.first)
        #expect(offer.provider == .openai)
        #expect(offer.providerRef == "gpt-image-1")
    }

    // MARK: - One model, several providers

    @Test("the Google Imagen entry shares the fal id, so the catalog merges them into ONE model")
    func googleSharesFalIdForMergedOffers() throws {
        let google = try #require(GoogleModelRegistry.models.first { $0.entry.id == "fal-ai/imagen4" })
        let fal = FalModelRegistry.entries.first { $0.id == google.entry.id }
        // A different id here would put two "Imagen 4" rows in front of the user instead of one model
        // with two routes — the thing #212 is for.
        #expect(fal != nil, "the Google entry must reuse the fal entry's id to merge offers")
        #expect(fal?.offers?.contains { $0.provider == .fal } == true)
    }

    @Test("a model offered by fal AND Google resolves to Google when only Google is activated")
    func resolvesToActivatedProvider() throws {
        let bindings = [
            ProviderBinding(provider: .fal, transport: .api, kind: .generation,
                            providerRef: "fal-ai/imagen4", billing: .perCall),
            ProviderBinding(provider: .google, transport: .api, kind: .generation,
                            providerRef: "imagen-4.0-generate-001", billing: .perCall),
        ]
        let googleOnly = ProviderActivation(active: [.init(provider: .google, transport: .api)])
        let picked = try #require(ProviderResolver.resolve(
            bindings: bindings, activation: googleOnly, effectiveCost: ProviderManifest.effectiveCost))
        #expect(picked.provider == .google)
        // The dispatch endpoint is the provider's OWN model string, not the fal id.
        #expect(picked.providerRef == "imagen-4.0-generate-001")
    }

    @Test("with both activated, the direct provider beats the fal middleman")
    func directBeatsFalWhenBothActive() throws {
        let bindings = [
            ProviderBinding(provider: .fal, transport: .api, kind: .generation,
                            providerRef: "fal-ai/imagen4", billing: .perCall),
            ProviderBinding(provider: .google, transport: .api, kind: .generation,
                            providerRef: "imagen-4.0-generate-001", billing: .perCall),
        ]
        let both = ProviderActivation(active: [
            .init(provider: .google, transport: .api), .init(provider: .fal, transport: .api),
        ])
        let picked = try #require(ProviderResolver.resolve(
            bindings: bindings, activation: both, effectiveCost: ProviderManifest.effectiveCost))
        #expect(picked.provider == .google)
    }

    @Test("nothing activated → nothing resolves, so the catalog can't offer it")
    func nothingActivatedResolvesNil() {
        let bindings = [
            ProviderBinding(provider: .google, transport: .api, kind: .generation,
                            providerRef: "imagen-4.0-generate-001", billing: .perCall),
        ]
        #expect(ProviderResolver.resolve(
            bindings: bindings, activation: ProviderActivation(active: []),
            effectiveCost: ProviderManifest.effectiveCost) == nil)
    }

    // MARK: - Honest capabilities

    @Test("gpt-image-1 advertises only the ratios it really renders — no 16:9")
    func openAIAspectsAreHonest() throws {
        let model = try #require(OpenAIModelRegistry.models.first)
        guard case .image(let caps) = model.entry.uiCapabilities else {
            Issue.record("expected image capabilities"); return
        }
        // 16:9 (1.78) is not 3:2 (1.50) — claiming it would trip the frame_ratio check at 2% tolerance.
        #expect(!caps.aspectRatios.contains("16:9"))
        #expect(Set(caps.aspectRatios) == Set(["1:1", "3:2", "2:3"]))
    }

    @Test("every advertised OpenAI ratio maps to a real size, and nothing else does")
    func openAISizeMappingIsTotal() throws {
        let model = try #require(OpenAIModelRegistry.models.first)
        guard case .image(let caps) = model.entry.uiCapabilities else {
            Issue.record("expected image capabilities"); return
        }
        for aspect in caps.aspectRatios {
            #expect(OpenAIModelRegistry.size(forAspect: aspect, model: model) != nil,
                    "advertised ratio must map to a size")
        }
        #expect(OpenAIModelRegistry.size(forAspect: "16:9", model: model) == nil)
    }

    @Test("both direct providers are honest key-field providers")
    func directProvidersAdvertiseDirectAPI() {
        #expect(GenerationProvider.google.supportsDirectAPI)
        #expect(GenerationProvider.openai.supportsDirectAPI)
        // Settings renders a key field off this — a shipped client backs both (no dead field).
        #expect(DirectImageDiscovery.providers == [.google, .openai])
    }

    @Test("the LLM sees provider-neutral logical ids")
    func logicalIdsAreProviderNeutral() {
        #expect(ModelCatalog.deriveLogicalId("openai/gpt-image-1") == "gpt-image-1")
        #expect(ModelCatalog.deriveLogicalId("fal-ai/imagen4") == "imagen4")
    }
}
