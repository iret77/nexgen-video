import Foundation
import Testing
@testable import NexGenEngine
@testable import MusicvideoPlugin

/// #174: engine-pinned deterministic steps — packs declare load-bearing steps the engine runs itself,
/// so the agent can neither skip nor improvise them.
@Suite("Deterministic steps")
struct DeterministicStepTests {
    @Test("steps are filtered by phase and preserve registration order")
    func phaseFilteringAndOrder() {
        let reg = EngineRegistry()
        reg.registerDeterministicStep("a", phase: "analysis", summary: "") { _ in }
        reg.registerDeterministicStep("x", phase: "brief", summary: "") { _ in }
        reg.registerDeterministicStep("b", phase: "analysis", summary: "") { _ in }
        #expect(reg.deterministicSteps(forPhase: "analysis").map(\.id) == ["a", "b"])
        #expect(reg.deterministicSteps(forPhase: "brief").map(\.id) == ["x"])
        #expect(reg.deterministicSteps(forPhase: "shotlist").isEmpty)
    }

    struct StepError: Error, Equatable { let m: String }

    @Test("a step's throw propagates (the host turns it into an actionable block)")
    func throwPropagates() {
        let reg = EngineRegistry()
        reg.registerDeterministicStep("boom", phase: "analysis", summary: "") { _ in
            throw StepError(m: "nope")
        }
        let step = reg.deterministicSteps(forPhase: "analysis")[0]
        #expect(throws: StepError(m: "nope")) { try step.run(URL(fileURLWithPath: "/tmp")) }
    }

    // MARK: - The musicvideo one-song contract as a deterministic step

    private func tempProject() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("detstep-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("audio"), withIntermediateDirectories: true)
        return root
    }

    private func writeAudio(_ name: String, in root: URL) {
        try? Data("x".utf8).write(to: root.appendingPathComponent("audio").appendingPathComponent(name))
    }

    @Test("musicvideo pins one_song_contract to the analysis phase")
    func musicvideoRegistersContract() {
        let reg = EngineRegistry()
        MusicvideoPack().register(reg)
        #expect(reg.deterministicSteps(forPhase: "analysis").contains { $0.id == "one_song_contract" })
    }

    @Test("one_song_contract blocks on zero or multiple songs, passes on exactly one")
    func oneSongContractEnforced() throws {
        let reg = EngineRegistry()
        MusicvideoPack().register(reg)
        let step = try #require(reg.deterministicSteps(forPhase: "analysis").first { $0.id == "one_song_contract" })

        let empty = tempProject(); defer { try? FileManager.default.removeItem(at: empty) }
        #expect(throws: (any Error).self) { try step.run(empty) }

        let many = tempProject(); defer { try? FileManager.default.removeItem(at: many) }
        writeAudio("a.wav", in: many); writeAudio("b.wav", in: many)
        #expect(throws: (any Error).self) { try step.run(many) }

        let one = tempProject(); defer { try? FileManager.default.removeItem(at: one) }
        writeAudio("song.wav", in: one)
        #expect(throws: Never.self) { try step.run(one) }
    }
}
