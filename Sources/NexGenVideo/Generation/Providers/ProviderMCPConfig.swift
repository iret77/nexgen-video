import Foundation

/// A provider's `.mcp` transport connection the user configured (Settings → Providers, MCP mode):
/// the server endpoint in UserDefaults, an optional subscription/OAuth bearer token in the Keychain.
/// Presence of an endpoint ACTIVATES the provider's `.mcp` transport — parallel to how an API key
/// activates `.api`. A provider may have both (API pay-per-call AND an MCP subscription); the
/// resolver then weighs them by billing.
enum ProviderMCP {
    private static func endpointKey(_ p: GenerationProvider) -> String { "provider.\(p.rawValue).mcp-endpoint" }
    private static func tokenAccount(_ p: GenerationProvider) -> String { "provider.\(p.rawValue).mcp-token" }

    static func endpoint(_ p: GenerationProvider) -> URL? {
        guard let s = UserDefaults.standard.string(forKey: endpointKey(p)), let u = URL(string: s) else { return nil }
        return u
    }

    static func hasConfig(_ p: GenerationProvider) -> Bool { endpoint(p) != nil }

    static func token(_ p: GenerationProvider) -> String? { KeychainStore.load(account: tokenAccount(p)) }

    static func setEndpoint(_ url: String?, for p: GenerationProvider) {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: endpointKey(p))
        } else {
            UserDefaults.standard.removeObject(forKey: endpointKey(p))
        }
        NotificationCenter.default.post(name: .providerKeysChanged, object: nil)
    }

    static func setToken(_ token: String?, for p: GenerationProvider) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainStore.save(trimmed, account: tokenAccount(p))
        } else {
            KeychainStore.delete(account: tokenAccount(p))
        }
    }

    /// An NGV-as-client for this provider's configured MCP, or nil when unconfigured.
    static func client(for p: GenerationProvider) -> MCPProviderClient? {
        guard let endpoint = endpoint(p) else { return nil }
        return MCPProviderClient(config: .init(endpoint: endpoint, bearerToken: token(p)))
    }
}
