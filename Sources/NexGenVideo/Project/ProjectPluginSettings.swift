import Foundation

/// Per-project production settings, stored as `<package>/ngv.json` — app-owned and written directly
/// (outside the NSDocument save cycle) so it can't interact with document versioning. Carries the
/// ACTIVE format plugin: exactly one per project, or none for the generic workflow. Installed ≠
/// active (Epic #98 / #95 C2) — a plugin being on disk never means every project builds with it.
enum ProjectPluginSettings {
    static let filename = "ngv.json"

    static func activePlugin(projectURL: URL?) -> String? {
        guard let projectURL else { return nil }
        let url = projectURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = json["activePlugin"] as? String, !name.isEmpty else { return nil }
        return name
    }

    static func setActivePlugin(_ name: String?, projectURL: URL) {
        let url = projectURL.appendingPathComponent(filename)
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            json = existing
        }
        if let name, !name.isEmpty {
            json["activePlugin"] = name
        } else {
            json.removeValue(forKey: "activePlugin")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
