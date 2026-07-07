import Foundation

/// Where installed `.ngvpack` bundles live and how their filenames map to pack
/// ids. One directory under Application Support; each pack is `<id>.ngvpack`.
enum PluginPaths {
    static let bundleExtension = "ngvpack"

    /// `~/Library/Application Support/NexGenVideo/Plugins`. Created on demand.
    static var installDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("NexGenVideo", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    /// The install location for a pack id — `<installDirectory>/<id>.ngvpack`.
    /// Ids are constrained (see `isValidID`) so they can never escape the dir.
    static func installURL(id: String) -> URL {
        installDirectory.appendingPathComponent(id).appendingPathExtension(bundleExtension)
    }

    /// Every installed `.ngvpack`, sorted by name. Empty (never throws) when the
    /// directory is absent — a fresh install with no packs is a calm empty state.
    static func installedBundles() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: installDirectory, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.pathExtension == bundleExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A pack id safe to use as a path component: lowercase alphanumerics, `-`,
    /// `_`; non-empty; no separators or dots. Guards the catalog against a
    /// malicious `id` traversing out of the install directory.
    static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
