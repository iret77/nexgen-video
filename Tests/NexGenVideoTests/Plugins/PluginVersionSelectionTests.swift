import Foundation
import Testing
@testable import NexGenVideo

/// #168: compatibility-based selection over a multi-version catalog — per pack id, pick the newest
/// version whose `minAppVersion ≤ app version`, so a new app gets the newest pack and an old app the
/// last pack that still supports it. Older versions stay published for older-app safety.
@Suite("Plugin version selection")
struct PluginVersionSelectionTests {
    private func entry(id: String, version: String, minApp: String) -> PluginCatalog.Entry {
        PluginCatalog.Entry(
            id: id, displayName: id, tagline: "", headline: nil, benefit: nil,
            version: version, minAppVersion: minApp,
            url: URL(string: "https://ex.com/\(id)-\(version).zip")!, sha256: "x", badge: nil)
    }

    private func pick(_ catalog: [PluginCatalog.Entry], app: String?) -> [String: String] {
        var out: [String: String] = [:]
        for e in PluginManager.selectCompatiblePerPack(catalog, appVersion: app) { out[e.id] = e.version }
        return out
    }

    @Test("newest compatible version wins per pack")
    func newestCompatible() {
        let catalog = [
            entry(id: "mv", version: "1.0.0", minApp: "0.1.0"),
            entry(id: "mv", version: "1.2.0", minApp: "0.1.0"),
            entry(id: "mv", version: "1.1.0", minApp: "0.1.0"),
        ]
        #expect(pick(catalog, app: "0.5.0") == ["mv": "1.2.0"])
    }

    @Test("a newer pack that needs a newer app is skipped for the last compatible one")
    func skipsIncompatibleNewer() {
        let catalog = [
            entry(id: "mv", version: "1.0.0", minApp: "0.1.0"),
            entry(id: "mv", version: "2.0.0", minApp: "0.9.0"),  // needs a newer app
        ]
        // Old app → last compatible (1.0.0); new app → newest (2.0.0).
        #expect(pick(catalog, app: "0.5.0") == ["mv": "1.0.0"])
        #expect(pick(catalog, app: "0.9.0") == ["mv": "2.0.0"])
    }

    @Test("when nothing is compatible, the newest overall is kept (shown as unavailable)")
    func allIncompatibleKeepsNewest() {
        let catalog = [
            entry(id: "mv", version: "2.0.0", minApp: "0.9.0"),
            entry(id: "mv", version: "2.1.0", minApp: "1.0.0"),
        ]
        #expect(pick(catalog, app: "0.5.0") == ["mv": "2.1.0"])
        // And it renders unavailable, not available.
        let selected = PluginManager.selectCompatiblePerPack(catalog, appVersion: "0.5.0")
        if case .unavailable = PluginManager.catalogStatus(entry: selected[0], appVersion: "0.5.0") {} else {
            Issue.record("expected unavailable status for an incompatible pack")
        }
    }

    @Test("independent packs are selected independently")
    func multiplePacks() {
        let catalog = [
            entry(id: "mv", version: "1.0.0", minApp: "0.1.0"),
            entry(id: "mv", version: "1.1.0", minApp: "0.1.0"),
            entry(id: "doc", version: "3.0.0", minApp: "0.1.0"),
        ]
        #expect(pick(catalog, app: "0.5.0") == ["mv": "1.1.0", "doc": "3.0.0"])
    }
}
