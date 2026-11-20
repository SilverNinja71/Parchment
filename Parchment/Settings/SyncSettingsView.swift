import SwiftUI
import UniformTypeIdentifiers

/// Settings → Sync. Pick a service, sign in, then choose any folder to keep your notes in.
struct SyncSettingsView: View {
    @EnvironmentObject private var sync: SyncEngine
    @Environment(\.webAuthenticationSession) private var webAuthentication

    @State private var folderPickerService: CloudService?
    @State private var showFolderPicker = false
    @State private var browsing: CloudService?
    @State private var formSignInService: CloudService?
    @State private var signingIn: CloudService?
    @State private var errorMessage: String?
    @State private var disconnecting: SyncEngine.Connection?

    /// Services that need a developer app ID stay hidden until one is added (see README).
    private var availableServices: [CloudService] { CloudService.allCases.filter { sync.isConfigured($0) } }

    var body: some View {
        Form {
            accountSummary

            if !sync.connections.isEmpty {
                Section {
                    ForEach(sync.connections) { connection in
                        HStack(spacing: 14) {
                            ServiceIcon(service: connection.service)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.service.title).font(.headline)
                                Text(connection.accountName).font(.subheadline).foregroundStyle(.secondary)
                                Label(connection.folder.displayPath, systemImage: "folder")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if sync.activeConnectionID == connection.id { ProgressView() }
                            Menu {
                                Button("Change Folder") { chooseFolder(for: connection.service) }
                                Button("Stop Syncing Here", role: .destructive) { disconnecting = connection }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3)
                            }
                            .accessibilityLabel("Options for \(connection.service.title)")
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        Task { await sync.syncNow() }
                    } label: {
                        HStack {
                            ThemedLabel("Sync Now", icon: .sync)
                            Spacer()
                            SyncStatusText()
                        }
                    }
                    Toggle("Sync Automatically", isOn: $sync.autoSync)
                    Toggle("Also Save PDF Copies", isOn: $sync.savePDFCopies)
                } header: {
                    Text(sync.connections.count == 1 ? "Syncing To" : "Syncing To \(sync.connections.count) Places")
                } footer: {
                    Text("Every place gets a full copy of every notebook, saved as .parchment files you can open on any iPad with BelloBook. Deleting a notebook here never deletes it from the cloud.")
                }
            }

            Section {
                ForEach(availableServices) { service in
                    Button {
                        start(service)
                    } label: {
                        HStack(spacing: 14) {
                            ServiceIcon(service: service)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.title).foregroundStyle(.primary)
                                Text(service.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if signingIn == service {
                                ProgressView()
                            } else if sync.connections.contains(where: { $0.service == service }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Style.selection)
                            } else {
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(signingIn != nil)
                }
            } header: {
                Text(sync.connections.isEmpty ? "Sign In With" : "Also Back Up To")
            } footer: {
                Text("For iCloud Drive you're already signed in with this iPad's Apple Account: choose iCloud Drive in the picker, then a folder (or make one called BelloBook). BelloBook is free; backup never needs a subscription.")
            }
        }
        .navigationTitle("Account & Backup")
        // The picker closes before it reports back, so the service is kept separately from
        // the "is it showing" flag (otherwise the choice is gone by the time it arrives).
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            guard let service = folderPickerService else { return }
            switch result {
            case .success(let url):
                guard let provider = sync.provider(for: service) as? FolderProvider else { return }
                do {
                    let folder = try provider.connect(to: url)
                    Task { await sync.connect(service, folder: folder) }
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $browsing) { service in
            NavigationStack {
                RemoteFolderBrowser(provider: sync.provider(for: service),
                                    folder: sync.provider(for: service).rootFolder()) { folder in
                    browsing = nil
                    Task { await sync.connect(service, folder: folder) }
                }
            }
        }
        .sheet(item: $formSignInService) { svc in
            WebDAVSignInView(service: svc) { browsing = svc }
        }
        .alert("Couldn't connect", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Stop syncing to \(disconnecting?.service.title ?? "this place")?",
                            isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
                            titleVisibility: .visible) {
            Button("Stop and Sign Out", role: .destructive) { if let connection = disconnecting { sync.disconnect(connection, signOut: true) } }
            Button("Stop but Stay Signed In") { if let connection = disconnecting { sync.disconnect(connection, signOut: false) } }
        } message: {
            Text("Your notebooks stay on this iPad and in that folder.")
        }
    }

    private var syncFailed: Bool {
        if case .failed = sync.status { return true }
        return false
    }

    /// Says plainly whether your work is safe.
    private var accountSummary: some View {
        let needsAttention = sync.connections.isEmpty || syncFailed
        return Section {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: needsAttention ? "exclamationmark.icloud" : "checkmark.icloud.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(needsAttention ? Color.orange : Style.selection)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sync.connections.isEmpty ? "Sign in to keep your work safe"
                         : syncFailed ? "Backup isn't working right now" : "Your work is backed up")
                        .font(.headline)
                    Text(sync.connections.isEmpty
                         ? "Right now your work is only on this iPad. If you delete BelloBook, it goes with it. Sign in below and BelloBook keeps a copy of your notebooks, media vault, flashcards, study progress and drawings in your own account."
                         : syncFailed
                         ? "The last sync didn't finish, so your newest changes may only be on this iPad. The reason is shown below; tap Sync Now to try again."
                         : "Your notebooks, media vault, flashcards, study progress and drawings are saved to your account. Sign in to the same place on any iPad, or after reinstalling, and it all comes back.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func start(_ service: CloudService) {
        let provider = sync.provider(for: service)
        switch service.signInStyle {
        case .folderPicker:
            folderPickerService = service
            showFolderPicker = true
        case .webDAVForm:
            if provider.isSignedIn { browsing = service } else { formSignInService = service }
        case .oauth:
            guard let oauthProvider = provider as? any OAuthCloudProvider else { return }
            if oauthProvider.isSignedIn {
                browsing = service
                return
            }
            signingIn = service
            Task {
                defer { signingIn = nil }
                do {
                    try await oauthProvider.signIn(using: webAuthentication)
                    browsing = service
                } catch {
                    if !Self.isCancellation(error) { errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private func chooseFolder(for service: CloudService) {
        if service.signInStyle == .folderPicker {
            folderPickerService = service
            showFolderPicker = true
        } else {
            browsing = service
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && nsError.code == 1
            || error is CancellationError
    }
}

/// Browse folders inside a signed-in account and pick where notes are saved.
struct RemoteFolderBrowser: View {
    let provider: CloudProvider
    let folder: RemoteFolder
    var onChoose: (RemoteFolder) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [RemoteItem] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var newFolderName = ""
    @State private var creatingFolder = false

    private var folders: [RemoteItem] { items.filter(\.isFolder).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    private var notebookCount: Int { items.filter { $0.name.hasSuffix(".\(NotebookArchive.fileExtension)") }.count }

    var body: some View {
        List {
            Section {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if folders.isEmpty {
                    Text("No folders here").foregroundStyle(.secondary)
                }
                ForEach(folders) { item in
                    NavigationLink {
                        RemoteFolderBrowser(provider: provider, folder: folder.child(item), onChoose: onChoose)
                    } label: {
                        Label(item.name, systemImage: "folder.fill")
                    }
                }
            } header: {
                Text(folder.displayPath)
            } footer: {
                if notebookCount > 0 {
                    Text("This folder already has \(notebookCount) BelloBook notebook\(notebookCount == 1 ? "" : "s"). They'll be added to your library.")
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newFolderName = "BelloBook"
                    creatingFolder = true
                } label: { Label("New Folder", systemImage: "folder.badge.plus") }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    onChoose(folder)
                } label: {
                    Text("Save Notes in \"\(folder.name)\"").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .alert("New Folder", isPresented: $creatingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await createFolder() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await provider.list(folder)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createFolder() async {
        let name = NotebookStore.safeFileName(newFolderName)
        do {
            _ = try await provider.createFolder(named: name, in: folder)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Server address, username and password for WebDAV or self-hosted BelloBook/Amphi servers.
struct WebDAVSignInView: View {
    var service: CloudService = .webDAV
    var onSignedIn: () -> Void
    @EnvironmentObject private var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(service == .amphiServer ? "https://notes.example.com" : "https://cloud.example.com/remote.php/dav/files/you/", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(service == .amphiServer ? "Username (optional)" : "Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(service == .amphiServer ? "Password / Token (optional)" : "Password or app password", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text(service == .amphiServer
                         ? "Connect one self-hosted BelloBook / Amphi server to sync your notebooks, media vault, audio, and photos."
                         : "For Nextcloud, find the WebDAV address under Files → Settings, and create an app password under Personal settings → Security.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(service == .amphiServer ? "BelloBook Server" : "WebDAV Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Sign In") { Task { await signIn() } }
                            .disabled(server.isEmpty || (service == .webDAV && (username.isEmpty || password.isEmpty)))
                            .bold()
                    }
                }
            }
        }
    }

    private func signIn() async {
        working = true
        defer { working = false }
        do {
            if service == .amphiServer, let provider = sync.provider(for: .amphiServer) as? AmphiServerProvider {
                try await provider.signIn(server: server, username: username, password: password)
            } else if let provider = sync.provider(for: .webDAV) as? WebDAVProvider {
                try await provider.signIn(server: server, username: username, password: password)
            }
            dismiss()
            onSignedIn()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ServiceIcon: View {
    let service: CloudService

    var body: some View {
        Image(systemName: service.systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(service.tint, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SyncStatusText: View {
    @EnvironmentObject private var sync: SyncEngine

    var body: some View {
        switch sync.status {
        case .idle:
            Text("Not synced yet").foregroundStyle(.secondary).font(.footnote)
        case .syncing(let message):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(message).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        case .synced(let date):
            Text("Synced \(date.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary).font(.footnote)
        case .failed(let message):
            Text(message).foregroundStyle(.red).font(.footnote).lineLimit(2)
        }
    }
}

/// Toolbar button in the library that shows sync state at a glance.
struct SyncStatusButton: View {
    var action: () -> Void
    @EnvironmentObject private var sync: SyncEngine

    var body: some View {
        Button {
            if sync.connections.isEmpty { action() } else { Task { await sync.syncNow() } }
        } label: {
            switch sync.status {
            case .syncing:
                ProgressView()
            case .failed:
                Image(systemName: "exclamationmark.icloud").foregroundStyle(.red)
            default:
                ThemedIcon(.sync)
            }
        }
        .accessibilityLabel("Sync")
    }
}
