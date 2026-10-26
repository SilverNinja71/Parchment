import SwiftUI
import PencilKit

/// Page thumbnails down the left edge of the editor, like MyScript's page list.
struct PagesSidebar: View {
    let notebook: Notebook
    @Binding var selection: UUID?
    var onAddPage: (PageKind) -> Void
    @EnvironmentObject private var store: NotebookStore
    @ObservedObject private var editor: EditorModel

    init(notebook: Notebook, selection: Binding<UUID?>, editor: EditorModel, onAddPage: @escaping (PageKind) -> Void) {
        self.notebook = notebook
        self._selection = selection
        self.editor = editor
        self.onAddPage = onAddPage
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(Array(notebook.pages.enumerated()), id: \.element.id) { index, page in
                        Button {
                            selection = page.id
                        } label: {
                            VStack(spacing: 4) {
                                PageThumbnail(notebookID: notebook.id, page: page,
                                              revision: store.revisions[notebook.id, default: 0],
                                              pdf: editor.pdfDocument)
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(page.id == selection ? Color.accentColor : Color.black.opacity(0.12),
                                                      lineWidth: page.id == selection ? 2.5 : 1))
                                Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(page.id)
                        .contextMenu {
                            if notebook.pages.count > 1 {
                                Button(role: .destructive) {
                                    if selection == page.id {
                                        selection = notebook.pages[index == 0 ? 1 : index - 1].id
                                    }
                                    store.deletePage(page.id, from: notebook.id)
                                } label: { ThemedLabel("Delete Page", icon: .trash) }
                            }
                        }
                    }

                    Menu {
                        Button("Document Page") { onAddPage(.document) }
                        Button("Freeform Page") { onAddPage(.freeform) }
                    } label: {
                        ThemedIcon(.addPage, size: 26)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .accessibilityLabel("Add page")
                }
                .padding(14)
            }
            .onChange(of: selection) { _, id in
                withAnimation { proxy.scrollTo(id) }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

/// A small rendering of a page (paper color, PDF page and ink).
struct PageThumbnail: View {
    let notebookID: UUID
    let page: Page
    let revision: Int
    let pdf: CGPDFDocument?
    @EnvironmentObject private var store: NotebookStore
    @State private var image: UIImage?

    private let width: CGFloat = 130

    /// Which part of the page the thumbnail shows (top of tall pages).
    private var region: CGRect {
        switch page.kind {
        case .pdf: return CGRect(origin: .zero, size: page.size)
        case .document, .freeform: return CGRect(x: 0, y: 0, width: Page.documentWidth, height: Page.documentWidth * 1.3)
        }
    }

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .frame(width: width, height: width * region.height / region.width)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .task(id: "\(page.id)-\(revision)") {
            image = render()
        }
    }

    private func render() -> UIImage? {
        PageRenderer.image(of: page, in: notebookID, store: store, pdf: pdf, region: region, width: width)
    }
}
