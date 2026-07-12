import Foundation
import NexGenEngine

/// Deterministic hard-gate preconditions for the musicvideo pack. These run (non-LLM) before a gate
/// can be approved, so the agent can never advance a phase whose real artifact is missing — the port
/// of the predecessor's analysis→render `require()` chain.
enum MusicvideoGateChecks {
    /// The `analysis` gate is approvable only when a real analysis artifact exists with genuine
    /// rhythm data — a non-empty `beats` AND `downbeats` list and a positive duration. This is what
    /// stops the agent from "hearing" a structure it never measured: no artifact, or an empty/degenerate
    /// one, blocks approval with an actionable message pointing at `run_phase("analysis")`.
    static func requireRealAnalysis(dataRoot: URL) throws {
        guard let url = AudioProjectLayout.expectedAnalysisArtifactURL(dataRoot: dataRoot) else {
            throw GateBlocked(
                "Can't approve \"analysis\": there isn't exactly one song in audio/ to analyse. "
                    + "Attach the track first, then run run_phase(\"analysis\").")
        }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw GateBlocked(
                "Can't approve \"analysis\": no analysis artifact yet. Run run_phase(\"analysis\") — it "
                    + "decodes the song and writes real beats/downbeats. Never describe the song's "
                    + "structure from listening; it must be measured.")
        }
        let beats = (obj["beats"] as? [Any])?.count ?? 0
        let downbeats = (obj["downbeats"] as? [Any])?.count ?? 0
        let duration = (obj["duration_s"] as? Double) ?? 0
        guard beats > 0, downbeats > 0, duration > 0 else {
            throw GateBlocked(
                "Can't approve \"analysis\": the analysis artifact has no real rhythm data "
                    + "(beats=\(beats), downbeats=\(downbeats), duration=\(duration)s). Re-run "
                    + "run_phase(\"analysis\") on a decodable song.")
        }
        // A2 gate: the DSP measures the grid, but the phase isn't done until A2 has INTERPRETED it —
        // the measured sections must be labeled. `interpretation.section_labels` is written by the A2
        // step (never the DSP), so requiring it forces A2 to actually run before the gate can close.
        let interpretation = obj["interpretation"] as? [String: Any]
        let sectionLabels = (interpretation?["section_labels"] as? [Any])?.count ?? 0
        guard sectionLabels > 0 else {
            throw GateBlocked(
                "Can't approve \"analysis\" yet: the measured sections aren't interpreted. Complete A2 — "
                    + "settle the tempo multiplier and write interpretation.section_labels (a label per "
                    + "measured section) — then approve. The DSP measures the grid; A2 names it.")
        }
    }

    // MARK: - Per-phase acceptance harness
    // Every phase's gate deterministically verifies the phase actually produced its artifact to the
    // plugin's spec — not decoration, an AI-agent harness. Most artifacts are hand-authored by the LLM
    // (no Swift writer), so "decodes against the real engine type" is itself a strong, load-bearing check.

    /// `brief`: a schema-valid brief.yaml (decode enforces the whole Brief contract, incl. budget and
    /// visual-medium-notes rules) plus a concrete target platform.
    static func requireRealBrief(dataRoot: URL) throws {
        let brief: Brief
        do {
            brief = try YAMLArtifactStore(dataRoot: dataRoot).load(Brief.self, at: PipelineLayout.briefFile)
        } catch {
            throw GateBlocked("Can't approve \"brief\": no valid brief.yaml yet (\(error)). Write the brief "
                + "with its required fields before approving.")
        }
        guard !brief.targetPlatform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GateBlocked("Can't approve \"brief\": target_platform is empty — set a concrete platform.")
        }
    }

    /// `shotlist`: a schema-valid, non-empty shotlist whose shots COVER the measured song. For
    /// beat/section modes the shots must reach the song's end and the shotlist's song duration must
    /// match the measured analysis — so a shot list can't be authored against a hallucinated length.
    static func requireRealShotlist(dataRoot: URL) throws {
        guard let shotlist = try? loadShotlist(dataRoot: dataRoot), !shotlist.shots.isEmpty else {
            throw GateBlocked("Can't approve \"shotlist\": no valid, non-empty shot list yet (it must decode "
                + "against the engine schema).")
        }
        guard ["beat", "section"].contains(shotlist.mode.rawValue) else { return }  // multicam/phrase: decode enforces coverage
        guard let measured = BeatAssembly.loadBeatGrid(dataRoot: dataRoot) else {
            throw GateBlocked("Can't approve \"shotlist\": the measured analysis is missing — approve "
                + "\"analysis\" first so shot timing can be checked against the real song.")
        }
        let tol = 0.5
        guard abs(shotlist.song.durationS - measured.durationS) <= tol else {
            throw GateBlocked("Can't approve \"shotlist\": its song duration (\(shotlist.song.durationS)s) "
                + "doesn't match the measured analysis (\(measured.durationS)s) — it was built against the "
                + "wrong length. Rebuild it from the measured song.")
        }
        let end = shotlist.shots.map(\.timeEnd).max() ?? 0
        guard end >= measured.durationS - tol else {
            throw GateBlocked("Can't approve \"shotlist\": shots stop at \(end)s but the song runs "
                + "\(measured.durationS)s — the tail is uncovered. Cover the whole track.")
        }
    }

    /// `bible`: a schema-valid bible (decode enforces global-unique ids + the per-entity anchor rule),
    /// at least one character/ensemble/location, and every reference image / sheet it lists must
    /// ACTUALLY exist on disk — the agent can't record art it never generated.
    static func requireRealBible(dataRoot: URL) throws {
        guard let bible = try? loadBible(dataRoot: dataRoot) else {
            throw GateBlocked("Can't approve \"bible\": no valid bible/bible.yaml yet (schema-valid, every "
                + "entity with at least one reference image or sheet).")
        }
        guard !bible.characters.isEmpty || !bible.ensembles.isEmpty || !bible.locations.isEmpty else {
            throw GateBlocked("Can't approve \"bible\": it defines no characters, ensembles, or locations.")
        }
        let bases = [dataRoot, FrameInventory.projectHome(of: dataRoot)]
        func exists(_ path: String) -> Bool {
            let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { return false }
            if FileManager.default.fileExists(atPath: p) { return true }
            return bases.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent(p).path) }
        }
        var claimed: [String] = []
        for c in bible.characters { claimed += c.referenceImages + Array(c.sheets.values) }
        for e in bible.ensembles { claimed += e.referenceImages + Array(e.sheets.values) }
        for l in bible.locations { claimed += l.referenceImages + Array(l.sheets.values) }
        let missing = claimed.filter { !exists($0) }
        guard missing.isEmpty else {
            throw GateBlocked("Can't approve \"bible\": \(missing.count) reference image(s)/sheet(s) it lists "
                + "don't exist on disk (e.g. \(missing.prefix(3).joined(separator: ", "))). Generate the "
                + "sheets first — the bible must not claim art it never produced.")
        }
    }
}
