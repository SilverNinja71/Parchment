import SwiftUI
import UniformTypeIdentifiers

/// The home screen: every notebook as a cover, like MyScript's library.
struct LibraryView: View {
    @Binding var path: [UUID]
    /// Show one subject's notebooks, or everything when nil.
    var subject: String? = nil
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var sync: SyncEngine
    @ObservedObject private var theme = ThemeStore.shared

    @State private var showNewNotebook = false
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var search = ""
    @State private var errorMessage: String?
    @State private var shareItem: ShareItem?
    @State private var renameTarget: Notebook?
    @State private var coverTarget: Notebook?
    @State private var deleteTarget: Notebook?
    @State private var newTitle = ""

    private var notebooks: [Notebook] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let base = store.notebooks(in: subject)
        guard !query.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if store.notebooks(in: subject).isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 28)], spacing: 32) {
                        ForEach(notebooks) { notebook in
                            NavigationLink(value: notebook.id) {
                                NotebookCard(notebook: notebook)
                            }
                            .buttonStyle(.plain)
                            // Quick "edit cover" button on every card.
                            .overlay(alignment: .topTrailing) {
                                Button { coverTarget = notebook } label: {
                                    Image(systemName: "paintpalette")
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 30, height: 30)
                                        .background(.regularMaterial, in: Circle())
                                        .ambientShadow()
                                }
                                .buttonStyle(.plain)
                                .hoverEffect(.highlight)
                                .padding(8)
                                .accessibilityLabel("Customize cover")
                            }
                            .contextMenu { menu(for: notebook) }
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Color.chrome)
        .searchable(text: $search, prompt: "Search notebooks")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SyncStatusButton { showSettings = true }
                Button { showImporter = true } label: { ThemedIcon(.importPDF) }
                    .accessibilityLabel("Import PDF")
                Button { showSettings = true } label: { ThemedIcon(.settings) }
                    .accessibilityLabel("Settings")
                Button { showNewNotebook = true } label: { ThemedIcon(.newNotebook) }
                    .accessibilityLabel("New notebook")
            }
        }
        .sheet(isPresented: $showNewNotebook) {
            NewNotebookSheet(subject: subject) { notebook in path.append(notebook.id) }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(item: $coverTarget) { notebook in
            CoverStudioSheet(notebookID: notebook.id)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .parchmentNotebook, .parchmentKit],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                var opened: Notebook?
                for url in urls {
                    do { opened = try FileOpener.open(url, store: store) } catch { errorMessage = error.localizedDescription }
                }
                if urls.count == 1, let opened { path.append(opened.id) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Rename Notebook", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let title = newTitle.trimmingCharacters(in: .whitespaces)
                if let id = renameTarget?.id, !title.isEmpty { store.update(id) { $0.title = title } }
            }
        }
        .confirmationDialog("Delete \"\(deleteTarget?.title ?? "")\"?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete Notebook", role: .destructive) {
                if let id = deleteTarget?.id { store.delete(id) }
            }
        } message: {
            Text("This removes it from this iPad. Copies already synced to the cloud are kept.")
        }
    }

    @ViewBuilder
    private var header: some View {
        if let subject {
            HStack(spacing: 14) {
                Circle().fill(Color(hex: store.subjects.first { $0.name == subject }?.colorHex ?? "8B4A2E"))
                    .frame(width: 18, height: 18)
                HandwrittenText(subject, size: 38, weight: .bold)
                Spacer()
            }
        } else {
            wordmarkHeader
        }
    }

    private var wordmarkHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            // The logo always keeps its own colors.
            Image(uiImage: theme.logoOrStandard)
                .resizable().scaledToFit().frame(height: 56)
            if let wordmark = theme.wordmark {
                Image(uiImage: wordmark).renderingMode(theme.keepInkColors ? .original : .template)
                    .resizable().scaledToFit().frame(height: 64)
                    .accessibilityLabel("Parchment")
            } else {
                Text("Parchment").font(.system(size: 40, weight: .bold, design: .serif))
            }
            Spacer()
        }
        .foregroundStyle(Color.accentColor)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            if let doodle = theme.emptyLibraryDoodle {
                Image(uiImage: doodle).resizable().scaledToFit().frame(maxHeight: 160)
            } else {
                Image(systemName: "book.closed").font(.system(size: 64)).foregroundStyle(.secondary)
            }
            Text("No notebooks yet").font(.title2.bold())
            Text("Create a notebook to start writing, or import a PDF to annotate it.")
                .foregroundStyle(.secondary)
            HStack {
                Button { showNewNotebook = true } label: { ThemedLabel("New Notebook", icon: .newNotebook) }
                    .buttonStyle(.borderedProminent)
                Button { showImporter = true } label: { ThemedLabel("Import PDF", icon: .importPDF) }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    @ViewBuilder
    private func menu(for notebook: Notebook) -> some View {
        Button {
            newTitle = notebook.title
            renameTarget = notebook
        } label: { Label("Rename", systemImage: "pencil") }
        Button { coverTarget = notebook } label: { Label("Customize Cover", systemImage: "paintpalette") }
        Menu {
            Button("None") { store.update(notebook.id) { $0.subject = nil } }
            ForEach(store.subjects) { subject in
                Button(subject.name) { store.update(notebook.id) { $0.subject = subject.name } }
            }
        } label: { ThemedLabel("Move to Subject", icon: .subjects) }
        Button {
            do {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(store.archiveFileName(for: notebook))
                try store.archive(notebook.id).write(to: url, options: .atomic)
                shareItem = ShareItem(url: url)
            } catch { errorMessage = error.localizedDescription }
        } label: { ThemedLabel("Share", icon: .share) }
        Button {
            do { shareItem = ShareItem(url: try store.exportPDF(notebook.id)) } catch { errorMessage = error.localizedDescription }
        } label: { Label("Export as PDF", systemImage: "doc.richtext") }
        Divider()
        Button(role: .destructive) { deleteTarget = notebook } label: { ThemedLabel("Delete", icon: .trash) }
    }
}

struct NotebookCard: View {
    let notebook: Notebook
    @EnvironmentObject private var store: NotebookStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotebookCoverView(appearance: CoverAppearance(notebook: notebook, store: store), title: notebook.title)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4,
                                                  bottomTrailingRadius: Style.cardRadius, topTrailingRadius: Style.cardRadius))
                .ambientShadow()
                .overlay(alignment: .bottomTrailing) {
                    if notebook.isPersonalizationKit {
                        badge("Kit", systemImage: "paintbrush.pointed")
                    } else if notebook.hasPDF {
                        badge("PDF", systemImage: "doc.richtext")
                    }
                }
            HandwrittenText(notebook.title, size: 17)
                .foregroundStyle(.primary)
            Text("\(notebook.pages.count) page\(notebook.pages.count == 1 ? "" : "s") · \(notebook.modified.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func badge(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
    }
}
