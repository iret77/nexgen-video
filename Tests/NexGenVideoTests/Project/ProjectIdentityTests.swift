import Foundation
import Testing

@testable import NexGenVideo

@Suite("ProjectIdentity")
struct ProjectIdentityTests {
    /// A throwaway `.ngv` package dir, optionally seeded with an `ngv.json` (to simulate a pre-UUID
    /// project or one already carrying an active plugin).
    private func tempPackage(ngvJSON: [String: Any]? = nil) throws -> URL {
        let pkg = FileManager.default.temporaryDirectory
            .appendingPathComponent("ngv-id-\(UUID().uuidString).ngv", isDirectory: true)
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        if let ngvJSON {
            let data = try JSONSerialization.data(withJSONObject: ngvJSON)
            try data.write(to: pkg.appendingPathComponent(ProjectPluginSettings.filename))
        }
        return pkg
    }

    @Test("uuid is generated once and stable across calls")
    func stableAcrossCalls() throws {
        let pkg = try tempPackage()
        defer { try? FileManager.default.removeItem(at: pkg) }
        let a = ProjectIdentity.uuid(for: pkg)
        let b = ProjectIdentity.uuid(for: pkg)
        #expect(a == b)
        #expect(ProjectIdentity.key(for: pkg) == "p-" + a)
    }

    @Test("distinct packages get distinct identities")
    func distinctPackages() throws {
        let a = try tempPackage(); let b = try tempPackage()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(ProjectIdentity.uuid(for: a) != ProjectIdentity.uuid(for: b))
    }

    @Test("migration: a pre-UUID package keeps its active plugin and gains an id")
    func migratesPreservingPlugin() throws {
        let pkg = try tempPackage(ngvJSON: ["activePlugin": "musicvideo"])
        defer { try? FileManager.default.removeItem(at: pkg) }
        _ = ProjectIdentity.uuid(for: pkg)   // triggers migration write
        #expect(ProjectPluginSettings.activePlugin(projectURL: pkg) == "musicvideo")
        #expect(ProjectIdentity.uuid(for: pkg).isEmpty == false)
    }

    @Test("regenerate assigns a fresh identity (the Save-As / duplicate case)")
    func regenerateChangesId() throws {
        let pkg = try tempPackage()
        defer { try? FileManager.default.removeItem(at: pkg) }
        let before = ProjectIdentity.uuid(for: pkg)
        ProjectIdentity.regenerate(at: pkg)
        #expect(ProjectIdentity.uuid(for: pkg) != before)
    }
}
