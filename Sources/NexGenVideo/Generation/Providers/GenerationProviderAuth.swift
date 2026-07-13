import Foundation

/// How a provider's MCP server authenticates — grounded in each service's real, documented setup, so
/// Settings only ever offers a method the provider actually supports (no dead fields).
enum MCPAuthMethod: Equatable, Sendable {
    /// The provider's own API key is forwarded as the MCP bearer (fal, Runway) — no separate sign-in;
    /// the API key configured above unlocks the MCP transport too.
    case forwardsAPIKey
    /// OAuth sign-in against the provider's hosted MCP (Higgsfield, OpenArt) — a browser login, no
    /// pasted key. Handled by `ProviderOAuth`.
    case oauth
    /// A local MCP bridge the provider's desktop app exposes (ACE Studio on localhost) — no key, but
    /// the app must be running.
    case localApp
}

/// A provider's hosted MCP transport: the known endpoint (so the user never types a URL) + how it
/// authenticates. `nil` for a provider with no usable MCP server (Marble, ElevenLabs — API only).
struct MCPCapability: Equatable, Sendable {
    let defaultURL: URL
    let auth: MCPAuthMethod
    /// One-line, creative-facing explanation of what this transport is.
    let note: String
}

extension GenerationProvider {
    /// The provider's MCP capability, if it offers a usable MCP server. URLs are the services' real,
    /// documented endpoints — pre-filled so the user activates with one action, never URL-typing.
    var mcpCapability: MCPCapability? {
        switch self {
        case .fal:
            return MCPCapability(defaultURL: URL(string: "https://mcp.fal.ai/mcp")!,
                                 auth: .forwardsAPIKey,
                                 note: "Run fal models on your fal subscription via MCP — uses your API key.")
        case .runway:
            return MCPCapability(defaultURL: URL(string: "https://mcp.runwayml.com/mcp")!,
                                 auth: .forwardsAPIKey,
                                 note: "Runway over MCP — uses your API key.")
        case .higgsfield:
            return MCPCapability(defaultURL: URL(string: "https://mcp.higgsfield.ai/mcp")!,
                                 auth: .oauth,
                                 note: "30+ video/image models on your Higgsfield subscription — sign in, no key.")
        case .openart:
            return MCPCapability(defaultURL: URL(string: "https://mcp.openart.ai/mcp")!,
                                 auth: .oauth,
                                 note: "Image + video models on your OpenArt credits — sign in, no key.")
        case .ace:
            return MCPCapability(defaultURL: URL(string: "http://localhost:21572/mcp")!,
                                 auth: .localApp,
                                 note: "Singing-voice synthesis — requires the ACE Studio app running on this Mac.")
        case .elevenlabs, .marble:
            // API only — no hosted MCP server to offer (ElevenLabs' MCP is a local stdio tool; Marble
            // is REST-only). Showing an MCP field here would be a dead field.
            return nil
        }
    }
}
