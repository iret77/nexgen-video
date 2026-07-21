import Foundation
import Testing
@testable import NexGenVideo

@Suite("Pack surface — host decoders")
struct PackSurfaceTests {

    private static let analysisJSON = """
    {
      "schema": "analysis/v2",
      "project": "demo",
      "song_path": "audio/midnight_drive.wav",
      "sample_rate": 44100,
      "duration_s": 222.0,
      "bpm": 128.0,
      "tempo_multiplier": 1.0,
      "key": "A minor",
      "downbeat_source": "beat-transformer",
      "beats": [0.0, 0.47, 0.94, 1.41],
      "downbeats": [0.0, 1.88],
      "sections": [
        {"index": 0, "start": 0.0, "end": 27.0, "cluster": 0, "label": "Intro", "source": "consolidated"},
        {"index": 1, "start": 27.0, "end": 71.0, "cluster": 1, "label": "Verse 1", "source": "alignment"}
      ]
    }
    """

    @Test("AnalysisSurfaceData decodes the analysis/v2 fields the panel renders")
    func decodesAnalysisArtifact() throws {
        let d = try JSONDecoder().decode(AnalysisSurfaceData.self, from: Data(Self.analysisJSON.utf8))
        #expect(d.trackName == "midnight_drive.wav")
        #expect(d.durationS == 222.0)
        #expect(d.perceivedBpm == 128.0)
        #expect(d.key == "A minor")
        #expect(d.downbeatSource == "beat-transformer")
        #expect(d.beats.count == 4)
        #expect(d.downbeats.count == 2)
        #expect(d.hasBeatGrid)
        #expect(d.sections.count == 2)
        #expect(d.sections.first?.label == "Intro")
        #expect(d.sections.last?.end == 71.0)
    }

    @Test("perceivedBpm applies the confirmed tempo multiplier")
    func perceivedBpmUsesMultiplier() throws {
        let json = Self.analysisJSON.replacingOccurrences(of: "\"tempo_multiplier\": 1.0", with: "\"tempo_multiplier\": 2.0")
        let d = try JSONDecoder().decode(AnalysisSurfaceData.self, from: Data(json.utf8))
        #expect(d.perceivedBpm == 256.0)
    }

    @Test("a beatless track decodes as degraded (no beat grid)")
    func degradedWhenNoBeats() throws {
        let json = Self.analysisJSON
            .replacingOccurrences(of: "\"beats\": [0.0, 0.47, 0.94, 1.41]", with: "\"beats\": []")
            .replacingOccurrences(of: "\"downbeats\": [0.0, 1.88]", with: "\"downbeats\": []")
        let d = try JSONDecoder().decode(AnalysisSurfaceData.self, from: Data(json.utf8))
        #expect(!d.hasBeatGrid)
        #expect(d.key == "A minor")   // still usable
    }

    @Test("ContractData decodes pack-contributed cockpit_surfaces; legacy files decode empty")
    func contractCockpitSurfaces() throws {
        let json = """
        {"surfaces":["choice","prose","review"],
         "phases":{"analysis":{"surface":"choice","task_class":"classification"}},
         "cockpit_surfaces":[{"id":"analysis","title":"Analysis","symbol":"waveform","phase":"analysis","kind":"beatAnalysis"}]}
        """
        let c = try JSONDecoder().decode(ContractData.self, from: Data(json.utf8))
        #expect(c.cockpitSurfaces.count == 1)
        #expect(c.cockpitSurfaces.first?.id == "analysis")
        #expect(c.cockpitSurfaces.first?.kind == "beatAnalysis")
        #expect(c.cockpitSurfaces.first?.symbol == "waveform")

        let legacy = try JSONDecoder().decode(ContractData.self, from: Data(#"{"phases":{}}"#.utf8))
        #expect(legacy.cockpitSurfaces.isEmpty)
    }
}
