import AppKit
import NexGenEngine

/// App-facing view of a native format pack — the successor to the former disk-discovered
/// plugin model. The gallery, title-bar chip, and agent launcher read packs from here (via
/// `PackCatalog`, NexGenEngine) instead of scanning disk. Activation is unchanged: exactly one
/// active per project, persisted in `ngv.json`.
struct InstalledPack: Identifiable, Equatable {
    /// The pack's `name` — the `activePlugin` string persisted per project.
    let name: String
    let displayName: String
    let tagline: String?
    /// Badge art inside the pack's own resource bundle (nil → gradient fallback).
    let badgeURL: URL?

    var id: String { name }

    init(_ pack: Pack) {
        self.name = pack.name
        self.displayName = pack.manifest.displayName
        self.tagline = pack.manifest.tagline.isEmpty ? nil : pack.manifest.tagline
        self.badgeURL = pack.manifest.badgeURL
    }

    /// Every first-party pack, gallery order.
    static var all: [InstalledPack] { PackCatalog.all.map(InstalledPack.init) }

    /// The pack whose `name` matches, or nil (generic workflow).
    static func named(_ name: String?) -> InstalledPack? {
        guard let name else { return nil }
        return all.first { $0.name == name }
    }

    /// The pack's badge, loaded from the pack's own resource bundle — self-contained,
    /// so a pack brings its art with it. nil → the gallery paints a gradient.
    func headerImage() -> NSImage? {
        badgeURL.flatMap { NSImage(contentsOf: $0) }
    }
}
