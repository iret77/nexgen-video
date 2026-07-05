import Foundation
import Testing

@testable import NexGenVideo

@Suite("PromptCompiler")
@MainActor
struct PromptCompilerTests {

    @Test func compileNormalizesWhitespaceAndReturnsValidToken() async throws {
        let compiled = try await PromptCompiler.compile(
            intent: "  an elephant\n\n on   a beach  ", modelId: "fal-ai/veo3", editor: nil)
        #expect(compiled.text == "an elephant on a beach")
        #expect(PromptCompiler.validate(token: compiled.token, text: compiled.text, modelId: "fal-ai/veo3"))
    }

    @Test func emptyIntentThrows() async {
        await #expect(throws: ToolError.self) {
            _ = try await PromptCompiler.compile(intent: "   \n ", modelId: "fal-ai/veo3", editor: nil)
        }
    }

    @Test func runwayLengthCapIsEnforced() async {
        let long = String(repeating: "a very long cinematic description ", count: 40) // > 1000 chars
        await #expect(throws: ToolError.self) {
            _ = try await PromptCompiler.compile(intent: long, modelId: "runway/gen4.5", editor: nil)
        }
    }

    @Test func tokenIsBoundToModelAndText() async throws {
        let compiled = try await PromptCompiler.compile(
            intent: "a red car", modelId: "fal-ai/veo3", editor: nil)
        // Different model → invalid; different text → invalid.
        #expect(!PromptCompiler.validate(token: compiled.token, text: compiled.text, modelId: "runway/gen4.5"))
        #expect(!PromptCompiler.validate(token: compiled.token, text: compiled.text + "!", modelId: "fal-ai/veo3"))
    }

    @Test func gateRejectsUncompiledAndFabricatedTokens() async throws {
        // No token at all.
        #expect(throws: ToolError.self) {
            try PromptCompiler.enforceGate(args: ["prompt": "raw"], prompt: "raw", modelId: "fal-ai/veo3")
        }
        // Fabricated token.
        #expect(throws: ToolError.self) {
            try PromptCompiler.enforceGate(
                args: ["compileToken": "deadbeefdeadbeef"], prompt: "raw", modelId: "fal-ai/veo3")
        }
        // A genuine compile passes.
        let compiled = try await PromptCompiler.compile(intent: "a red car", modelId: "fal-ai/veo3", editor: nil)
        try PromptCompiler.enforceGate(
            args: ["compileToken": compiled.token], prompt: compiled.text, modelId: "fal-ai/veo3")
    }

    @Test func rawPromptRequiresProSetting() {
        let key = PromptCompiler.rawPromptsDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(false, forKey: key)
        #expect(throws: ToolError.self) {
            try PromptCompiler.enforceGate(args: ["rawPrompt": true], prompt: "raw", modelId: "fal-ai/veo3")
        }

        UserDefaults.standard.set(true, forKey: key)
        #expect(throws: Never.self) {
            try PromptCompiler.enforceGate(args: ["rawPrompt": true], prompt: "raw", modelId: "fal-ai/veo3")
        }
    }
}
