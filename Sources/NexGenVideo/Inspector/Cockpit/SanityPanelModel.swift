import Foundation

// Mirrors the engine's sanity report JSON (engine/nexgen_engine/mcp_server.run_sanity → read.py
// "sanity"): `{project, findings: [{level, code, shot_id, message}]}`. When the project has no
// shotlist yet the CLI emits `{"error": "no shotlist", ...}` — CockpitDataService.sanity treats that
// as `.success(nil)`, so this model only ever decodes a real report. Decoding is defensive; unknown
// keys are ignored so a newer engine schema still loads read-only.

struct SanityData: Decodable, Sendable, Equatable {
    var project: String
    var findings: [SanityFinding]

    enum CodingKeys: String, CodingKey {
        case project, findings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        findings = try c.decodeIfPresent([SanityFinding].self, forKey: .findings) ?? []
    }

    var errorCount: Int { findings.filter { $0.level == .error }.count }
    var warningCount: Int { findings.filter { $0.level == .warn }.count }
    var infoCount: Int { findings.filter { $0.level == .info }.count }

    /// True when nothing at all was flagged.
    var isClean: Bool { findings.isEmpty }

    /// A terse count-by-level summary, e.g. "2 errors · 3 warnings". Empty when clean.
    var summary: String {
        var parts: [String] = []
        if errorCount > 0 { parts.append("\(errorCount) \(errorCount == 1 ? "error" : "errors")") }
        if warningCount > 0 { parts.append("\(warningCount) \(warningCount == 1 ? "warning" : "warnings")") }
        if infoCount > 0 { parts.append("\(infoCount) \(infoCount == 1 ? "note" : "notes")") }
        return parts.joined(separator: " · ")
    }
}

/// One audit finding. `level` is one of info/warn/error (see engine sanity/models.py `Level`).
struct SanityFinding: Decodable, Sendable, Equatable, Identifiable {
    var level: SanityLevel
    var code: String
    var shotId: String?
    var message: String

    /// Stable identity for ForEach; findings aren't uniquely keyed by the engine, so combine fields.
    let id = UUID()

    enum CodingKeys: String, CodingKey {
        case level, code, message
        case shotId = "shot_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(SanityLevel.self, forKey: .level) ?? .info
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        shotId = try c.decodeIfPresent(String.self, forKey: .shotId)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
    }

    static func == (lhs: SanityFinding, rhs: SanityFinding) -> Bool {
        lhs.level == rhs.level && lhs.code == rhs.code
            && lhs.shotId == rhs.shotId && lhs.message == rhs.message
    }
}

/// Finding severity. Unknown/future values decode as `.info` so the panel never fails to load.
enum SanityLevel: String, Decodable, Sendable, Equatable {
    case info
    case warn
    case error

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SanityLevel(rawValue: raw) ?? .info
    }
}
