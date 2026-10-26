import Foundation
import Combine
import SwiftUI

/// Two-way sync between this iPad and the folder the user picked in their cloud.
///
/// Each notebook is stored remotely as one `.parchment` file. On every sync:
/// - notebooks edited here are uploaded,
/// - files edited elsewhere are downloaded,
/// - if both changed, the cloud version is kept as a "(conflict)" copy so nothing is lost,
/// - new files in the folder (from another iPad) are added to the library.
/// Deleting a notebook never deletes the cloud copy.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case idle
        case syncing(String)
        case synced(Date)
        case failed(String)
    }

    struct Connection: Codable, Equatable {
        var service: CloudService
        var folder: RemoteFolder
        var accountName: String
    }

    /// What we know about each notebook's cloud copy since the last successful sync.
    private struct Record: Codable {
        var remoteID: String
        var localModified: Date
        var remoteModified: Date
    }

    @Published private(set) var connection: Connection?
    @Published private(set) var status: Status = .idle
    @Published var autoSync: Bool { didSet { defaults.set(autoSync, forKey: Keys.autoSync) } }
    @Published var savePDFCopies: Bool { didSet { defaults.set(savePDFCopies, forKey: Keys.pdfCopies) } }

    private var records: [UUID: Record] = [:]
    private var providers: [CloudService: CloudProvider] = [:]
    private var isSyncing = false
    private var syncAgain = false
    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard
    private let store: NotebookStore

    private enum Keys {
        static let connection = "sync.connection"
        static let records = "sync.records"
        static let autoSync = "sync.auto"
        static let pdfCopies = "sync.pdfCopies"
    }

    init(store: NotebookStore? = nil) {
        self.store = store ?? .shared
        autoSync = defaults.object(forKey: Keys.autoSync) as? Bool ?? true
        savePDFCopies = defaults.bool(forKey: Keys.pdfCopies)
        connection = defaults.data(forKey: Keys.connection).flatMap { try? JSONDecoder().decode(Connection.self, from: $0) }
        records = defaults.data(forKey: Keys.records).flatMap { try? JSONDecoder().decode([UUID: Record].self, from: $0) } ?? [:]

        // Sync a little while after the user stops writing.
        self.store.userDidEdit
            .debounce(for: .seconds(15), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncIfAutomatic() }
            .store(in: &cancellables)
    }

    // MARK: - Providers

    func provider(for service: CloudService) -> CloudProvider {
        if let provider = providers[service] { return provider }
        let provider: CloudProvider
        switch service {
        case .iCloudDrive, .otherApp: provider = FolderProvider(service: service)
        case .oneDrive: provider = OneDriveProvider()
        case .googleDrive: provider = GoogleDriveProvider()
        case .dropbox: provider = DropboxProvider()
        case .webDAV: provider = WebDAVProvider()
        }
        providers[service] = provider
        return provider
    }

    /// Whether the developer has filled in the app ID this service needs (see CloudCredentials.swift).
    func isConfigured(_ service: CloudService) -> Bool {
        switch service {
        case .oneDrive: return CloudCredentials.isConfigured(CloudCredentials.oneDriveClientID)
        case .googleDrive: return CloudCredentials.isConfigured(CloudCredentials.googleClientID)
        case .dropbox: return CloudCredentials.isConfigured(CloudCredentials.dropboxAppKey)
        case .iCloudDrive, .webDAV, .otherApp: return true
        }
    }

    // MARK: - Connecting

    /// Called once the user has signed in and picked a folder.
    func connect(_ service: CloudService, folder: RemoteFolder) async {
        let provider = provider(for: service)
        let account = (try? await provider.accountName()) ?? service.title
        if let previous = connection, previous.service != service || previous.folder.id != folder.id {
            records = [:] // a new place starts fresh
        }
        connection = Connection(service: service, folder: folder, accountName: account)
        persist()
        await syncNow()
    }

    func disconnect(signOut: Bool) {
        if let connection, signOut { provider(for: connection.service).signOut() }
        connection = nil
        records = [:]
        status = .idle
        persist()
    }

    // MARK: - Syncing

    func syncIfAutomatic() {
        guard autoSync, connection != nil else { return }
        Task { await syncNow() }
    }

    func syncNow() async {
        guard let connection else { return }
        if isSyncing {
            syncAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            syncAgain = false
            do {
                try await sync(with: provider(for: connection.service), folder: connection.folder)
                status = .synced(Date())
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        } while syncAgain
    }

    private func sync(with provider: CloudProvider, folder: RemoteFolder) async throws {
        status = .syncing("Checking \(provider.service.title)…")
        let remoteItems = try await provider.list(folder)
        let remoteFiles = remoteItems.filter { !$0.isFolder && $0.name.hasSuffix(".\(NotebookArchive.fileExtension)") }
        let remoteByID = Dictionary(remoteFiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var takenNames = Set(remoteItems.map { $0.name.lowercased() })
        var handled = Set<String>()

        // 1. Every local notebook: push, pull or resolve a conflict.
        for notebook in store.notebooks where !notebook.isPersonalizationKit {
            let record = records[notebook.id]
            let remote = record.flatMap { remoteByID[$0.remoteID] }
            let localChanged = record.map { notebook.modified.timeIntervalSince($0.localModified) > 0.5 } ?? true
            let remoteChanged = remote.map { remoteModified($0).timeIntervalSince(record?.remoteModified ?? .distantPast) > 1 } ?? false

            if let remote { handled.insert(remote.id) }

            switch (remote, localChanged, remoteChanged) {
            case (nil, _, _):
                // Never uploaded, or the cloud copy was removed: upload it.
                status = .syncing("Uploading \(notebook.title)…")
                let name = uniqueName(for: notebook, taken: &takenNames)
                try await upload(notebook, named: name, replacing: nil, with: provider, folder: folder)
            case (let remote?, true, false):
                status = .syncing("Uploading \(notebook.title)…")
                try await upload(notebook, named: remote.name, replacing: remote, with: provider, folder: folder)
            case (let remote?, false, true):
                status = .syncing("Downloading \(notebook.title)…")
                try await download(remote, with: provider)
            case (let remote?, true, true):
                // Edited in both places: keep the cloud version as a copy, then upload ours.
                status = .syncing("Saving both versions of \(notebook.title)…")
                let data = try await provider.download(remote)
                try store.importArchive(data, asCopy: true, titleSuffix: "(conflict)")
                try await upload(notebook, named: remote.name, replacing: remote, with: provider, folder: folder)
            default:
                break // already in sync
            }
        }

        // 2. Files we haven't seen yet (made on another device).
        for item in remoteFiles where !handled.contains(item.id) {
            status = .syncing("Downloading \(item.name)…")
            try await download(item, with: provider)
        }
        persist()
    }

    private func upload(_ notebook: Notebook, named name: String, replacing existing: RemoteItem?,
                        with provider: CloudProvider, folder: RemoteFolder) async throws {
        let data = try store.archive(notebook.id)
        let item = try await provider.upload(data, named: name, to: folder, replacing: existing)
        records[notebook.id] = Record(remoteID: item.id, localModified: notebook.modified, remoteModified: remoteModified(item))

        if savePDFCopies, let pdf = try? store.exportPDF(notebook.id), let pdfData = try? Data(contentsOf: pdf) {
            let pdfName = (name as NSString).deletingPathExtension + ".pdf"
            _ = try? await provider.upload(pdfData, named: pdfName, to: folder, replacing: nil)
        }
    }

    private func download(_ item: RemoteItem, with provider: CloudProvider) async throws {
        let data = try await provider.download(item)
        let archive = try NotebookArchive.decode(data)
        // Only replace a local notebook if the cloud copy is newer.
        if let local = store.notebook(archive.notebook.id), local.modified > archive.notebook.modified,
           records[local.id] == nil {
            records[local.id] = Record(remoteID: item.id, localModified: .distantPast, remoteModified: remoteModified(item))
            return // the next pass uploads the newer local copy
        }
        let notebook = try store.importArchive(data)
        records[notebook.id] = Record(remoteID: item.id, localModified: notebook.modified, remoteModified: remoteModified(item))
    }

    private func remoteModified(_ item: RemoteItem) -> Date { item.modified ?? .distantPast }

    private func uniqueName(for notebook: Notebook, taken: inout Set<String>) -> String {
        var name = store.archiveFileName(for: notebook)
        if taken.contains(name.lowercased()) {
            name = "\(NotebookStore.safeFileName(notebook.title)) \(notebook.id.uuidString.prefix(4)).\(NotebookArchive.fileExtension)"
        }
        taken.insert(name.lowercased())
        return name
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(connection), forKey: Keys.connection)
        defaults.set(try? JSONEncoder().encode(records), forKey: Keys.records)
    }
}
