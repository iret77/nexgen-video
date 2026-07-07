import Foundation
import NexGenEngine

/// One installed `.ngvpack`'s state after the load gate ran — what the picker
/// shows and what the app registered. The app links only NexGenEngine's
/// `PackEntry`/`PackBox`; the pack's own module is never compiled in.
struct InstalledPluginRecord: Identifiable, Equatable {
    let id: String
    let displayName: String
    let tagline: String
    let version: String
    let minAppVersion: String
    let bundleURL: URL
    let state: State

    var isLoaded: Bool { state == .loaded }
    var incompatibility: PluginIncompatibility? {
        if case .incompatible(let reason) = state { return reason }
        return nil
    }

    enum State: Equatable {
        case loaded
        case incompatible(PluginIncompatibility)
    }
}

/// Loads installed format packs at startup, enforcing the hard gate order:
/// read Info.plist → id/version/entry well-formed → NGVMinAppVersion ≤ app
/// version → code signature (host Team ID, or ad-hoc when the host is unsigned)
/// → `Bundle.load()` → instantiate the principal `PackEntry` → register the pack.
/// An incompatible or unsigned pack yields a record with a reason — never a crash,
/// never a silent skip.
@MainActor
enum PluginLoader {
    /// The most recent scan, for the picker. Empty until `loadInstalled()` runs.
    private(set) static var installed: [InstalledPluginRecord] = []

    /// Scan the install directory and load every pack. Idempotent.
    @discardableResult
    static func loadInstalled(appVersion: String? = AppVersion.marketing) -> [InstalledPluginRecord] {
        let hostTeam = PluginSignature.hostTeamIdentifier()
        let records = PluginPaths.installedBundles().map {
            load(at: $0, appVersion: appVersion, hostTeam: hostTeam)
        }
        installed = records
        return records
    }

    /// Run the full gate for a single bundle and, on success, register its pack
    /// into `PackCatalog`. Returns the record either way. Also used by the
    /// installer to bring a freshly downloaded pack online without a relaunch.
    @discardableResult
    static func load(
        at bundleURL: URL,
        appVersion: String? = AppVersion.marketing,
        hostTeam: String? = PluginSignature.hostTeamIdentifier()
    ) -> InstalledPluginRecord {
        let fallbackID = bundleURL.deletingPathExtension().lastPathComponent

        guard let info = PluginBundleInfo(bundleURL: bundleURL) else {
            return blocked(id: fallbackID, bundleURL: bundleURL,
                           reason: .malformedMetadata("its Info.plist is missing or unreadable"))
        }

        if let reason = PluginGate.evaluate(info: info, appVersion: appVersion) {
            if case .malformedMetadata = reason {} else if appVersion == nil {
                Log.plugins.notice("app has no marketing version (dev build) — skipping version gate for \(info.id)")
            }
            return record(info, bundleURL: bundleURL, state: .incompatible(reason))
        }

        if let reason = PluginSignature.verify(bundleURL: bundleURL, hostTeam: hostTeam) {
            return record(info, bundleURL: bundleURL, state: .incompatible(reason))
        }

        guard let bundle = Bundle(url: bundleURL), bundle.load() else {
            return record(info, bundleURL: bundleURL,
                          state: .incompatible(.malformedMetadata("the pack's code failed to load")))
        }
        guard let entryClass = bundle.principalClass as? PackEntry.Type else {
            return record(info, bundleURL: bundleURL,
                          state: .incompatible(.malformedMetadata("entry point \(info.principalClass) not found")))
        }

        let pack = entryClass.init().makePack().pack
        if pack.name != info.id {
            Log.plugins.warning("pack id \"\(info.id)\" ≠ loaded pack name \"\(pack.name)\" — activating by \"\(pack.name)\"")
        }
        PackCatalog.register(pack)
        Log.plugins.notice("loaded pack \(pack.name) v\(info.version) from \(bundleURL.lastPathComponent)")
        return record(info, bundleURL: bundleURL, state: .loaded)
    }

    private static func record(
        _ info: PluginBundleInfo, bundleURL: URL, state: InstalledPluginRecord.State
    ) -> InstalledPluginRecord {
        if case .incompatible(let reason) = state {
            Log.plugins.warning("pack \(info.id) not loaded: \(reason.reason)")
        }
        return InstalledPluginRecord(
            id: info.id, displayName: info.displayName.isEmpty ? info.id : info.displayName,
            tagline: info.tagline, version: info.version, minAppVersion: info.minAppVersion,
            bundleURL: bundleURL, state: state)
    }

    private static func blocked(
        id: String, bundleURL: URL, reason: PluginIncompatibility
    ) -> InstalledPluginRecord {
        Log.plugins.warning("pack \(id) not loaded: \(reason.reason)")
        return InstalledPluginRecord(
            id: id, displayName: id, tagline: "", version: "", minAppVersion: "",
            bundleURL: bundleURL, state: .incompatible(reason))
    }
}
