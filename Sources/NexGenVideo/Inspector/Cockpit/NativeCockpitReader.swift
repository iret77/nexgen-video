import Foundation
import NexGenEngine

// In-process replacement for the `nexgen_engine.read` subprocess, for the kinds the pure Swift
// engine can serve natively (no venv, no Python). Each function returns raw JSON bytes in the SAME
// shape the read CLI emits (engine/nexgen_engine/read.py), so the existing Cockpit panel decoders
// consume it unchanged. The remaining kinds keep the legacy subprocess path.
//
// Parity is proven in NexGenEngineTests: the `state` bytes here match the committed state.json golden.
enum NativeCockpitReader {

    /// True for the kinds served natively below. Everything else falls through to the Python CLI.
    static func servesNatively(_ kind: String) -> Bool {
        ["state", "phases", "contract", "router", "brief", "treatment"].contains(kind)
    }

    /// The project's data root (`<projectDir>/_studio` in the v2 layout, or the flat dir), or nil
    /// when `projectDir` is not a project yet — mirrors `read.py`'s `data_root_of` precheck.
    static func dataRoot(of projectDir: URL) -> URL? {
        DataRootResolver.dataRoot(of: projectDir)
    }

    enum NativeError: Error, Sendable, Equatable {
        case notInitialized
        case encode(String)
        case load(String)
    }

    // MARK: - Projectless kinds

    /// `read.py` "phases": the ordered core pipeline (JSON array of strings). Pack phases would append
    /// here; the pure engine has no pack discovery, so it's the core order.
    static func phasesJSON() throws -> Data {
        try serialize(coreGatePhases)
    }

    /// `read.py` "contract": `{surfaces:[...], phases:{phase:{surface, task_class}}}`.
    /// `core.ui_contract.full_contract()`.
    static func contractJSON(packEntries: [String: UIContract.Entry] = [:]) throws -> Data {
        let contract = UIContract.fullContract(packEntries: packEntries)
        var phases: [String: Any] = [:]
        for (phase, entry) in contract {
            phases[phase] = ["surface": entry.surface, "task_class": entry.taskClass]
        }
        return try serialize(["surfaces": UIContract.surfaces, "phases": phases])
    }

    /// `read.py` "router": `core.router.describe()` — `{tiers:{...}, task_classes:{name:{tier, effort}}}`.
    static func routerJSON(dataRoot: URL? = nil) throws -> Data {
        var taskClasses: [String: Any] = [:]
        for tc in ModelRouter.taskClasses {
            taskClasses[tc.name] = ["tier": tc.tier, "effort": tc.effort]
        }
        return try serialize(["tiers": ModelRouter.manifest(dataRoot: dataRoot), "task_classes": taskClasses])
    }

    // MARK: - Project kinds

    /// `read.py` "state": `mcp_server.project_state()` → `ProjectState.model_dump()` (snake_case, no
    /// aliasing). Phase order is the core order; pack phases would extend it.
    static func stateJSON(dataRoot: URL) throws -> Data {
        let snapshot: ProjectStateBuilder.ProjectState
        do {
            snapshot = try ProjectStateBuilder.buildSnapshot(dataRoot: dataRoot)
        } catch {
            throw NativeError.notInitialized
        }
        return try serialize(stateDictionary(snapshot))
    }

    /// The `ProjectState.model_dump()` dictionary shape — extracted so the parity test can build the
    /// same bytes the CLI/golden carry. Keys and gate-state raw strings match `state.py` exactly.
    static func stateDictionary(_ s: ProjectStateBuilder.ProjectState) -> [String: Any] {
        let phases: [[String: Any]] = s.phases.map { p in
            [
                "phase": p.phase,
                "approved": p.approved,
                "state": p.state.rawValue,
                "notes": p.notes.map { $0 as Any } ?? NSNull(),
            ]
        }
        return [
            "project": s.project,
            "mode": s.mode,
            "budget_eur": s.budgetEur,
            "budget_spent_eur": s.budgetSpentEur,
            "budget_remaining_eur": s.budgetRemainingEur,
            "phases": phases,
            "next_phase": s.nextPhase.map { $0 as Any } ?? NSNull(),
        ]
    }

    /// `read.py` "brief": the Brief loaded via the engine, re-encoded to the CLI's
    /// `model_dump(by_alias=True, mode="json")` shape (schema alias, snake_case). Literal `null` when
    /// no brief exists yet (mirrors read.py's `FileNotFoundError → None`).
    static func briefJSON(dataRoot: URL) throws -> Data {
        let store = YAMLArtifactStore(dataRoot: dataRoot)
        let brief: Brief
        do {
            brief = try store.load(Brief.self, at: StudioLayout.briefFile)
        } catch {
            // A missing brief.yaml is the not-yet-drafted state → literal null (like read.py).
            let url = StudioLayout.url(StudioLayout.briefFile, in: dataRoot)
            if !FileManager.default.fileExists(atPath: url.path) {
                return Data("null".utf8)
            }
            throw NativeError.load("brief")
        }
        // The engine Brief is JSON-encodable in the by-alias shape already (CodingKeys carry the
        // Python names); a standard encoder omits nil optionals, which the tolerant BriefData decoder
        // accepts. Emit sorted keys for stable output.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(brief)
    }

    /// `read.py` "treatment": `{meta:{...}, body_markdown:...}` — the latest treatment, or literal
    /// `null` when none exists (read.py's `glob("treatment/v*.md")` precheck).
    static func treatmentJSON(dataRoot: URL) throws -> Data {
        let treatment: Treatment
        do {
            treatment = try TreatmentStore.load(dataRoot: dataRoot)
        } catch {
            return Data("null".utf8)
        }
        // meta re-encoded via its Codable (by-alias CodingKeys), wrapped with body_markdown.
        let metaData = try JSONEncoder().encode(treatment.meta)
        let metaObject = try JSONSerialization.jsonObject(with: metaData)
        return try serialize(["meta": metaObject, "body_markdown": treatment.bodyMarkdown])
    }

    // MARK: - Serialization

    /// JSON bytes for a Foundation object graph. `.sortedKeys` for deterministic output; key SPELLING
    /// (not order) is what the decoders and goldens care about.
    static func serialize(_ object: Any) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        } catch {
            throw NativeError.encode(String(describing: error))
        }
    }
}
