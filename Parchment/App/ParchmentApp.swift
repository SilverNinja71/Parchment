import SwiftUI

@main
struct ParchmentApp: App {
    @StateObject private var store = NotebookStore.shared
    @StateObject private var sync = SyncEngine.shared
    @StateObject private var study = StudyStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(sync)
                .environmentObject(study)
        }
    }
}

enum SidebarItem: Hashable {
    case allNotes
    case folder(String)
    case subject(String)
    case flashcards
    case recall
}

/// Notability-style layout: a sidebar of notes, subjects and study tools, with the
/// sidebar sliding away while you write.
struct RootView: View {
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var sync: SyncEngine
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarItem? = .allNotes
    @State private var path: [UUID] = []
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var showSettings = false
    @State private var showCommandPalette = false
    @State private var openError: String?
    @AppStorage("hasSeededTutorial") private var seededTutorial = false
    @AppStorage("hasCompletedTutorial") private var completedTutorial = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(selection: $selection, showSettings: $showSettings)
        } detail: {
            NavigationStack(path: $path) {
                detail
                    .navigationDestination(for: UUID.self) { id in
                        // A [[wiki-link]] in the Textbook view opens the notebook it names.
                        NotebookView(notebookID: id) { linked in path = [linked] }
                    }
            }
        }
        .tint(Color.accentColor)
        .onChange(of: path, initial: true) { _, path in
            withAnimation { columns = path.isEmpty ? .all : .detailOnly }
        }
        .onChange(of: selection) { _, _ in path = [] }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                onOpenNotebook: { id in
                    selection = .allNotes
                    path = [id]
                },
                onSelectSidebar: { item in
                    selection = item
                    path = []
                },
                onOpenSettings: {
                    showSettings = true
                }
            )
        }
        .background {
            Button("") { showCommandPalette = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
        .onAppear {
            // Catch up on reading handwriting for search, a moment after launch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { HandwritingIndex.shared.indexEverything() }
            // First arrival: add the hands-on welcome notebook and open it.
            guard !seededTutorial else { return }
            seededTutorial = true
            let tutorial = store.createTutorialNotebook()
            if !completedTutorial { path = [tutorial.id] }
        }
        .onOpenURL { url in
            do {
                let notebook = try FileOpener.open(url, store: store)
                selection = .allNotes
                path = [notebook.id]
            } catch {
                openError = error.localizedDescription
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pull changes when you come back, push them when you leave.
            if phase == .active || phase == .background {
                sync.syncIfAutomatic()
            }
        }
        .alert("Couldn't open file", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .allNotes {
        case .allNotes:
            LibraryView(path: $path)
        case .folder(let folder):
            LibraryView(path: $path, folderPath: folder).id("folder:" + folder)
        case .subject(let name):
            LibraryView(path: $path, subject: name).id(name)
        case .flashcards:
            FlashcardsHomeView()
        case .recall:
            RecallHomeView()
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Binding var showSettings: Bool
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var study: StudyStore
    @EnvironmentObject private var sync: SyncEngine
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showAccount = false
    @State private var addingSubject = false
    @State private var newSubject = ""
    @State private var deleting: Subject?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label { Text("All Notes") } icon: { ThemedIcon(.allNotes, size: 20) }
                    .badge(store.notebooks.count)
                    .tag(SidebarItem.allNotes)
            }

            if !uniqueFolders.isEmpty {
                Section("Folders") {
                    ForEach(uniqueFolders, id: \.self) { folder in
                        Label {
                            Text(folder)
                        } icon: {
                            Image(systemName: "folder").foregroundStyle(Style.accent)
                        }
                        .badge(store.notebooks.filter { ($0.folderPath ?? "") == folder || ($0.folderPath ?? "").hasPrefix(folder + "/") }.count)
                        .tag(SidebarItem.folder(folder))
                    }
                }
            }

            Section("Subjects") {
                ForEach(store.subjects) { subject in
                    Label {
                        HandwrittenText(subject.name, size: 16, weight: .regular)
                    } icon: {
                        Circle().fill(Color(hex: subject.colorHex)).frame(width: 14, height: 14)
                    }
                    .badge(store.notebooks(in: subject.name).count)
                    .tag(SidebarItem.subject(subject.name))
                    .contextMenu {
                        Button("Delete Subject", role: .destructive) { deleting = subject }
                    }
                }
                Button {
                    newSubject = ""
                    addingSubject = true
                } label: {
                    Label("New Subject", systemImage: "plus")
                }
            }

            Section("Study") {
                Label { Text("Flashcards") } icon: { ThemedIcon(.flashcards, size: 20) }
                    .badge(dueCards)
                    .tag(SidebarItem.flashcards)
                Label { Text("Recall Practice") } icon: { ThemedIcon(.recall, size: 20) }
                    .tag(SidebarItem.recall)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("BelloBook")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if sync.connections.isEmpty {
                    Button { showAccount = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.icloud").font(.title3).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Not backed up").font(.subheadline.bold()).foregroundStyle(.primary)
                                Text("Sign in to keep your work safe").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Style.controlRadius))
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Button { showSettings = true } label: {
                        Label { Text("Settings") } icon: { ThemedIcon(.settings, size: 20) }
                    }
                    Spacer()
                    SyncStatusButton { showAccount = true }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .sheet(isPresented: $showAccount) {
            NavigationStack {
                SyncSettingsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAccount = false } } }
            }
        }
        .alert("New Subject", isPresented: $addingSubject) {
            TextField("e.g. Biology", text: $newSubject)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let color = Notebook.coverPalette[store.subjects.count % Notebook.coverPalette.count]
                store.addSubject(newSubject, colorHex: color)
            }
        }
        .confirmationDialog("Delete the subject \"\(deleting?.name ?? "")\"?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Subject", role: .destructive) {
                if let subject = deleting {
                    if selection == .subject(subject.name) { selection = .allNotes }
                    store.deleteSubject(subject.name)
                }
            }
        } message: {
            Text("Its notebooks stay in All Notes.")
        }
    }

    private var uniqueFolders: [String] {
        let paths = store.notebooks.compactMap(\.folderPath).filter { !$0.isEmpty }
        return Array(Set(paths)).sorted()
    }

    private var dueCards: Int {
        let counts = study.counts(for: nil)
        return counts.due + counts.new
    }
}
