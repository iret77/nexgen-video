import Foundation

/// One-time cleanup of the pre-model layout: older builds scaffolded a project's pipeline (`_studio`)
/// and vestigial `inbox`/`review`/`final` zones loose in the projects folder, next to the `.ngv`
/// packages. They belong to no project under the new model. Move them to the Trash (recoverable, never
/// a hard delete) so the projects folder holds only project files. See `docs/PROJECT_STORAGE.md`.
enum ProjectStorageMigration {
    /// Loose directory names left by older builds that must not sit in the projects folder.
    private static let orphanNames = ["_studio", "inbox", "review", "final"]

    static func cleanUpProjectsFolder() {
        let fm = FileManager.default
        let root = Project.storageDirectory
        for name in orphanNames {
            let candidate = root.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue else { continue }
            do {
                try fm.trashItem(at: candidate, resultingItemURL: nil)
                Log.project.notice("moved orphaned '\(name)' out of the projects folder to Trash")
            } catch {
                Log.project.error("couldn't trash orphaned '\(name)': \(error.localizedDescription)")
            }
        }
    }
}
