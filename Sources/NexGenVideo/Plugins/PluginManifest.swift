import Foundation
import NexGenEngine

/// Metadata read from an installed `.ngvpack`'s `Contents/Info.plist` — the
/// values the load gate needs BEFORE any code is loaded.
struct PluginBundleInfo: Equatable {
    /// `NGVPackID` — the pack's activation id (also its filename stem).
    let id: String
    /// `NGVPackDisplayName` — gallery title.
    let displayName: String
    /// `NGVPackTagline` — gallery subtitle (may be empty).
    let tagline: String
    /// `NGVPackHeadline` — a bold one-line card pitch (may be empty → card uses tagline).
    let headline: String
    /// `NGVPackBenefit` — a short benefit line under the headline (may be empty).
    let benefit: String
    /// `CFBundleShortVersionString` — the pack's own version.
    let version: String
    /// `NGVMinAppVersion` — minimum NexGenVideo marketing version required.
    let minAppVersion: String
    /// `NGVEngineContract` — the host↔pack binary contract the pack was BUILT against, stamped by
    /// `assemble_ngvpack.sh`. `0` = absent or unparseable, i.e. a pack that predates the check.
    let engineContract: Int
    /// `NSPrincipalClass` — the `PackEntry` subclass the host instantiates.
    let principalClass: String

    /// Plist keys, kept in one place so assembly (release.yml) and reading agree.
    enum Key {
        static let id = "NGVPackID"
        static let displayName = "NGVPackDisplayName"
        static let tagline = "NGVPackTagline"
        static let headline = "NGVPackHeadline"
        static let benefit = "NGVPackBenefit"
        static let version = "CFBundleShortVersionString"
        static let minAppVersion = "NGVMinAppVersion"
        static let engineContract = "NGVEngineContract"
        static let principalClass = "NSPrincipalClass"
    }

    /// Pure decode from a plist dictionary — the unit-testable core.
    init(plist: [String: Any]) {
        id = (plist[Key.id] as? String) ?? ""
        displayName = (plist[Key.displayName] as? String) ?? ""
        tagline = (plist[Key.tagline] as? String) ?? ""
        headline = (plist[Key.headline] as? String) ?? ""
        benefit = (plist[Key.benefit] as? String) ?? ""
        version = (plist[Key.version] as? String) ?? ""
        minAppVersion = (plist[Key.minAppVersion] as? String) ?? ""
        // Only a genuine plist integer counts — a string ("2") or a missing key reads as 0 and is
        // refused, so an ambiguous stamp can never be mistaken for a matching contract.
        engineContract = (plist[Key.engineContract] as? NSNumber)?.intValue ?? 0
        principalClass = (plist[Key.principalClass] as? String) ?? ""
    }

    /// Read from a `.ngvpack` bundle URL's `Contents/Info.plist`. Nil when the
    /// plist is missing or unparseable (surfaced as damaged metadata upstream).
    init?(bundleURL: URL) {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any]
        else { return nil }
        self.init(plist: dict)
    }
}

/// Why a pack can't be activated — each carries a calm, user-facing reason the
/// picker shows instead of crashing or silently skipping the pack.
enum PluginIncompatibility: Equatable {
    /// Missing or malformed id / version / principal class.
    case malformedMetadata(String)
    /// `NGVMinAppVersion` is newer than the running app.
    case requiresAppVersion(String)
    /// Code signature missing, invalid, or not from the host's Team ID.
    case untrustedSignature(String)
    /// `NGVEngineContract` ≠ the running engine's. The pack's witness tables don't match what the
    /// host would dispatch through, so it is refused BEFORE any of its code is loaded.
    case requiresEngineContract(pack: Int, app: Int)

    var reason: String {
        switch self {
        case .malformedMetadata(let detail):
            return "Damaged pack — \(detail)."
        case .requiresAppVersion(let min):
            return "Requires NexGenVideo \(min) or newer."
        case .untrustedSignature(let detail):
            return "Signature check failed — \(detail)."
        case .requiresEngineContract:
            return "Built for a different version of NexGenVideo — update the pack."
        }
    }
}

/// The metadata + version half of the load gate (pure; the signature half is IO
/// in `PluginSignature`). Returns the blocking reason, or nil when the pack
/// clears these checks.
enum PluginGate {
    static func evaluate(info: PluginBundleInfo, appVersion: String?) -> PluginIncompatibility? {
        guard PluginPaths.isValidID(info.id) else {
            return .malformedMetadata("missing or invalid pack id")
        }
        guard SemanticVersion(info.version) != nil else {
            return .malformedMetadata("invalid pack version \"\(info.version)\"")
        }
        guard !info.principalClass.isEmpty else {
            return .malformedMetadata("no entry point declared")
        }
        // Version first: when the app is simply too old, "Requires NexGenVideo X" is the more
        // actionable reason than the contract mismatch that follows from it.
        if let reason = versionCheck(minAppVersion: info.minAppVersion, appVersion: appVersion) {
            return reason
        }
        return contractCheck(packContract: info.engineContract)
    }

    /// The binary-contract axis. A pack built against a different engine contract has no witness-table
    /// entry for requirements added since — dispatching into it jumps to a null address and kills the
    /// app. Refused on the plist alone, so nothing of the pack is ever loaded.
    static func contractCheck(packContract: Int, engine: Int = EngineContract.current) -> PluginIncompatibility? {
        guard packContract == engine else {
            return .requiresEngineContract(pack: packContract, app: engine)
        }
        return nil
    }

    /// The version axis alone — reused by the picker to decide whether a catalog
    /// entry (which carries no principal class yet) is installable on this build.
    static func versionCheck(minAppVersion: String, appVersion: String?) -> PluginIncompatibility? {
        guard let minVersion = SemanticVersion(minAppVersion) else {
            return .malformedMetadata("invalid minimum app version \"\(minAppVersion)\"")
        }
        // Dev / CI builds without a marketing version are always compatible
        // (logged by the caller) — a bare `swift run` still loads local packs.
        guard let appVersionString = appVersion, let app = SemanticVersion(appVersionString) else {
            return nil
        }
        guard app >= minVersion else {
            return .requiresAppVersion(minAppVersion)
        }
        return nil
    }
}
