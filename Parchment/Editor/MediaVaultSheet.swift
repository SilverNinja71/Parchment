import SwiftUI
import UniformTypeIdentifiers
import PDFKit

/// Page Media Vault, Photo Browser, Quick File Previewer, and Audio Metadata Editor
/// (Amphi Notes / Music / Cloud / Photos parity) styled with `Style.swift`.
struct MediaVaultSheet: View {
    let notebookID: UUID
    let pageID: UUID

    @EnvironmentObject private var store: NotebookStore
    @ObservedObject private var deck = AudioDeck.shared
    @Environment(\.dismiss) private var dismiss

    @State private var importing = false
    @State private var filterKind: MediaKind? = nil
    @State private var previewing: MediaAttachment? = nil
    @State private var editingAudio: MediaAttachment? = nil
    @State private var errorMessage: String? = nil

    private var attachments: [MediaAttachment] {
        guard let nb = store.notebook(notebookID),
              let page = nb.pages.first(where: { $0.id == pageID }) else { return [] }
        let all = page.attachments ?? []
        if let filterKind { return all.filter { $0.kind == filterKind } }
        return all
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filterKind) {
                    Text("All").tag(MediaKind?.none)
                    ForEach(MediaKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(MediaKind?.some(kind))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                if attachments.isEmpty {
                    ContentUnavailableView {
                        Label("Media & File Vault", systemImage: "tray.full")
                    } description: {
                        Text("Attach photos, audio tracks, voice notes, videos, or documents to this page. Everything stays private on your device and syncs with your server.")
                    } actions: {
                        Button("Attach File, Photo, or Audio") { importing = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Style.accent)
                    }
                } else {
                    List {
                        ForEach(attachments) { item in
                            attachmentRow(item)
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Media & File Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { importing = true } label: {
                        Label("Attach", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .sheet(item: $previewing) { item in
                QuickAttachmentPreviewSheet(notebookID: notebookID, attachment: item)
            }
            .sheet(item: $editingAudio) { item in
                AudioMetadataSheet(attachment: item) { updated in
                    store.updatePage(pageID, in: notebookID) { page in
                        var list = page.attachments ?? []
                        if let idx = list.firstIndex(where: { $0.id == updated.id }) {
                            list[idx] = updated
                            page.attachments = list
                        }
                    }
                    deck.updateMetadata(id: updated.id, title: updated.title, artist: updated.artist, album: updated.album)
                }
            }
            .alert("Couldn't attach file", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .wideSheet()
    }

    @ViewBuilder
    private func attachmentRow(_ item: MediaAttachment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.systemImage)
                .font(.title3)
                .foregroundStyle(Style.accent)
                .frame(width: 36, height: 36)
                .background(Style.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Style.controlRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !item.artist.isEmpty {
                        Text(item.artist)
                    }
                    if item.byteCount > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if item.kind == .audio {
                Button {
                    deck.play(attachment: item, notebookID: notebookID)
                } label: {
                    Image(systemName: deck.currentItem?.id == item.id && deck.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Style.accent)
                }
                .buttonStyle(.plain)

                Button {
                    editingAudio = item
                } label: {
                    Image(systemName: "tag")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Preview") {
                    previewing = item
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Style.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            for url in urls {
                let attachment = try MediaVault.shared.importFile(from: url, into: notebookID)
                store.updatePage(pageID, in: notebookID) { page in
                    var list = page.attachments ?? []
                    list.append(attachment)
                    page.attachments = list
                }
            }
            Style.tap()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        let toDelete = offsets.map { attachments[$0] }
        for item in toDelete {
            MediaVault.shared.remove(item, from: notebookID)
            store.updatePage(pageID, in: notebookID) { page in
                page.attachments?.removeAll { $0.id == item.id }
            }
        }
    }
}

/// Built-in Quick Preview for Images, PDFs, and Text/Markdown (Amphi Cloud parity).
private struct QuickAttachmentPreviewSheet: View {
    let notebookID: UUID
    let attachment: MediaAttachment
    @Environment(\.dismiss) private var dismiss

    private var url: URL { MediaVault.shared.fileURL(for: attachment, in: notebookID) }

    var body: some View {
        NavigationStack {
            Group {
                if attachment.kind == .image, let uiImage = UIImage(contentsOfFile: url.path) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                    .background(Color.paper)
                } else if url.pathExtension.lowercased() == "pdf", let pdfDoc = PDFDocument(url: url) {
                    PDFKitPreviewView(document: pdfDoc)
                } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                    ScrollView {
                        Text(text)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color.paper)
                } else {
                    ContentUnavailableView(
                        attachment.title,
                        systemImage: attachment.kind.systemImage,
                        description: Text("File stored in BelloBook Media Vault (\(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))).")
                    )
                }
            }
            .navigationTitle(attachment.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PDFKitPreviewView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}

private struct AudioMetadataSheet: View {
    @State var attachment: MediaAttachment
    var onSave: (MediaAttachment) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Track Metadata") {
                    TextField("Title", text: $attachment.title)
                    TextField("Artist", text: $attachment.artist)
                    TextField("Album", text: $attachment.album)
                }
                Section("Notes") {
                    TextEditor(text: $attachment.notes)
                        .frame(minHeight: 90)
                }
            }
            .navigationTitle("Audio Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(attachment)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
