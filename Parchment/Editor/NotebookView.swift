import SwiftUI

/// The notebook editor: top bar, tool palette, page list and the writing canvas.
struct NotebookView: View {
    let notebookID: UUID

    @EnvironmentObject private var store: NotebookStore
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var editor: EditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentPageID: UUID?
    @State private var showPages = true
    @State private var editingBlock: TextBlock?
    @State private var shareItem: ShareItem?
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var message: String?
    @State private var practicing = false
    @State private var customizingCover = false
    @State private var choosingPaper = false
    @AppStorage("hasCompletedTutorial") private var tutorialDone = false

    init(notebookID: UUID) {
        self.notebookID = notebookID
        // Open the PDF up front so the first page and thumbnails render with it.
        _editor = StateObject(wrappedValue: EditorModel(pdfDocument: NotebookStore.shared.pdfDocument(for: notebookID)))
    }

    private var notebook: Notebook? { store.notebook(notebookID) }

    private var currentPage: Page? {
        guard let notebook else { return nil }
        return notebook.pages.first { $0.id == currentPageID } ?? notebook.pages.first
    }

    var body: some View {
        Group {
            if let notebook, let page = currentPage {
                VStack(spacing: 0) {
                    topBar(notebook)
                    if notebook.isPersonalizationKit { kitBanner(notebook) }
                    Divider()
                    HStack(spacing: 0) {
                        if showPages {
                            PagesSidebar(notebook: notebook, selection: $currentPageID, editor: editor) { kind in
                                addPage(kind, to: notebook)
                            }
                            .frame(width: 160)
                            Divider()
                        }
                        PageCanvas(notebookID: notebook.id, page: page, editor: editor, settings: settings) { block in
                            editingBlock = block
                        }
                        .ignoresSafeArea(.container, edges: .bottom)
                        // Notability-style floating tool palette.
                        .overlay(alignment: .top) {
                            EditorToolbar(editor: editor).padding(.top, 12)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Notebook not found", systemImage: "book.closed")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if currentPageID == nil { currentPageID = notebook?.pages.first?.id }
        }
        .onDisappear { editor.canvas?.saveNow() }
        .sheet(item: $editor.conversion) { request in
            ConvertSheet(request: request) { editor.applyConversion($0) }
        }
        .sheet(item: $editingBlock) { block in
            TextBlockEditor(block: block) { updated in
                guard let page = currentPage else { return }
                store.updatePage(page.id, in: notebookID) { page in
                    if let index = page.textBlocks.firstIndex(where: { $0.id == updated.id }) {
                        page.textBlocks[index] = updated
                    }
                }
            } onDelete: {
                guard let page = currentPage else { return }
                store.updatePage(page.id, in: notebookID) { $0.textBlocks.removeAll { $0.id == block.id } }
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $customizingCover) {
            CoverStudioSheet(notebookID: notebookID)
        }
        .sheet(isPresented: $choosingPaper) {
            if let page = currentPage {
                NavigationStack {
                    PaperStylePicker(selection: Binding(
                        get: { page.paper },
                        set: { paper in store.updatePage(page.id, in: notebookID) { $0.paper = paper } }), columns: 5)
                        .padding(24)
                        .navigationTitle("Paper Style")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { choosingPaper = false }.bold() } }
                }
                .presentationDetents([.height(320)])
                .presentationCornerRadius(Style.sheetRadius)
            }
        }
        .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
            if let notebook, notebook.isTutorial == true, !tutorialDone, let page = currentPage,
               let index = notebook.pages.firstIndex(of: page) {
                let step = TutorialStep.all[min(index, TutorialStep.all.count - 1)]
                TutorialOverlay(anchors: anchors, step: step, isLast: index >= notebook.pages.count - 1) {
                    withAnimation(Style.spring) { currentPageID = notebook.pages[min(index + 1, notebook.pages.count - 1)].id }
                } onFinish: {
                    withAnimation { tutorialDone = true }
                }
                .id(index)
            }
        }
        .sheet(isPresented: $practicing) {
            NavigationStack {
                RecallSetupView(title: notebook?.title ?? "Notebook", notebookIDs: [notebookID], startPageID: currentPage?.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { practicing = false } }
                    }
            }
        }
        .alert("Rename Notebook", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let title = newTitle.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { store.update(notebookID) { $0.title = title } }
            }
        }
        .overlay {
            if editor.isRecognizing {
                ProgressView("Reading your handwriting…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Top bar

    private func topBar(_ notebook: Notebook) -> some View {
        HStack(spacing: 4) {
            Button {
                editor.canvas?.saveNow()
                dismiss()
            } label: {
                ThemedIcon(.library).frame(width: 44, height: 40)
            }
            .accessibilityLabel("Library")

            Button {
                withAnimation(.snappy) { showPages.toggle() }
            } label: {
                ThemedIcon(.pages).frame(width: 44, height: 40)
            }
            .accessibilityLabel("Pages")

            Spacer()

            Button {
                editor.canvas?.saveNow()
                practicing = true
            } label: {
                Label { Text("Practice") } icon: { ThemedIcon(.recall, size: 20) }
                    .font(.subheadline.bold())
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Study this notebook with active recall")

            Button { customizingCover = true } label: {
                Image(systemName: "paintpalette").font(.system(size: 19)).frame(width: 44, height: 40)
            }
            .accessibilityLabel("Customize cover")
            .tutorialAnchor(.cover)

            Button(action: editor.undo) { ThemedIcon(.undo).frame(width: 44, height: 40) }
                .disabled(!editor.canUndo)
                .accessibilityLabel("Undo")
            Button(action: editor.redo) { ThemedIcon(.redo).frame(width: 44, height: 40) }
                .disabled(!editor.canRedo)
                .accessibilityLabel("Redo")

            Menu {
                Button("Document Page") { addPage(.document, to: notebook) }
                Button("Freeform Page") { addPage(.freeform, to: notebook) }
            } label: {
                ThemedIcon(.addPage).frame(width: 44, height: 40)
            }
            .accessibilityLabel("Add page")

            Menu {
                Button { share(notebook, asPDF: false) } label: { ThemedLabel("Share Notebook", icon: .share) }
                Button { share(notebook, asPDF: true) } label: { Label("Export as PDF", systemImage: "doc.richtext") }
                if let page = currentPage, page.kind != .pdf {
                    Button { choosingPaper = true } label: { Label("Paper Style…", systemImage: "square.grid.3x3") }
                }
                Button { customizingCover = true } label: { Label("Customize Cover…", systemImage: "paintpalette") }
                Toggle("Draw with Finger", isOn: $settings.fingerDraws)
                Divider()
                Button {
                    newTitle = notebook.title
                    renaming = true
                } label: { Label("Rename", systemImage: "pencil") }
                if notebook.pages.count > 1, let page = currentPage {
                    Button(role: .destructive) {
                        let index = notebook.pages.firstIndex(of: page) ?? 0
                        currentPageID = notebook.pages[index == 0 ? 1 : index - 1].id
                        store.deletePage(page.id, from: notebookID)
                    } label: { ThemedLabel("Delete Page", icon: .trash) }
                }
            } label: {
                ThemedIcon(.more).frame(width: 44, height: 40)
            }
            .tutorialAnchor(.more)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay {
            // Title centered like Notability and MyScript.
            Button {
                newTitle = notebook.title
                renaming = true
            } label: {
                HandwrittenText(notebook.title, size: 20)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: 360)
            }
            .accessibilityHint("Rename notebook")
        }
        .background(.bar)
    }

    private func kitBanner(_ notebook: Notebook) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "paintbrush.pointed")
            Text("Draw in each box with your Apple Pencil, then apply. You can come back and change it any time.")
                .font(.subheadline)
            Spacer()
            Button("Apply to Parchment") { applyKit(notebook) }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.12))
    }

    // MARK: - Actions

    private func addPage(_ kind: PageKind, to notebook: Notebook) {
        let page = kind == .freeform ? Page.newFreeform() : Page.newDocument(paper: settings.defaultPaper)
        store.update(notebook.id) { notebook in
            let index = notebook.pages.firstIndex { $0.id == currentPage?.id } ?? notebook.pages.count - 1
            notebook.pages.insert(page, at: index + 1)
        }
        currentPageID = page.id
    }

    private func share(_ notebook: Notebook, asPDF: Bool) {
        editor.canvas?.saveNow()
        do {
            if asPDF {
                shareItem = ShareItem(url: try store.exportPDF(notebook.id))
            } else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(store.archiveFileName(for: notebook))
                try store.archive(notebook.id).write(to: url, options: .atomic)
                shareItem = ShareItem(url: url)
            }
        } catch {
            show(error.localizedDescription)
        }
    }

    private func applyKit(_ notebook: Notebook) {
        editor.canvas?.saveNow()
        let extracted = KitExtractor.extract(from: notebook, store: store)
        ThemeStore.shared.apply(extracted)
        show(extracted.isEmpty
             ? "Nothing drawn yet — draw inside the boxes first."
             : "Applied \(extracted.count) drawings. Parchment is now yours ✨")
    }

    private func show(_ text: String) {
        withAnimation { message = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { if message == text { message = nil } }
        }
    }
}
