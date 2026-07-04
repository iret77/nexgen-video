import Foundation

// Mirrors `read.py "frames"` (engine/nexgen_engine/frames/inventory.py): the on-disk frame
// candidates per shot directory. Decoding is defensive — missing keys fall back, unknown audit
// keys are ignored (only `status` is surfaced).

struct FramesData: Decodable, Sendable, Equatable {
    var project: String
    var shots: [FrameShot]

    enum CodingKeys: String, CodingKey {
        case project, shots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        shots = try c.decodeIfPresent([FrameShot].self, forKey: .shots) ?? []
    }
}

struct FrameShot: Decodable, Sendable, Equatable, Identifiable {
    var shotId: String
    var frames: [FrameCandidate]
    var auditStatus: String?

    var id: String { shotId }

    enum CodingKeys: String, CodingKey {
        case frames, audit
        case shotId = "shot_id"
    }

    private struct Audit: Decodable {
        var status: String?
        enum CodingKeys: String, CodingKey { case status }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = try? c.decodeIfPresent(String.self, forKey: .status)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shotId = try c.decodeIfPresent(String.self, forKey: .shotId) ?? ""
        frames = try c.decodeIfPresent([FrameCandidate].self, forKey: .frames) ?? []
        auditStatus = ((try? c.decodeIfPresent(Audit.self, forKey: .audit)) ?? nil)?.status
    }
}

struct FrameCandidate: Decodable, Sendable, Equatable, Identifiable {
    var name: String
    var path: String

    var id: String { path }

    enum CodingKeys: String, CodingKey { case name, path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
    }
}
