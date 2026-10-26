import Foundation
import Combine
import PencilKit

/// Makes handwriting searchable. Pages are read on the device with Vision, in the
/// background, a few seconds after you stop writing. The text is kept in a small
/// local index (it never leaves the iPad and isn't synced; each device builds its own).
@MainActor
final class HandwritingIndex: ObservableObject {
    static let shared = HandwritingIndex()

    struct PageText: Codable {
        var text: String
        var indexed: Date
    }

    struct Hit: Identifiable {
        let id = UUID()
        let notebookID: UUID
        let pageID: UUID
        let pageNumber: Int
        /// The words around the match.
        let snippet: String
        let handwritten: Bool
    }

    @Published private(set) var pages: [UUID: PageText] = [:]
    @Published private(set) var isIndexing = false

    private let store: NotebookStore
    private let fileURL: URL
    private var queue: [UUID] = []
    private var cancellables = Set<AnyCancellable>()

    init(store: NotebookStore? = nil) {
        self.store = store ?? .shared
        fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HandwritingIndex.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([UUID: PageText].self, from: data) {
            pages = saved
        }
        self.store.userDidEdit
            .debounce(for: .seconds(4), scheduler: RunLoop.main)
            .sink { [weak self] id in self?.enqueue([id]) }
            .store(in: &cancellables)
    }

    /// Catches up on anything written since the index was last updated.
    func indexEverything() {
        enqueue(store.notebooks.filter { $0.isPersonalizationKit != true }.map(\.id))
    }

    private func enqueue(_ ids: [UUID]) {
        queue.append(contentsOf: ids.filter { !queue.contains($0) })
        guard !isIndexing else { return }
        isIndexing = true
        Task { await processQueue() }
    }

    private func processQueue() async {
        while !queue.isEmpty {
            let id = queue.removeFirst()
            await index(id)
        }
        isIndexing = false
        save()
    }

    private func index(_ notebookID: UUID) async {
        guard let notebook = store.notebook(notebookID) else { return }
        let language = AppSettings.shared.recognitionLanguage
        for page in notebook.pages {
            let url = store.drawingURL(notebook: notebookID, page: page.id)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if let existing = pages[page.id], existing.indexed >= modified { continue }

            guard let data = try? Data(contentsOf: url), let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else {
                pages[page.id] = PageText(text: "", indexed: Date())
                continue
            }
            let text = await Self.read(drawing, language: language)
            pages[page.id] = PageText(text: text, indexed: Date())
        }
        save()
    }

    /// Reads a page in horizontal bands so small handwriting on long pages stays legible to Vision.
    private static func read(_ drawing: PKDrawing, language: String) async -> String {
        let bounds = drawing.bounds
        guard !bounds.isNull, !bounds.isEmpty else { return "" }
        let bandHeight: CGFloat = 600
        var lines: [String] = []
        var top = bounds.minY
        while top < bounds.maxY {
            let band = top..<(top + bandHeight)
            // Each stroke belongs to the band holding its middle, so nothing is read twice.
            let strokes = drawing.strokes.filter { stroke in
                stroke.ink.inkType != .marker && band.contains(stroke.renderBounds.midY)
            }
            if !strokes.isEmpty,
               let text = try? await HandwritingRecognizer.recognize(PKDrawing(strokes: strokes), language: language),
               !text.isEmpty {
                lines.append(text)
            }
            top += bandHeight
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Searching

    /// Finds `query` in handwriting and typed text across notebooks.
    func search(_ query: String, in notebooks: [Notebook]) -> [Hit] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return [] }
        var hits: [Hit] = []
        for notebook in notebooks where notebook.isPersonalizationKit != true {
            for (index, page) in notebook.pages.enumerated() {
                let typed = page.textBlocks.map(\.text).joined(separator: " ")
                if let snippet = Self.snippet(of: needle, in: typed) {
                    hits.append(Hit(notebookID: notebook.id, pageID: page.id, pageNumber: index + 1, snippet: snippet, handwritten: false))
                } else if let handwriting = pages[page.id]?.text, let snippet = Self.snippet(of: needle, in: handwriting) {
                    hits.append(Hit(notebookID: notebook.id, pageID: page.id, pageNumber: index + 1, snippet: snippet, handwritten: true))
                }
            }
        }
        return hits
    }

    private static func snippet(of needle: String, in text: String) -> String? {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = flat.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = flat.index(range.lowerBound, offsetBy: -40, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: 50, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }

    private func save() {
        // Forget pages that no longer exist.
        let live = Set(store.notebooks.flatMap(\.pages).map(\.id))
        pages = pages.filter { live.contains($0.key) }
        if let data = try? JSONEncoder().encode(pages) { try? data.write(to: fileURL, options: .atomic) }
    }
}
