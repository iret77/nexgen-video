import Foundation
import Testing
import NexGenEngine

@testable import NexGenVideo

/// The crash-safe working-copy round trip: materialize from the package, detect a crash-surviving
/// copy, persist back into the package, and recognize/retire the legacy `_studio` layout.
@MainActor
@Suite("ProjectWorkingCopy")
struct ProjectWorkingCopyTests {
    private func tempPackage(pipelineName: String = DataRootResolver.pipelineDirname) throws -> URL {
        let pkg = FileManager.default.temporaryDirectory
            .appendingPathComponent("ngv-wc-\(UUID().uuidString).ngv", isDirectory: true)
        let pipeline = pkg.appendingPathComponent(pipelineName, isDirectory: true)
        try FileManager.default.createDirectory(at: pipeline, withIntermediateDirectories: true)
        try "project: demo\nmode: beat\n".write(
            to: pipeline.appendingPathComponent("project.yaml"), atomically: true, encoding: .utf8)
        try "hello".write(
            to: pipeline.appendingPathComponent("bible.yaml"), atomically: true, encoding: .utf8)
        return pkg
    }

    private func uniqueKey() -> String { "test-\(UUID().uuidString)" }

    @Test("open with no working copy materializes from the package (no recovery)")
    func materializesFresh() throws {
        let pkg = try tempPackage()
        let key = uniqueKey()
        defer { ProjectWorkingCopy.discard(key: key); try? FileManager.default.removeItem(at: pkg) }

        let result = try ProjectWorkingCopy.open(key: key, packageURL: pkg)
        #expect(result.recoveredUnsaved == false)
        let copied = result.home.appendingPathComponent(DataRootResolver.pipelineDirname)
            .appendingPathComponent("bible.yaml")
        #expect(FileManager.default.fileExists(atPath: copied.path))
    }

    @Test("a surviving working copy is reported as recovered unsaved work")
    func detectsCrashCopy() throws {
        let pkg = try tempPackage()
        let key = uniqueKey()
        defer { ProjectWorkingCopy.discard(key: key); try? FileManager.default.removeItem(at: pkg) }

        _ = try ProjectWorkingCopy.open(key: key, packageURL: pkg)   // first session materializes
        let second = try ProjectWorkingCopy.open(key: key, packageURL: pkg)   // crash → copy survives
        #expect(second.recoveredUnsaved == true)
    }

    @Test("a working copy missing the completion sentinel is rebuilt, not recovered")
    func partialCopyNotRecovered() throws {
        let pkg = try tempPackage()
        let key = uniqueKey()
        defer { ProjectWorkingCopy.discard(key: key); try? FileManager.default.removeItem(at: pkg) }

        let home = try ProjectWorkingCopy.materialize(key: key, packageURL: pkg)
        // Simulate a partial/old copy: valid project.yaml present, but no completion sentinel.
        try FileManager.default.removeItem(at: home.appendingPathComponent(".ngv-materialized"))
        let result = try ProjectWorkingCopy.open(key: key, packageURL: pkg)
        #expect(result.recoveredUnsaved == false)
    }

    @Test("legacy _studio in the package is materialized into pipeline")
    func materializesLegacy() throws {
        let pkg = try tempPackage(pipelineName: DataRootResolver.legacyPipelineDirname)
        let key = uniqueKey()
        defer { ProjectWorkingCopy.discard(key: key); try? FileManager.default.removeItem(at: pkg) }

        let result = try ProjectWorkingCopy.open(key: key, packageURL: pkg)
        let copied = result.home.appendingPathComponent(DataRootResolver.pipelineDirname)
            .appendingPathComponent("project.yaml")
        #expect(FileManager.default.fileExists(atPath: copied.path))
    }

    @Test("persist syncs the working copy into the package and retires legacy _studio")
    func persistRoundTrip() throws {
        let pkg = try tempPackage(pipelineName: DataRootResolver.legacyPipelineDirname)
        let key = uniqueKey()
        defer { ProjectWorkingCopy.discard(key: key); try? FileManager.default.removeItem(at: pkg) }

        let home = try ProjectWorkingCopy.materialize(key: key, packageURL: pkg)
        // Edit the working copy, then persist.
        try "edited".write(
            to: home.appendingPathComponent(DataRootResolver.pipelineDirname).appendingPathComponent("bible.yaml"),
            atomically: true, encoding: .utf8)
        try ProjectWorkingCopy.persist(key: key, to: pkg)

        let persisted = pkg.appendingPathComponent(DataRootResolver.pipelineDirname)
            .appendingPathComponent("bible.yaml")
        #expect((try? String(contentsOf: persisted, encoding: .utf8)) == "edited")
        // The legacy dir is gone; the project carries only `pipeline/`.
        #expect(!FileManager.default.fileExists(
            atPath: pkg.appendingPathComponent(DataRootResolver.legacyPipelineDirname).path))
    }

    @Test("stableKey is deterministic for the same location")
    func stableKeyDeterministic() {
        let url = URL(fileURLWithPath: "/tmp/demo.ngv")
        #expect(ProjectWorkingCopy.stableKey(for: url) == ProjectWorkingCopy.stableKey(for: url))
    }
}
