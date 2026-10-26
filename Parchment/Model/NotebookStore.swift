import Foundation
import Combine

/// Owns every notebook on the device.
///
/// Layout on disk (Application Support/Notebooks):
///
///     <notebook-id>/
///         notebook.json        – the `Notebook` manifest
///         pages/<page-id>.drawing – PencilKit drawing data, one file per page
///         source.pdf           – the imported PDF, if any
@MainActor
final class NotebookStore: ObservableObject {
    static let shared = NotebookStore()

    @Published private(set) var notebooks: [Notebook] = []
    @Published private var savedSubjects: [Subject] = []
    /// Bumped whenever a notebook's content changes, so thumbnails refresh.
    @Published private(set) var revisions: [UUID: Int] = [:]
    /// Fires with a notebook ID every time the user changes that notebook (drives auto-sync).
    let userDidEdit = PassthroughSubject<UUID, Never>()

    let root: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    init(root: URL? = nil) {
        let base = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notebooks", isDirectory: true)
        self.root = base
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        savedSubjects = UserDefaults.standard.data(forKey: Self.subjectsKey)
            .flatMap { try? JSONDecoder().decode([Subject].self, from: $0) } ?? []
        reload()
    }

    // MARK: - Subjects

    private static let subjectsKey = "library.subjects"

    /// Every subject: ones you made plus any found on notebooks (e.g. arriving by sync).
    var subjects: [Subject] {
        var all = savedSubjects
        for name in Set(notebooks.compactMap(\.subject)) where !all.contains(where: { $0.name == name }) {
            all.append(Subject(name: name, colorHex: Notebook.coverPalette[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Notebook.coverPalette.count]))
        }
        return all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func addSubject(_ name: String, colorHex: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !savedSubjects.contains(where: { $0.name == name }) else { return }
        savedSubjects.append(Subject(name: name, colorHex: colorHex))
        persistSubjects()
    }

    /// Removes a subject; its notebooks stay in the library, unfiled.
    func deleteSubject(_ name: String) {
        savedSubjects.removeAll { $0.name == name }
        persistSubjects()
        for notebook in notebooks where notebook.subject == name {
            update(notebook.id) { $0.subject = nil }
        }
    }

    func notebooks(in subject: String?) -> [Notebook] {
        guard let subject else { return notebooks }
        return notebooks.filter { $0.subject == subject }
    }

    private func persistSubjects() {
        UserDefaults.standard.set(try? JSONEncoder().encode(savedSubjects), forKey: Self.subjectsKey)
    }

    // MARK: - Paths

    func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func pdfURL(for id: UUID) -> URL { folder(for: id).appendingPathComponent("source.pdf") }
    private func coverImageURL(for id: UUID) -> URL { folder(for: id).appendingPathComponent("cover.jpg") }

    // MARK: - Cover photos

    func coverImageData(for id: UUID) -> Data? { try? Data(contentsOf: coverImageURL(for: id)) }

    /// Saves (or removes, with nil) a notebook's imported cover image.
    func setCoverImageData(_ data: Data?, for id: UUID) {
        if let data {
            try? data.write(to: coverImageURL(for: id), options: .atomic)
        } else {
            try? fileManager.removeItem(at: coverImageURL(for: id))
        }
        update(id) { $0.hasCoverImage = data != nil }
    }
    private func manifestURL(for id: UUID) -> URL { folder(for: id).appendingPathComponent("notebook.json") }
    private func pagesFolder(for id: UUID) -> URL { folder(for: id).appendingPathComponent("pages", isDirectory: true) }
    func drawingURL(notebook: UUID, page: UUID) -> URL {
        pagesFolder(for: notebook).appendingPathComponent("\(page.uuidString).drawing")
    }

    // MARK: - Reading

    func reload() {
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        notebooks = folders
            .compactMap { folder -> Notebook? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("notebook.json")) else { return nil }
                return try? decoder.decode(Notebook.self, from: data)
            }
            .sorted { $0.modified > $1.modified }
    }

    func notebook(_ id: UUID) -> Notebook? { notebooks.first { $0.id == id } }

    func loadDrawing(notebook: UUID, page: UUID) -> Data? {
        try? Data(contentsOf: drawingURL(notebook: notebook, page: page))
    }

    // MARK: - Writing

    @discardableResult
    func createNotebook(title: String, kind: PageKind = .document, paper: PaperStyle = .ruled,
                        coverColor: String = Notebook.coverPalette[0], customCover: Int? = nil,
                        subject: String? = nil) -> Notebook {
        let page = kind == .freeform ? Page.newFreeform(paper: paper) : Page.newDocument(paper: paper)
        var notebook = Notebook(title: title, pages: [page])
        notebook.subject = subject
        notebook.coverColor = coverColor
        notebook.customCover = customCover
        write(notebook)
        return notebook
    }

