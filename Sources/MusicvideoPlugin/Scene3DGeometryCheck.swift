import Foundation
import NexGenEngine

/// SCENE3D_POVS_UNRECORDED / SCENE3D_VIEW_WITHOUT_REVERSE / SCENE3D_SHEET_NOT_IN_POV_SET (#166).
///
/// The scene-geometry guarantee only holds while the views a shot uses actually come from the
/// location's one panorama. Nothing enforced that: `extract_scene3d_povs` cuts the set and hands back
/// its geometry, but recording it on the location is the agent's step — and a plan can name a sheet
/// that was never cut from the panorama at all, in which case the room silently stops agreeing with
/// itself across angles. Same shape as `builder_bypass`: audit what was recorded, don't trust that it
/// was. Warn-level — it reports lost consistency, it doesn't block.
extension MusicvideoChecks {
    public static let scene3dGeometryCheck: SanityCheck = { ctx in
        guard let bible = ctx.bible else { return [] }
        var out: [Finding] = []

        for location in bible.locations {
            let scene3d = location.scene3d
            let hasPanorama = !scene3d.panorama.trimmingCharacters(in: .whitespaces).isEmpty

            // A panorama with no recorded POV set: either nothing was cut yet (fine, and silent), or it
            // was cut and the geometry never made it back into the bible — in which case the reverse-shot
            // derivation has nothing to stand on and the set is just files on disk.
            if hasPanorama, scene3d.povs.isEmpty, !location.sheets.isEmpty {
                out.append(Finding(
                    level: .warn, code: "SCENE3D_POVS_UNRECORDED", shotId: nil,
                    message: "location '\(location.id)' has a scene3d panorama and \(location.sheets.count) "
                        + "sheet(s), but no recorded POV geometry. Record extract_scene3d_povs' `scene3d` "
                        + "block on the location — without it nothing can tell which sheets came from the "
                        + "panorama, and a reverse shot can't be derived."))
                continue
            }
            guard !scene3d.povs.isEmpty else { continue }

            // Every view needs an opposite, or a reverse angle of it has no geometry to stand on and the
            // model will invent the far wall — the exact failure this whole mechanism exists to prevent.
            let orphans = Scene3DCamera.viewsWithoutReverse(in: scene3d.specs)
            if !orphans.isEmpty {
                out.append(Finding(
                    level: .warn, code: "SCENE3D_VIEW_WITHOUT_REVERSE", shotId: nil,
                    message: "location '\(location.id)': \(orphans.joined(separator: ", ")) have no opposite "
                        + "view in the POV set, so a reverse angle on them can't be derived from the "
                        + "panorama — the model would invent the far wall. Cut the opposing POV(s) too "
                        + "(the four cardinal walls cover this by default)."))
            }

            // A sheet that isn't a POV name was not cut from this panorama. It may be a legitimate
            // hand-made view, so this is a warn — but it is outside the geometric guarantee and worth
            // knowing, because it is exactly where two shots of one room stop agreeing.
            let povNames = Set(scene3d.povs.map(\.name))
            let strays = location.sheets.keys.filter { !povNames.contains($0) }.sorted()
            if !strays.isEmpty {
                out.append(Finding(
                    level: .warn, code: "SCENE3D_SHEET_NOT_IN_POV_SET", shotId: nil,
                    message: "location '\(location.id)': sheet(s) \(strays.joined(separator: ", ")) are not "
                        + "in the POV set cut from its panorama, so they carry no guarantee of matching "
                        + "the room's geometry. Cut them as POVs, or accept that shots using them may "
                        + "disagree with the rest of the location."))
            }
        }
        return out
    }
}
