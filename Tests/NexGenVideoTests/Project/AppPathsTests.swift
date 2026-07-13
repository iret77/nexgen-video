import Foundation
import Testing
@testable import NexGenVideo

/// The storage-tier layout (docs/PROJECT_STORAGE.md). The Caches tier is per-project scratch, keyed
/// under `projectCachesRoot`, and generation staging lives inside a project's cache — so the launch
/// idle-sweep (which walks `projectCachesRoot` for `p-…` keys) retires it.
@Suite("AppPaths tiers")
struct AppPathsTests {
    @Test("project cache + staging nest under the Caches projects root, distinct from Recovery")
    func tierLayout() {
        let key = "p-DEADBEEF"
        let cache = AppPaths.projectCache(projectId: key)
        let staging = AppPaths.projectStaging(projectId: key)

        #expect(cache.deletingLastPathComponent() == AppPaths.projectCachesRoot)
        #expect(cache.lastPathComponent == key)
        #expect(staging.deletingLastPathComponent() == cache)
        #expect(staging.lastPathComponent == "staging")

        // Caches tier, never the durable Application Support / Recovery tier.
        #expect(AppPaths.projectCachesRoot.path.contains("/Caches/"))
        #expect(!AppPaths.projectCachesRoot.path.contains("Application Support"))
        #expect(AppPaths.projectCache(projectId: key) != AppPaths.workingCopy(projectId: key))
    }
}
