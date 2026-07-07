import Foundation
import NexGenEngine

/// Accessor over the musicvideo pack's bundled knowledge — the pattern YAMLs
/// (`Resources/MusicvideoPack/library/`) and the neutralized phase docs
/// (`Resources/MusicvideoPack/phases/`).
///
/// The pack ships these as `MusicvideoPlugin` target resources. At runtime they
/// resolve either from SwiftPM's generated `NexGenVideo_MusicvideoPlugin.bundle`
/// (dev/test/CI), or from the installed `.ngvpack` this dylib was loaded out of —
/// where assembly copies that same generated bundle into `Contents/Resources/`.
/// Both are found below; nothing is read from an absolute disk path.
public enum PackKnowledge {
    private final class BundleFinder {}

    /// A bundle actually contains the pack's resources iff `MusicvideoPack/` sits
    /// under its resource dir.
    private static func carriesPack(_ bundle: Bundle) -> Bool {
        guard let root = bundle.resourceURL else { return false }
        return FileManager.default.fileExists(
            atPath: root.appendingPathComponent("MusicvideoPack").path)
    }

    /// SwiftPM's generated `Bundle.module` accessor fatalErrors when the resource
    /// bundle isn't where it expects — a hard SIGTRAP. This resolver searches the
    /// known locations and returns nil instead of trapping.
    static let resourceBundle: Bundle? = {
        let name = "NexGenVideo_MusicvideoPlugin"
        let selfBundle = Bundle(for: BundleFinder.self)
        // The plugin bundle itself, when its resources are flattened in place
        // (a `.ngvpack` whose Contents/Resources holds MusicvideoPack/ directly).
        if carriesPack(selfBundle) { return selfBundle }
        // Otherwise the generated resource bundle sits next to the dylib / test
        // bundle (SwiftPM) or inside the `.ngvpack`'s Contents/Resources.
        let bases: [URL?] = [
            selfBundle.resourceURL,
            selfBundle.bundleURL.deletingLastPathComponent(),
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ]
        for base in bases {
            guard let url = base?.appendingPathComponent("\(name).bundle"),
                  let bundle = Bundle(url: url) else { continue }
            return bundle
        }
        return nil
    }()
    /// URLs of every pattern-library YAML bundled with the pack. Port of
    /// `patterns_schema.py::patterns_dir` + the `*.yaml` glob in
    /// `load_all_patterns` — Swift has no on-disk package directory to list,
    /// so this enumerates `Bundle.module`'s resource URLs instead.
    public static func patternLibraryURLs() -> [URL] {
        guard let dir = Self.resourceBundle?.resourceURL?.appendingPathComponent("MusicvideoPack/library") else { return [] }
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.pathExtension == "yaml" }
    }

    public enum PhaseDocError: Swift.Error, Sendable {
        case notFound(String)
    }

    /// Loads a neutralized phase doc's markdown text by base name (e.g.
    /// `"analysis"` -> `phases/analysis.md`).
    public static func phaseDoc(name: String) throws -> String {
        guard let url = Self.resourceBundle?.url(forResource: name, withExtension: "md", subdirectory: "MusicvideoPack/phases")
        else {
            throw PhaseDocError.notFound(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The pack's badge art (`MusicvideoPack/badge.png`) — the self-contained gallery visual.
    public static func badgeURL() -> URL? {
        Self.resourceBundle?.url(forResource: "badge", withExtension: "png", subdirectory: "MusicvideoPack")
    }

    /// Base names of every bundled phase doc, sorted.
    public static func phaseDocNames() -> [String] {
        guard let dir = Self.resourceBundle?.resourceURL?.appendingPathComponent("MusicvideoPack/phases") else { return [] }
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.pathExtension == "md" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }
}
