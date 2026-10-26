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
                        NotebookView(notebookID: id)
                    }
            }
        }
        .tint(Color.accentColor)
        .onChange(of: path) { _, path in
            withAnimation { columns = path.isEmpty ? .all : .detailOnly }
        }
        .onChange(of: selection) { _, _ in path = [] }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
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
    @ObservedObject private var theme = ThemeStore.shared
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
        .navigationTitle("Parchment")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { showSettings = true } label: {
                    Label { Text("Settings") } icon: { ThemedIcon(.settings, size: 20) }
                }
                Spacer()
                SyncStatusButton { showSettings = true }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
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

    private var dueCards: Int {
        let counts = study.counts(for: nil)
        return counts.due + counts.new
    }
}
