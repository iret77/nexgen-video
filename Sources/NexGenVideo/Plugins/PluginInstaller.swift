import CryptoKit
import Foundation

/// Downloads, verifies, and installs a catalog pack, then loads it through the
/// same gate as a startup pack. Verification is defense in depth: SHA-256 of the
/// download must match the catalog, and the unpacked bundle's code signature is
/// checked by `PluginLoader` before any code runs.
@MainActor
enum PluginInstaller {
    enum InstallError: LocalizedError {
        case download(String)
        case checksumMismatch(expected: String, actual: String)
        case unpack(String)
        case idMismatch(expected: String, found: String)
        case gate(PluginIncompatibility)

        var errorDescription: String? {
            switch self {
            case .download(let detail): return "Download failed — \(detail)."
            case .checksumMismatch:
                return "The download didn't match its checksum and was discarded."
            case .unpack(let detail): return "Couldn't unpack the pack — \(detail)."
            case .idMismatch(let expected, let found):
                return "The pack identifies as \"\(found)\" but the catalog listed \"\(expected)\"."
            case .gate(let reason): return reason.reason
            }
        }
    }

    /// Install (or update) `entry`: download → checksum → unpack → move into the
    /// plugins directory (replacing any prior version) → load through the gate.
    /// Returns the loaded record. Throws `InstallError` with a user-facing reason.
    @discardableResult
    static func install(
        _ entry: PluginCatalog.Entry,
        appVersion: String? = AppVersion.marketing
    ) async throws -> InstalledPluginRecord {
        guard PluginPaths.isValidID(entry.id) else {
            throw InstallError.unpack("the catalog id \"\(entry.id)\" is invalid")
        }

        let data = try await download(entry.url)

        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(entry.sha256) == .orderedSame else {
            throw InstallError.checksumMismatch(expected: entry.sha256, actual: actual)
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("ngvpack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let zipURL = work.appendingPathComponent("pack.zip")
        try data.write(to: zipURL)
        let extractDir = work.appendingPathComponent("x", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try unzip(zipURL, into: extractDir)

        guard let unpacked = firstBundle(in: extractDir) else {
            throw InstallError.unpack("no .ngvpack inside the archive")
        }
        if let info = PluginBundleInfo(bundleURL: unpacked), info.id != entry.id {
            throw InstallError.idMismatch(expected: entry.id, found: info.id)
        }

        try moveIntoPlace(unpacked, id: entry.id)

        // Re-scan: loads + registers the new/updated pack, refreshes the picker
        // inventory, and preserves any other installed packs' states.
        let records = PluginLoader.loadInstalled(appVersion: appVersion)
        guard let record = records.first(where: { $0.id == entry.id }) else {
            throw InstallError.unpack("the installed pack didn't reappear in the library")
        }
        if let reason = record.incompatibility { throw InstallError.gate(reason) }
        return record
    }

    /// Remove an installed pack from disk. The already-loaded code stays live
    /// until the next launch (dylibs can't be safely unloaded mid-session), but
    /// it won't reload — the picker reflects that immediately.
    static func uninstall(id: String) throws {
        let url = PluginPaths.installURL(id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Steps

    private static func download(_ url: URL) async throws -> Data {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw InstallError.download("HTTP \(http.statusCode)")
            }
            guard !data.isEmpty else { throw InstallError.download("empty response") }
            return data
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.download(error.localizedDescription)
        }
    }

    private static func unzip(_ zip: URL, into dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, dir.path]
        do { try process.run() } catch { throw InstallError.unpack(error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.unpack("archive extraction failed")
        }
    }

    private static func firstBundle(in dir: URL) -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries.first { $0.pathExtension == PluginPaths.bundleExtension }
    }

    /// Atomically place `unpacked` at `<installDir>/<id>.ngvpack`, replacing any
    /// existing install. Staged inside the install directory so the swap stays on
    /// one volume.
    private static func moveIntoPlace(_ unpacked: URL, id: String) throws {
        let dest = PluginPaths.installURL(id: id)
        try FileManager.default.createDirectory(
            at: PluginPaths.installDirectory, withIntermediateDirectories: true)
        let staging = PluginPaths.installDirectory
            .appendingPathComponent(".staging-\(UUID().uuidString).\(PluginPaths.bundleExtension)")
        do {
            try FileManager.default.copyItem(at: unpacked, to: staging)
            if FileManager.default.fileExists(atPath: dest.path) {
                _ = try FileManager.default.replaceItemAt(dest, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: dest)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw InstallError.unpack(error.localizedDescription)
        }
    }
}
