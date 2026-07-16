import Foundation
import NexGenEngine

/// #231 — the consistency levers of #195/#196/#197 all end in JSON handed to the LLM, and until now
/// nothing compared the plan with the render. `next_render_shot` *offers* the reference plan and the
/// chain start frame; `render.md` *asks* the agent to pass them on; `compile_prompt`'s `shotId` is
/// optional and, when omitted, degrades silently to a free-intent compile (no camera projection, no
/// drift lint). This audits the result instead of trusting the request.
///
/// Same seam and same shape as `builderBypassCheck`: re-run the deterministic machinery at audit time
/// and compare it against what the manifests recorded. Every planner involved is pure, so the plan a
/// check reconstructs is the plan `next_render_shot` handed out. Degrades to no findings whenever the
/// data root, a manifest, or the recorded conditioning is absent — an un-rendered project is not a
/// violation, and entries written before the audit fields existed carry nil, not a false accusation.
extension MusicvideoChecks {
    /// PLAN_REFS_IGNORED / CHAIN_START_FRAME_IGNORED / SHOT_PROJECTION_MISSING.
    public static let planAdherenceCheck: SanityCheck = { ctx in
        guard let root = ctx.extra?["data_root"] else { return [] }
        let dataRoot = URL(fileURLWithPath: root)
        var out: [Finding] = []
        out.append(contentsOf: referenceAndChainAdherence(ctx, dataRoot: dataRoot))
        out.append(contentsOf: shotProjectionAdherence(ctx, dataRoot: dataRoot))
        return out
    }

    /// Every render-manifest phase present on disk. The phase is a free string the agent passes to
    /// `next_render_shot` (`videos_preview`, `videos_final`, …) — never a fixed set — and
    /// `loadRenderManifest` answers a missing file with an EMPTY manifest rather than an error, so
    /// naming a phase that doesn't exist would audit nothing and report success. Discover them instead.
    private static func renderPhases(dataRoot: URL) -> [String] {
        let dir = PipelineLayout.url(PipelineLayout.rendersDir, in: dataRoot)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { name in
            guard name.hasPrefix("manifest-"), name.hasSuffix(".json") else { return nil }
            return String(name.dropFirst("manifest-".count).dropLast(".json".count))
        }.sorted()
    }

    /// The two render-manifest halves: did the shot render with the planned references, and did a
    /// chained shot start on its predecessor's extracted last frame.
    private static func referenceAndChainAdherence(_ ctx: AuditContext, dataRoot: URL) -> [Finding] {
        renderPhases(dataRoot: dataRoot).flatMap { phase -> [Finding] in
            guard let manifest = try? loadRenderManifest(dataRoot: dataRoot, phase: phase) else { return [] }
            return adherence(ctx, dataRoot: dataRoot, manifest: manifest)
        }
    }

    private static func adherence(
        _ ctx: AuditContext, dataRoot: URL, manifest: RenderManifest
    ) -> [Finding] {
        let planner = MusicvideoReferencePlanProvider()
        var out: [Finding] = []

        for shot in ctx.shotlist.shots {
            guard let entry = manifest.entries[shot.id], entry.status == .rendered else { continue }

            // A render recorded before the conditioning fields existed (or one whose output asset
            // couldn't be resolved) carries no actuals — unknown, not violated.
            if let recorded = entry.referencePaths,
               let plan = planner.planReferences(dataRoot: dataRoot, shotId: shot.id), !plan.refs.isEmpty {
                let planned = plan.refs.map(\.path)
                let missing = planned.filter { p in !recorded.contains { $0.hasSuffix(p) || p.hasSuffix($0) } }
                if !missing.isEmpty {
                    out.append(Finding(
                        level: .warn, code: "PLAN_REFS_IGNORED", shotId: shot.id,
                        message: "shot \(shot.id) rendered with \(recorded.count) image reference(s), but the "
                            + "reference planner had offered \(planned.count) — \(missing.count) planned ref(s) "
                            + "never reached the render: \(missing.joined(separator: ", ")). The shot lost the "
                            + "identity anchors and bible sheets that keep it on-model. Re-render it with "
                            + "next_render_shot's reference_images passed as referenceImageMediaRefs."))
                }
            }

            // #196: a chained shot must start on its predecessor's extracted last frame. Only auditable
            // once that frame exists — before then the successor legitimately couldn't have used it.
            guard shot.chainWithPreviousEnd,
                  let predId = ChainContinuity.chainPredecessor(ctx.shotlist, shotId: shot.id),
                  let expected = manifest.entries[predId]?.lastFramePath,
                  let actual = entry.startFramePath else { continue }
            if !(actual.hasSuffix(expected) || expected.hasSuffix(actual)) {
                out.append(Finding(
                    level: .warn, code: "CHAIN_START_FRAME_IGNORED", shotId: shot.id,
                    message: "shot \(shot.id) declares chain_with_previous_end but started on '\(actual)' "
                        + "instead of \(predId)'s extracted last frame '\(expected)'. The cut between them "
                        + "will jump — anchor-and-extend only holds when the successor starts on the exact "
                        + "frame the predecessor ended on. Re-render it with next_render_shot's "
                        + "chain_start_frame_media_ref as startFrameMediaRef."))
            }
        }
        return out
    }

    /// The `compile_prompt(shotId:)` half: a shot compiled without its id degrades silently to a
    /// free-intent compile — `PromptComposer` then leaves `payload.camera` empty and skips the drift
    /// lint. The frames manifest records the exact provider prompt, so the degradation is visible after
    /// the fact: the builder puts the shot's camera prose through `SlopStripper.strip` verbatim, so
    /// re-running that same pure transform reproduces exactly what a projected compile would have
    /// emitted. Absent from the prompt ⇒ the projection never ran.
    private static func shotProjectionAdherence(_ ctx: AuditContext, dataRoot: URL) -> [Finding] {
        guard let manifest = try? loadFramesManifest(dataRoot: dataRoot) else { return [] }
        let camera = Dictionary(
            uniqueKeysWithValues: ctx.shotlist.shots.compactMap { shot -> (String, String)? in
                guard let prose = shot.cameraSetup?.promptProse() else { return nil }
                let stripped = SlopStripper.strip(prose)
                return stripped.isEmpty ? nil : (shot.id, stripped)
            })
        var out: [Finding] = []
        for sf in manifest.shots {
            guard let expected = camera[sf.shotId] else { continue }
            for frame in sf.frames {
                let prompt = frame.providerPrompt
                // An empty provider prompt is builder_bypass's finding, not this one — don't double-report.
                guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty,
                      !prompt.contains(expected) else { continue }
                out.append(Finding(
                    level: .warn, code: "SHOT_PROJECTION_MISSING", shotId: sf.shotId,
                    message: "frame \(sf.shotId)-\(frame.role) was compiled without shotId: its provider "
                        + "prompt carries none of the shot's declared camera (\"\(expected)\"), so "
                        + "compile_prompt degraded to a free-intent compile — the camera came from the "
                        + "agent's phrasing, not the shot spec, and the drift linter never ran. "
                        + "Recompile with compile_prompt(intent, model, shotId: \"\(sf.shotId)\")."))
            }
        }
        return out
    }
}
