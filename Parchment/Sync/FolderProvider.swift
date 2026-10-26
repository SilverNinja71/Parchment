import Foundation

/// iCloud Drive and every other storage app on the iPad (Box, pCloud, Proton Drive,
/// Synology Drive, Nextcloud app…) through the Files app's folder picker.
///
/// Signing in happens in the system (Settings → Apple Account, or the provider's own app);
/// Parchment just remembers the folder you picked with a security-scoped bookmark.
@MainActor
final class FolderProvider: CloudProvider {
    let service: CloudService

    init(service: CloudService) {
        self.service = service
    }

    private var bookmarkKey: String { "sync.folderBookmark.\(service.rawValue)" }
    var isSignedIn: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// Remembers a folder chosen in the system picker.
    func connect(to url: URL) throws -> RemoteFolder {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        return rootFolder()
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    func accountName() async throws -> String {
        service == .iCloudDrive ? "Your Apple Account" : (try? rootURL().lastPathComponent) ?? "Files app"
    }

    func rootFolder() -> RemoteFolder {
        let name = (try? rootURL().lastPathComponent) ?? service.title
        return RemoteFolder(id: "", name: name, displayPath: service == .iCloudDrive ? "iCloud Drive › \(name)" : name)
    }

    func list(_ folder: RemoteFolder) async throws -> [RemoteItem] {
        let root = try rootURL()
        return try await withAccess(root) {
            let directory = folder.id.isEmpty ? root : root.appendingPathComponent(folder.id, isDirectory: true)
            let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
            return urls.compactMap { url -> RemoteItem? in
                var name = url.lastPathComponent
                // Older iCloud Drive shows not-yet-downloaded files as ".Name.icloud".
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    name = String(name.dropFirst().dropLast(".icloud".count))
                } else if name.hasPrefix(".") {
                    return nil
                }
                let values = try? url.resourceValues(forKeys: Set(keys))
                let relative = folder.id.isEmpty ? name : "\(folder.id)/\(name)"
                return RemoteItem(id: relative, name: name, isFolder: values?.isDirectory ?? false,
                                  modified: values?.contentModificationDate, size: values?.fileSize)
            }
        }
    }

    func createFolder(named name: String, in folder: RemoteFolder) async throws -> RemoteFolder {
        let root = try rootURL()
        let relative = folder.id.isEmpty ? name : "\(folder.id)/\(name)"
        try await withAccess(root) {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(relative, isDirectory: true),
                                                    withIntermediateDirectories: true)
        }
        return folder.child(RemoteItem(id: relative, name: name, isFolder: true))
    }

    func upload(_ data: Data, named name: String, to folder: RemoteFolder, replacing existing: RemoteItem?) async throws -> RemoteItem {
        let root = try rootURL()
        let relative = existing?.id ?? (folder.id.isEmpty ? name : "\(folder.id)/\(name)")
        let url = root.appendingPathComponent(relative)
        let modified = try await withAccess(root) { () throws -> Date? in
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
                do { try data.write(to: target, options: .atomic) } catch { writeError = error }
            }
            if let error = coordinationError ?? writeError { throw error }
            return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return RemoteItem(id: relative, name: name, isFolder: false, modified: modified ?? Date(), size: data.count)
    }

    func download(_ item: RemoteItem) async throws -> Data {
        let root = try rootURL()
        let url = root.appendingPathComponent(item.id)
        return try await withAccess(root) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            var coordinationError: NSError?
            var result: Result<Data, Error> = .failure(ParchmentError.notFound("Couldn't read \(item.name)."))
            // Coordinated reads wait for cloud files to finish downloading.
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
                result = Result { try Data(contentsOf: source) }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }
    }

    // MARK: - Helpers

    private func rootURL() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw ParchmentError.sync("Choose a \(service.title) folder in Settings → Sync.")
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    /// Runs file work off the main thread while holding access to the chosen folder.
    private func withAccess<T: Sendable>(_ root: URL, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority: .utility) { try work() }.value
    }
}
