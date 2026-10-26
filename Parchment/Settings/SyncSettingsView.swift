import SwiftUI
import UniformTypeIdentifiers

/// Settings → Sync. Pick a service, sign in, then choose any folder to keep your notes in.
struct SyncSettingsView: View {
    @EnvironmentObject private var sync: SyncEngine
    @Environment(\.webAuthenticationSession) private var webAuthentication

    @State private var folderPickerService: CloudService?
    @State private var browsing: CloudService?
    @State private var showWebDAVSignIn = false
    @State private var signingIn: CloudService?
    @State private var errorMessage: String?
    @State private var setupNeeded: CloudService?
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            if let connection = sync.connection {
                Section {
                    HStack(spacing: 14) {
                        ServiceIcon(service: connection.service)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.service.title).font(.headline)
                            Text(connection.accountName).font(.subheadline).foregroundStyle(.secondary)
                            Label(connection.folder.displayPath, systemImage: "folder")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

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
                    Button("Change Folder") { chooseFolder(for: connection.service) }
                    Button("Stop Syncing", role: .destructive) { confirmDisconnect = true }
                } header: {
                    Text("Syncing To")
                } footer: {
                    Text("Notebooks are saved as .parchment files you can open on any iPad with Parchment. Deleting a notebook here never deletes it from the cloud.")
                }
            }

            Section {
                ForEach(CloudService.allCases) { service in
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
                            } else if sync.connection?.service == service {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            } else {
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(signingIn != nil)
                }
            } header: {
                Text(sync.connection == nil ? "Choose Where to Sync" : "Switch To")
            } footer: {
                Text("Sign in, then pick any folder in your account. Parchment is free — syncing never needs a subscription.")
            }
        }
        .navigationTitle("Sync")
        .fileImporter(isPresented: Binding(get: { folderPickerService != nil }, set: { if !$0 { folderPickerService = nil } }),
                      allowedContentTypes: [.folder]) { result in
            guard let service = folderPickerService else { return }
            folderPickerService = nil
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
        .sheet(isPresented: $showWebDAVSignIn) {
            WebDAVSignInView { browsing = .webDAV }
        }
        .alert("Couldn't connect", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("\(setupNeeded?.title ?? "") needs an app ID", isPresented: Binding(get: { setupNeeded != nil }, set: { if !$0 { setupNeeded = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add your free \(setupNeeded?.title ?? "") developer app ID to CloudCredentials.swift, then rebuild. README.md walks you through it in a few minutes.")
        }
        .confirmationDialog("Stop syncing?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Stop and Sign Out", role: .destructive) { sync.disconnect(signOut: true) }
            Button("Stop but Stay Signed In") { sync.disconnect(signOut: false) }
        } message: {
            Text("Your notebooks stay on this iPad and in the cloud.")
        }
    }

    private func start(_ service: CloudService) {
        guard sync.isConfigured(service) else {
            setupNeeded = service
            return
        }
        let provider = sync.provider(for: service)
        switch service.signInStyle {
        case .folderPicker:
            folderPickerService = service
        case .webDAVForm:
            if provider.isSignedIn { browsing = service } else { showWebDAVSignIn = true }
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
                    Text("This folder already has \(notebookCount) Parchment notebook\(notebookCount == 1 ? "" : "s"). They'll be added to your library.")
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
                    newFolderName = "Parchment"
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

/// Server address, username and password for WebDAV servers such as Nextcloud.
struct WebDAVSignInView: View {
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
                    TextField("https://cloud.example.com/remote.php/dav/files/you/", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password or app password", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("For Nextcloud, find the WebDAV address under Files → Settings, and create an app password under Personal settings → Security.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("WebDAV Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Sign In") { Task { await signIn() } }
                            .disabled(server.isEmpty || username.isEmpty || password.isEmpty)
                            .bold()
                    }
                }
            }
        }
    }

    private func signIn() async {
        guard let provider = sync.provider(for: .webDAV) as? WebDAVProvider else { return }
        working = true
        defer { working = false }
        do {
            try await provider.signIn(server: server, username: username, password: password)
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
            if sync.connection == nil { action() } else { Task { await sync.syncNow() } }
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