    /// Saves the manifest. `touch` marks it as edited by the user (updates `modified`, triggers sync).
    func save(_ notebook: Notebook, touch: Bool = true) {
        var notebook = notebook
        if touch { notebook.modified = Date() }
        write(notebook)
        if touch { userDidEdit.send(notebook.id) }
    }

    /// Changes a notebook in place and saves it.
    func update(_ id: UUID, touch: Bool = true, _ change: (inout Notebook) -> Void) {
        guard var notebook = notebook(id) else { return }
        change(&notebook)
        save(notebook, touch: touch)
    }

    func updatePage(_ pageID: UUID, in id: UUID, touch: Bool = true, _ change: (inout Page) -> Void) {
        update(id, touch: touch) { notebook in
            guard let index = notebook.pages.firstIndex(where: { $0.id == pageID }) else { return }
            change(&notebook.pages[index])
        }
    }

    func saveDrawing(_ data: Data, notebook id: UUID, page: UUID) {
        try? fileManager.createDirectory(at: pagesFolder(for: id), withIntermediateDirectories: true)
        try? data.write(to: drawingURL(notebook: id, page: page), options: .atomic)
        if let notebook = notebook(id) { save(notebook) }
    }

    func delete(_ id: UUID) {
        try? fileManager.removeItem(at: folder(for: id))
        notebooks.removeAll { $0.id == id }
    }

    func deletePage(_ pageID: UUID, from notebookID: UUID) {
        guard var notebook = notebook(notebookID), notebook.pages.count > 1 else { return }
        notebook.pages.removeAll { $0.id == pageID }
        try? fileManager.removeItem(at: drawingURL(notebook: notebookID, page: pageID))
        save(notebook)
    }

    private func write(_ notebook: Notebook) {
        try? fileManager.createDirectory(at: pagesFolder(for: notebook.id), withIntermediateDirectories: true)
        if let data = try? encoder.encode(notebook) {
            try? data.write(to: manifestURL(for: notebook.id), options: .atomic)
        }
        if let index = notebooks.firstIndex(where: { $0.id == notebook.id }) {
            notebooks[index] = notebook
        } else {
            notebooks.append(notebook)
        }
        notebooks.sort { $0.modified > $1.modified }
        revisions[notebook.id, default: 0] += 1
    }

    /// Stores a PDF for a notebook (used by PDF import and the personalization kit).
    func attachPDF(_ data: Data, to id: UUID) throws {
        try fileManager.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
        try data.write(to: pdfURL(for: id), options: .atomic)
    }

    // MARK: - Single-file archives (share, AirDrop, sync)

    func archive(_ id: UUID) throws -> Data {
        guard let notebook = notebook(id) else { throw ParchmentError.notFound("Notebook not found.") }
        var drawings: [String: Data] = [:]
        for page in notebook.pages {
            if let data = loadDrawing(notebook: id, page: page.id) { drawings[page.id.uuidString] = data }
        }
        let pdf = notebook.hasPDF ? try? Data(contentsOf: pdfURL(for: id)) : nil
        var archive = NotebookArchive(notebook: notebook, drawings: drawings, pdf: pdf)
        archive.coverImage = notebook.hasCoverImage == true ? coverImageData(for: id) : nil
        return try archive.encoded()
    }

    /// Unpacks an archive. With `asCopy` the notebook gets a new identity instead of
    /// replacing a local notebook that has the same ID.
    @discardableResult
    func importArchive(_ data: Data, asCopy: Bool = false, titleSuffix: String? = nil) throws -> Notebook {
        let archive = try NotebookArchive.decode(data)
        var notebook = archive.notebook
        if asCopy { notebook.id = UUID() }
        if let titleSuffix { notebook.title += " \(titleSuffix)" }

        try? fileManager.removeItem(at: folder(for: notebook.id))
        try fileManager.createDirectory(at: pagesFolder(for: notebook.id), withIntermediateDirectories: true)
        for (pageID, drawing) in archive.drawings {
            guard let uuid = UUID(uuidString: pageID) else { continue }
            try drawing.write(to: drawingURL(notebook: notebook.id, page: uuid), options: .atomic)
        }
        if let pdf = archive.pdf { try attachPDF(pdf, to: notebook.id) }
        if let cover = archive.coverImage { try cover.write(to: coverImageURL(for: notebook.id), options: .atomic) }
        write(notebook)
        return notebook
    }

    func archiveFileName(for notebook: Notebook) -> String {
        "\(Self.safeFileName(notebook.title)).\(NotebookArchive.fileExtension)"
    }

    static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.newlines)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(80))
    }
}
