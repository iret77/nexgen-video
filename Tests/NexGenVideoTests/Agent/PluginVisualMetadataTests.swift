import Foundation
import Testing

@testable import NexGenVideo

@Suite("Plugin visual metadata")
struct PluginVisualMetadataTests {

    private func makePluginDirs(name: String) throws -> (installRoot: URL, pluginDir: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("plugin-\(UUID().uuidString)/\(name)", isDirectory: true)
        let pluginDir = root.appendingPathComponent("plugin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: pluginDir.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        return (root, pluginDir)
    }

    @Test func fallbacksWithoutNgvManifest() throws {
        let (root, pluginDir) = try makePluginDirs(name: "musicvideo")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try #"{"name":"musicvideo","description":"Music video studio."}"#
            .write(to: pluginDir.appendingPathComponent(".claude-plugin/plugin.json"),
                   atomically: true, encoding: .utf8)

        let v = PluginManager.visualMetadata(installRoot: root, pluginDir: pluginDir, name: "musicvideo")
        #expect(v.displayName == "Musicvideo")
        #expect(v.tagline == "Music video studio.")   // falls back to claude's description
        #expect(v.headerImageURL == nil)
    }

    @Test func ngvManifestWinsAndResolvesHeader() throws {
        let (root, pluginDir) = try makePluginDirs(name: "musicvideo")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47])
            .write(to: root.appendingPathComponent("assets/header.png"))
        try #"{"displayName":"Music Video Studio","tagline":"Structured production.","headerImage":"assets/header.png"}"#
            .write(to: root.appendingPathComponent("ngv-plugin.json"), atomically: true, encoding: .utf8)

        let v = PluginManager.visualMetadata(installRoot: root, pluginDir: pluginDir, name: "musicvideo")
        #expect(v.displayName == "Music Video Studio")
        #expect(v.tagline == "Structured production.")
        #expect(v.headerImageURL?.lastPathComponent == "header.png")
    }

    @Test func missingHeaderFileYieldsNil() throws {
        let (root, pluginDir) = try makePluginDirs(name: "x")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try #"{"headerImage":"assets/gone.png"}"#
            .write(to: root.appendingPathComponent("ngv-plugin.json"), atomically: true, encoding: .utf8)

        let v = PluginManager.visualMetadata(installRoot: root, pluginDir: pluginDir, name: "x")
        #expect(v.headerImageURL == nil)
    }
}
