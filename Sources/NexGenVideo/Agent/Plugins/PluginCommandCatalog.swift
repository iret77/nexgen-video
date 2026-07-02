import Foundation

// Read-only catalog of installed plugins and their entry-point slash-commands, built for the launcher
// UI so a user can discover and start a workflow without knowing the slash-command syntax.
//
// Grounded in `PluginManager.discoverPlugins()`: each plugin dir is `<name>/plugin/` with a
// `.claude-plugin/plugin.json` (name, description) and `commands/*.md` files. A command file
// `commands/<stem>.md` maps to the slash-command `/<pluginName>:<stem>`. Its YAML frontmatter (the
// leading `---`…`---` block) carries `description:` and often `argument-hint:`.
//
// Everything degrades gracefully: an unreadable manifest, missing frontmatter, or a plugin with no
// commands all just yield sparser entries, never an error. Frontmatter is line-scanned (no YAML dep).
enum PluginCommandCatalog {

    struct PluginInfo: Identifiable, Equatable {
        var id: String { name }
        /// Plugin folder name — the `<pluginName>` half of `/<pluginName>:<stem>`.
        let name: String
        /// `description` from `plugin.json`, if present.
        let description: String?
        let commands: [PluginCommand]
    }

    struct PluginCommand: Identifiable, Equatable {
        var id: String { command }
        /// The runnable slash-command, e.g. `/musicvideo:start`.
        let command: String
        /// Humanized command stem, e.g. `start` → "Start", `audio-sync` → "Audio Sync".
        let title: String
        /// `description` from the command's frontmatter, if present.
        let description: String?
        /// `argument-hint` from the frontmatter, e.g. `<projektname>` — nil when the command takes none.
        let argumentHint: String?

        /// A command needs user-supplied arguments before it can run.
        var requiresArgument: Bool {
            guard let hint = argumentHint?.trimmingCharacters(in: .whitespaces) else { return false }
            return !hint.isEmpty
        }
    }

    /// Every discovered plugin with its commands, ordered by plugin name then command stem. Reuses
    /// `PluginManager.discoverPlugins()` so the same bundled + user-import discovery (and de-dup) applies.
    static func discover() -> [PluginInfo] {
        PluginManager.discoverPlugins().map { plugin in
            PluginInfo(
                name: plugin.name,
                description: manifestDescription(pluginDir: plugin.pluginDir),
                commands: commands(pluginName: plugin.name, pluginDir: plugin.pluginDir)
            )
        }
    }

    // MARK: - Manifest

    private static func manifestDescription(pluginDir: URL) -> String? {
        let manifest = pluginDir.appendingPathComponent(".claude-plugin/plugin.json")
        guard let data = try? Data(contentsOf: manifest),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let desc = obj["description"] as? String else { return nil }
        let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Commands

    private static func commands(pluginName: String, pluginDir: URL) -> [PluginCommand] {
        let fm = FileManager.default
        let commandsDir = pluginDir.appendingPathComponent("commands", isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(
            at: commandsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }

        return entries
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let stem = url.deletingPathExtension().lastPathComponent
                let front = frontmatter(at: url)
                return PluginCommand(
                    command: "/\(pluginName):\(stem)",
                    title: humanize(stem),
                    description: front.description,
                    argumentHint: front.argumentHint
                )
            }
    }

    // MARK: - Frontmatter (manual scan, no YAML dependency)

    private struct Frontmatter {
        var description: String?
        var argumentHint: String?
    }

    /// Scan the leading `---`…`---` block for `description:` and `argument-hint:`. Tolerant of a
    /// missing block, missing keys, quoted values, and leading whitespace. Only the first frontmatter
    /// block is read; body text is ignored.
    private static func frontmatter(at url: URL) -> Frontmatter {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return Frontmatter() }
        var result = Frontmatter()
        var inBlock = false
        var started = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "---" {
                if !started {
                    started = true
                    inBlock = true
                    continue
                }
                break  // closing delimiter — done
            }
            guard inBlock else {
                if !started { break }  // no opening delimiter → no frontmatter at all
                continue
            }
            if let value = value(of: "description", in: line) { result.description = value }
            else if let value = value(of: "argument-hint", in: line) { result.argumentHint = value }
        }
        return result
    }

    /// If `line` is `key: value`, return the unquoted, trimmed value (nil when empty). Case-insensitive
    /// on the key; matches only a leading `key:` so a `description` inside a value isn't caught.
    private static func value(of key: String, in line: String) -> String? {
        let prefix = key + ":"
        guard line.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        var value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, (first == "\"" || first == "'"), value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `start` → "Start", `audio-sync` / `audio_sync` → "Audio Sync". Splits on `-`/`_`/space,
    /// capitalizes each word's first letter, leaves the rest untouched (so acronyms survive).
    private static func humanize(_ stem: String) -> String {
        let words = stem
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { word -> String in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .filter { !$0.isEmpty }
        return words.isEmpty ? stem : words.joined(separator: " ")
    }
}
