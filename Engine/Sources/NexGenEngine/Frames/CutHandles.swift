import Foundation

/// Cut handles as CONTENT, not post-padding (#213).
///
/// A real edit needs material beyond the visible cut at every fade/crossfade — otherwise the blend has
/// nothing to work with and you can't nudge the cut a couple of frames. Film has it because the camera
/// ran longer; a generation model delivers exactly the seconds ordered. The rejected fixes are freeze
/// frames (`ffmpeg tpad` — two stills fading into each other is AI slop) and "render gross and hope"
/// (the model spreads the action across the whole clip, so nothing is trimmable).
///
/// Instead the model renders the handle as moving frames with an explicit temporal structure: a held
/// beat of micro-motion before the action, and a held pose after. The net duration is the timeline
/// in/out; the gross duration (net + handles) is what the model is asked for and what is billed. This
/// is deterministic — derived from the shot's planned transitions, never left to agent discipline.
public enum CutHandles {
    /// Seconds of overlap material rendered on a handled side. A held beat of micro-motion — long
    /// enough to blend a fade and to re-cut by a few frames, short enough not to dominate the order.
    public static let handleSeconds = 0.75

    /// The pre/post handle seconds for a shot. A side is handled when its planned transition needs one
    /// (`fade`/`crossfade`), or when `forceAll` is set (the global override — the user keeps every shot's
    /// options open at the cost of more billed seconds and looser model inference over the gross time).
    public static func handles(for shot: Shot, forceAll: Bool) -> (pre: Double, post: Double) {
        let pre = (forceAll || shot.transitionIn.needsHandle) ? handleSeconds : 0
        let post = (forceAll || shot.transitionOut.needsHandle) ? handleSeconds : 0
        return (pre, post)
    }

    /// Gross render duration: the net action plus whichever handles this shot carries. This is the
    /// duration ordered from the model and the duration billed — handles are content, so they cost.
    public static func grossDuration(for shot: Shot, forceAll: Bool) -> Double {
        let h = handles(for: shot, forceAll: forceAll)
        return shot.durationS + h.pre + h.post
    }

    /// The deterministic temporal instruction handed to the video prompt for a handled shot, so the
    /// model front-/back-loads held micro-motion instead of spreading the action across the gross time.
    /// nil when the shot carries no handle (a plain hard-cut shot renders its net action as before).
    /// Phrased the way a director calls it — "hold … then … and hold".
    public static func temporalStructure(for shot: Shot, forceAll: Bool) -> String? {
        let h = handles(for: shot, forceAll: forceAll)
        guard h.pre > 0 || h.post > 0 else { return nil }
        func secs(_ v: Double) -> String {
            v == v.rounded() ? String(Int(v)) : String(format: "%.2g", v)
        }
        var parts: [String] = []
        if h.pre > 0 {
            parts.append("Open with \(secs(h.pre))s of near-stillness — only micro-motion (breath, "
                + "hair, ambient drift), the subject settled before the action")
        }
        parts.append(h.pre > 0 || h.post > 0 ? "then the described action" : "the described action")
        if h.post > 0 {
            parts.append("and end holding the final pose for \(secs(h.post))s with only micro-motion")
        }
        return parts.joined(separator: ", ") + "."
    }
}
