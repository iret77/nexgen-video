import Foundation

/// Deriving a shot's camera from the location's 3D reference (#166) — the half of scene-geometry
/// consistency that isn't pixels.
///
/// `PovSpec` says where each view looks; this says how those views RELATE, so a plan can derive the
/// right one instead of the agent guessing. The load-bearing relation is the reverse shot: two views
/// oppose when their HEADINGS are 180° apart.
///
/// That is a yaw relation, deliberately — not a negated direction vector. The default POVs are tilted
/// 5° down, and a camera turned around is still tilted 5° DOWN, not up: `back` is therefore *not*
/// `−front` as a vector. The original port asserted exactly that vector identity and passed only
/// because its cameras were accidentally level; fixing the tilt (#218) is what exposed it. Comparing
/// headings is the relation that actually holds, at any tilt.
public enum Scene3DCamera {
    /// Shortest signed angular difference from `a` to `b`, in (−180, 180]. Handles the wrap that makes
    /// −170° and 170° neighbours (20° apart), not opposites.
    public static func yawDelta(from a: Double, to b: Double) -> Double {
        var delta = (b - a).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// Do these two views look opposite ways? True when their headings are 180° apart within
    /// `toleranceDegrees`. Tilt is ignored on purpose: it does not flip when a camera turns around.
    public static func areReverses(
        _ a: PovSpec, _ b: PovSpec, toleranceDegrees: Double = 1
    ) -> Bool {
        abs(abs(yawDelta(from: a.yawDegrees, to: b.yawDegrees)) - 180) <= toleranceDegrees
    }

    /// The view that looks the opposite way from `name` — the reverse shot's view. nil when the set
    /// has no opposite, which is a real answer: the reverse shot has no geometry to stand on and must
    /// not be invented.
    public static func reverse(
        of name: String, in povs: [PovSpec], toleranceDegrees: Double = 1
    ) -> PovSpec? {
        guard let source = povs.first(where: { $0.name == name }) else { return nil }
        return povs.first { $0.name != name && areReverses(source, $0, toleranceDegrees: toleranceDegrees) }
    }

    /// The view whose heading is closest to `yaw`. nil only for an empty set. Deterministic on ties:
    /// the earliest POV in the set wins, so the same plan always derives the same view.
    public static func nearest(toYaw yaw: Double, in povs: [PovSpec]) -> PovSpec? {
        povs.min { lhs, rhs in
            let l = abs(yawDelta(from: yaw, to: lhs.yawDegrees))
            let r = abs(yawDelta(from: yaw, to: rhs.yawDegrees))
            // `min(by:)` keeps the first element on a tie only if the predicate is strict.
            return l < r
        }
    }

    /// The views in this set that have NO opposite in it. A location cut only to `front` and `right`
    /// can never cover a reverse angle of either — worth saying before a shot asks for one, not after
    /// the model has invented a wall.
    public static func viewsWithoutReverse(
        in povs: [PovSpec], toleranceDegrees: Double = 1
    ) -> [String] {
        povs.filter { pov in
            !povs.contains { $0.name != pov.name && areReverses(pov, $0, toleranceDegrees: toleranceDegrees) }
        }.map(\.name)
    }
}
