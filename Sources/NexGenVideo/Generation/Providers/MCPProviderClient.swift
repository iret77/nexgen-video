import Foundation
import MCP

/// NGV as an MCP **client** to a provider's own MCP server (OpenArt, Runway, Higgsfield, ACE, …).
/// This is the `.mcp` transport of the provider layer: the LLM never touches the raw endpoint —
/// NGV connects, and the generation path calls the provider's tool with an ALREADY-COMPILED prompt
/// (the prompt-engine gate runs upstream in `GenerationController`, exactly like the `.api` transport).
/// Distinct from the embedded Claude runtime's external-MCP config: there Claude is the client; here
/// NGV is, so the gate and the resolver stay in force.
actor MCPProviderClient {
    struct Config: Sendable, Equatable {
        /// Hosted server URL (e.g. https://mcp.openart.ai/mcp). stdio/local support lands with ACE.
        let endpoint: URL
        /// Optional bearer token for the provider's subscription/OAuth session.
        let bearerToken: String?

        init(endpoint: URL, bearerToken: String? = nil) {
            self.endpoint = endpoint
            self.bearerToken = bearerToken
        }
    }

    enum ClientError: Error, Sendable {
        case notConnected
        case toolFailed(String)
    }

    private let config: Config
    private var client: Client?

    init(config: Config) { self.config = config }

    private func connectedClient() async throws -> Client {
        if let client { return client }
        let client = Client(name: "nexgen", version: "1.0.0")
        let transport = HTTPClientTransport(endpoint: config.endpoint)
        try await client.connect(transport: transport)
        self.client = client
        return client
    }

    /// Call a provider tool with a pre-compiled argument set and return its textual contents
    /// (result URLs / payload the host then imports onto the timeline). Arguments are already
    /// gate-compiled by the caller.
    func callTool(name: String, arguments: [String: Value]) async throws -> [String] {
        let client = try await connectedClient()
        let result = try await client.callTool(name: name, arguments: arguments)
        if result.isError == true {
            throw ClientError.toolFailed(Self.joinedText(result.content))
        }
        return Self.textContents(result.content)
    }

    func disconnect() async {
        await client?.disconnect()
        client = nil
    }

    private static func textContents(_ content: [Tool.Content]) -> [String] {
        content.compactMap { part in
            if case let .text(text) = part { return text }
            return nil
        }
    }

    private static func joinedText(_ content: [Tool.Content]) -> String {
        let text = textContents(content).joined(separator: " ")
        return text.isEmpty ? "provider tool reported an error" : text
    }
}
