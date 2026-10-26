import Foundation
import CoreGraphics
import UniformTypeIdentifiers

extension UTType {
    // The Xcode build declares these types in Info.plist. Swift Playgrounds builds can't,
    // so there we fall back to recognizing the file extension.
    static let parchmentNotebook = UTType("app.parchment.notebook")
        ?? UTType(filenameExtension: "parchment", conformingTo: .data) ?? .data
    static let parchmentKit = UTType("app.parchment.kit")
        ?? UTType(filenameExtension: "parchmentkit", conformingTo: .data) ?? .data
}

/// Opens files that arrive by AirDrop, the Files app, "Open in…" or the import button.
enum FileOpener {
    @MainActor
    static func open(_ url: URL, store: NotebookStore) throws -> Notebook {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
            // AirDropped files land in Documents/Inbox; we've copied what we need.
            if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent

        if ext == KitLayout.fileExtension || (ext == "pdf" && isPersonalizationKit(data)) {
            return try store.importPDF(data: data, title: "Personalization Kit", isPersonalizationKit: true)
        }
        if ext == NotebookArchive.fileExtension {
            let archive = try NotebookArchive.decode(data)
            // Never silently overwrite a notebook that's already here.
            let exists = store.notebook(archive.notebook.id) != nil
            return try store.importArchive(data, asCopy: exists, titleSuffix: exists ? "(copy)" : nil)
        }
        if ext == "pdf" {
            return try store.importPDF(data: data, title: title)
        }
        throw ParchmentError.invalidFile("Parchment can open PDFs, Parchment notebooks and Personalization Kits.")
    }

    /// Kit PDFs carry a keyword so they're recognized even when renamed to .pdf.
    static func isPersonalizationKit(_ data: Data) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), let info = document.info else { return false }
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(info, "Keywords", &value), let value,
              let keywords = CGPDFStringCopyTextString(value) as String? else { return false }
        return keywords.contains("ParchmentKit")
    }
}
