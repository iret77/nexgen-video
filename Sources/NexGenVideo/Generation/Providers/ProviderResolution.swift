import Foundation

/// LLM → NGV → Provider → Model.
///
/// The LLM never picks or calls a provider. It asks NGV for a *capability* — a logical
/// model to generate, OR a workflow tool-call — and NGV resolves the concrete
/// (provider, transport) here. Providers expose BOTH kinds over API and/or MCP (fal,
/// Runway, Higgsfield, OpenArt, … all offer both transports). The prompt-engine gate
/// fires only for `.generation` (a creative prompt to a content model); `.tool` calls are
/// NGV-mediated but ungated unless they themselves send such a prompt. This is the pure,
/// testable spine of that resolution — it replaces the hardcoded 1:1 model-id-prefix
/// ladder in `GenerationProvider.servicing` / `GenerationService.runJob`.

/// How NGV reaches a provider. Never a raw LLM tool: for `.mcp`, NGV is the MCP *client*
/// (behind the prompt-engine gate), on the user's subscription/OAuth.
enum ProviderTransport: String, Sendable, Codable, CaseIterable, Hashable {
    case api   // direct REST on the user's own API key
    case mcp   // NGV-as-MCP-client to the provider's server
}

/// Billing reality of a transport — decisive for "cheapest": a flat subscription (`.mcp`)
/// can beat pay-per-use (`.api`) at the same raw rate, and often the reverse. NGV weighs
/// this, not just the sticker price.
enum BillingMode: String, Sendable, Codable, Hashable {
    case perCall        // separate account, charged per generation (typical API)
    case subscription   // flat / already paid (typical MCP)
}

/// What a binding fulfills. Both go LLM → NGV → Provider; only `.generation` (a creative
/// prompt to a content model) passes the prompt-engine gate. `.tool` is a workflow
/// operation — upscale/relight/inpaint, background-removal, roto, reference upload,
/// character lookup, project ops, any provider-specific tool — NGV-mediated but ungated
/// unless it itself sends a creative prompt to a content model.
enum ProviderCapabilityKind: String, Sendable, Codable, Hashable {
    case generation
    case tool
}

/// One concrete way to fulfil a capability: a (provider, transport) with the provider's
/// own reference and its billing mode. A provider may offer the same capability over both
/// transports (API pay-per-call and MCP subscription) — the resolver weighs both.
struct ProviderBinding: Sendable, Hashable {
    let provider: GenerationProvider
    let transport: ProviderTransport
    let kind: ProviderCapabilityKind
    /// The provider's own reference: a model/endpoint id for `.generation`, a tool name for `.tool`.
    let providerRef: String
    let billing: BillingMode
}

/// What the user has actually turned on — per (provider, transport). A provider can be
/// active over one transport but not the other (API key present, MCP not connected, …).
struct ProviderActivation: Sendable {
    struct Key: Hashable, Sendable {
        let provider: GenerationProvider
        let transport: ProviderTransport
    }
    let active: Set<Key>

    init(active: Set<Key> = []) { self.active = active }

    func isActive(_ provider: GenerationProvider, _ transport: ProviderTransport) -> Bool {
        active.contains(Key(provider: provider, transport: transport))
    }
}

enum ProviderResolver {
    /// Pick the cheapest ACTIVATED way to fulfil a capability (a logical model to generate,
    /// or a workflow tool-call).
    ///
    /// `bindings` are all the ways it can be fulfilled; `activation` is what the user turned
    /// on; `effectiveCost` returns the billing-aware cost of THIS call for a binding (a
    /// subscription transport typically reports a low/flat marginal cost). Returns `nil`
    /// when no activated provider offers it — in which case the catalog must not have
    /// offered it to the LLM in the first place (usable-only rule).
    static func resolve(
        bindings: [ProviderBinding],
        activation: ProviderActivation,
        effectiveCost: (ProviderBinding) -> Double
    ) -> ProviderBinding? {
        bindings
            .filter { activation.isActive($0.provider, $0.transport) }
            .min { effectiveCost($0) < effectiveCost($1) }
    }
}
