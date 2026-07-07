import Foundation
import Testing

@testable import NexGenVideo

@Suite("Plugin catalog decode")
struct PluginCatalogDecodeTests {

    @Test func decodesCatalog() throws {
        let json = """
        {
          "schema": "plugins/v1",
          "plugins": [
            {
              "id": "musicvideo",
              "displayName": "Music Video Studio",
              "tagline": "Structured AI music-video production.",
              "version": "0.0.1",
              "minAppVersion": "0.1.0",
              "url": "https://github.com/iret77/nexgen-video/releases/download/dev-latest/musicvideo.ngvpack.zip",
              "sha256": "abc123"
            }
          ]
        }
        """.data(using: .utf8)!

        let catalog = try PluginCatalogService.decode(json)
        #expect(catalog.plugins.count == 1)
        let entry = try #require(catalog.plugins.first)
        #expect(entry.id == "musicvideo")
        #expect(entry.displayName == "Music Video Studio")
        #expect(entry.version == "0.0.1")
        #expect(entry.minAppVersion == "0.1.0")
        #expect(entry.sha256 == "abc123")
        #expect(entry.url.lastPathComponent == "musicvideo.ngvpack.zip")
    }

    @Test func emptyCatalogDecodes() throws {
        let catalog = try PluginCatalogService.decode(#"{"plugins":[]}"#.data(using: .utf8)!)
        #expect(catalog.plugins.isEmpty)
    }

    @Test func malformedCatalogThrows() {
        #expect(throws: (any Error).self) {
            _ = try PluginCatalogService.decode(#"{"plugins":[{"id":"x"}]}"#.data(using: .utf8)!)
        }
    }

    /// An installed pack is "updatable" when the catalog offers a newer version —
    /// a straight SemanticVersion compare, the same the picker uses.
    @Test func updateDetection() {
        #expect(SemanticVersion("0.0.2")! > SemanticVersion("0.0.1")!)
        #expect(!(SemanticVersion("0.0.1")! > SemanticVersion("0.0.1")!))
    }
}
