import CryptoKit
import Foundation

/// The mandatory prompt gate (Epic #98 / issue #100): every prompt bound for a content model
/// passes through here. User chat input — and the agent's own phrasing — is *intent*, never a raw
/// model prompt; NGV's value is that several cheap LLM turns prepare the input before one
/// expensive content render. This deterministic stage merges locked ledger directives, applies
/// per-model limits, and normalizes; translation and gap-resolution happen agent-side (per the
/// compile_prompt tool contract) BEFORE compiling. Raw sends exist only behind the pro toggle.
struct CompiledPrompt: Sendable {
    let text: String
    let token: String
    let notes: [String]
}

enum PromptCompiler {
    /// Settings → Providers "Raw prompts (pro)". Off by default — the gate is the default path.
    static let rawPromptsDefaultsKey = "allowRawPrompts"

    static var rawPromptsAllowed: Bool {
        UserDefaults.standard.bool(forKey: rawPromptsDefaultsKey)
    }

    /// Process-stable salt: a compileToken can only come from compile_prompt in this app run —
    /// the agent cannot fabricate one to sneak an uncompiled prompt past the gate.
    private static let salt = UUID().uuidString

    /// Per-model prompt length caps. Runway's promptText is hard-capped at 1000 chars (verified
    /// against their SDK); other providers get a generous but finite bound.
    static func lengthCap(modelId: String) -> Int {
        modelId.hasPrefix("runway/") ? 1000 : 2500
    }

    /// Deterministic compile: normalize, fold in locked ledger directives (non-negotiable,
    /// concept §5), enforce the model's length cap. The intent must already be English and
    /// contradiction-free — that is the agent's part of the contract.
    @MainActor
    static func compile(
        intent: String,
        modelId: String,
        editor: EditorViewModel?
    ) async throws -> CompiledPrompt {
        let trimmed = intent
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError("Empty intent — describe what to generate.")
        }

        var notes: [String] = []
        var text = trimmed

        if let editor, let dir = editor.studioProjectDir {
            if case .success(.some(let ledger)) = await CockpitDataService.ledger(projectDir: dir) {
                let locked = ledger.objects.values
                    .flatMap(\.values)
                    .filter(\.locked)
                    .map(\.directive)
                let missing = locked.filter { !text.localizedCaseInsensitiveContains($0) }
                if !missing.isEmpty {
                    let suffix = text.hasSuffix(".") ? " " : ". "
                    text += suffix + missing.joined(separator: ". ")
                    notes.append("merged \(missing.count) locked ledger directive(s)")
                }
            }
        }

        let cap = lengthCap(modelId: modelId)
        guard text.count <= cap else {
            throw ToolError(
                "Compiled prompt is \(text.count) characters — \(modelId) accepts at most \(cap). Tighten the intent.")
        }
        return CompiledPrompt(text: text, token: token(for: text, modelId: modelId), notes: notes)
    }

    static func token(for text: String, modelId: String) -> String {
        let digest = SHA256.hash(data: Data("\(salt)|\(modelId)|\(text)".utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func validate(token: String, text: String, modelId: String) -> Bool {
        token == self.token(for: text, modelId: modelId)
    }

    /// The gate itself, shared by every generate tool. `rawPrompt: true` is honored only when the
    /// pro toggle is on; otherwise the prompt must carry a valid compileToken for this model.
    static func enforceGate(args: [String: Any], prompt: String, modelId: String) throws {
        if args.bool("rawPrompt") == true {
            guard rawPromptsAllowed else {
                throw ToolError(
                    "Raw prompts are disabled. Compile via compile_prompt(intent, model) and pass "
                    + "compiledPrompt + compileToken — or the user can enable \u{201C}Raw prompts (pro)\u{201D} "
                    + "in Settings \u{2192} Providers.")
            }
            return
        }
        guard let token = args.string("compileToken"), validate(token: token, text: prompt, modelId: modelId) else {
            throw ToolError(
                "Uncompiled prompt. NGV never sends raw prompts to content models: call "
                + "compile_prompt(intent, model) first and pass its compiledPrompt and compileToken "
                + "here unchanged. If essential details are missing, ask the user BEFORE generating.")
        }
    }
}
