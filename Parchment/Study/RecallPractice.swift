import SwiftUI
import PencilKit

struct RecallItem: Hashable {
    let notebookID: UUID
    let pageID: UUID
}

/// Study → Recall Practice: choose a subject or notebook to practice.
struct RecallHomeView: View {
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var study: StudyStore

    private var notebooks: [Notebook] { store.notebooks.filter { !$0.isPersonalizationKit } }

    var body: some View {
        List {
            Section {
                StudyHeader(
                    title: "Recall Practice",
                    message: "Look at a page, hide it, rewrite it from memory, then compare. Pulling information out of your head is what makes it stick.",
                    icon: .recall)
            }

            if notebooks.isEmpty {
                Text("Write some notes first, then come back to practice them.").foregroundStyle(.secondary)
            }

            let subjects = store.subjects.filter { !store.notebooks(in: $0.name).isEmpty }
            if !subjects.isEmpty {
                Section("Subjects") {
                    ForEach(subjects) { subject in
                        let ids = store.notebooks(in: subject.name).map(\.id)
                        NavigationLink {
                            RecallSetupView(title: subject.name, notebookIDs: ids)
                        } label: {
                            row(title: subject.name, color: subject.colorHex, notebookIDs: ids)
                        }
                    }
                }
            }

            Section("Notebooks") {
                ForEach(notebooks) { notebook in
                    NavigationLink {
                        RecallSetupView(title: notebook.title, notebookIDs: [notebook.id])
                    } label: {
                        row(title: notebook.title, color: notebook.coverColor, notebookIDs: [notebook.id])
                    }
                }
            }
        }
        .navigationTitle("Recall Practice")
    }

    private func row(title: String, color: String, notebookIDs: [UUID]) -> some View {
        let pages = notebookIDs.compactMap { store.notebook($0) }.flatMap(\.pages)
        let due = pages.filter { study.pageSchedule($0.id).isDue() }.count
        return HStack {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: color)).frame(width: 6, height: 34)
            VStack(alignment: .leading) {
                HandwrittenText(title, size: 17)
                Text("\(pages.count) page\(pages.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if due > 0 {
                Text("\(due) due").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// Options before a recall session.
struct RecallSetupView: View {
    let title: String
    let notebookIDs: [UUID]
    var startPageID: UUID?

    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var study: StudyStore
    @AppStorage("study.memorizeSeconds") private var seconds = 60
    @AppStorage("study.dueOnly") private var dueOnly = true
    @AppStorage("study.shuffle") private var shuffle = false
    @State private var session: RecallSessionBox?

    private var allItems: [RecallItem] {
        notebookIDs.compactMap { store.notebook($0) }.flatMap { notebook in
            notebook.pages.filter { hasContent($0, in: notebook.id) }.map { RecallItem(notebookID: notebook.id, pageID: $0.id) }
        }
    }

    private var items: [RecallItem] {
        var items = dueOnly ? allItems.filter { study.pageSchedule($0.pageID).isDue() } : allItems
        if let startPageID, let index = items.firstIndex(where: { $0.pageID == startPageID }) {
            items = Array(items[index...] + items[..<index])
        }
        return shuffle ? items.shuffled() : items
    }

    var body: some View {
        Form {
            Section {
                HandwrittenText(title, size: 26)
                Text("\(allItems.count) page\(allItems.count == 1 ? "" : "s") with notes · \(items.count) to practice now")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Time to memorize each page", selection: $seconds) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("No timer").tag(0)
                }
                Toggle("Only pages that are due", isOn: $dueOnly)
                Toggle("Shuffle pages", isOn: $shuffle)
            } footer: {
                Text("Pages you rate 1–2 come back soon; pages you know well come back after longer and longer gaps.")
            }
            Section {
                Button {
                    session = RecallSessionBox(items: items)
                } label: {
                    Label("Start Recall Practice", systemImage: "play.fill").frame(maxWidth: .infinity).bold()
                }
                .buttonStyle(.borderedProminent)
                .disabled(items.isEmpty)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Practice")
        .fullScreenCover(item: $session) { box in
            RecallSessionView(items: box.items, seconds: seconds)
        }
    }

    private func hasContent(_ page: Page, in notebookID: UUID) -> Bool {
        if page.kind == .pdf || !page.textBlocks.isEmpty { return true }
        guard let data = store.loadDrawing(notebook: notebookID, page: page.id),
              let drawing = try? PKDrawing(data: data) else { return false }
        return !drawing.strokes.isEmpty
    }
}

private struct RecallSessionBox: Identifiable {
    let id = UUID()
    let items: [RecallItem]
}

/// Memorize → page turns white → rewrite from memory → side-by-side comparison → rate 1–5.
struct RecallSessionView: View {
    let items: [RecallItem]
    let seconds: Int

    private enum Phase { case memorize, recall, compare, finished }

    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var study: StudyStore
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var phase = Phase.memorize
    @State private var remaining = 0
    @State private var original: UIImage?
    @State private var attempt = PKDrawing()
    @State private var ink = SketchInk.pen(0)
    @State private var canvasSize = CGSize(width: 800, height: 1000)
    @State private var rating: RecallRating?
    @State private var ratings: [RecallRating] = []
    @State private var pdfs: [UUID: CGPDFDocument] = [:]

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var item: RecallItem? { index < items.count ? items[index] : nil }
    private var notebook: Notebook? { item.flatMap { store.notebook($0.notebookID) } }
    private var page: Page? { notebook?.pages.first { $0.id == item?.pageID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch phase {
                case .memorize: memorizeView
                case .recall: recallView
                case .compare: compareView
                case .finished: finishedView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            if phase != .finished { bottomBar }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear(perform: loadPage)
        .onReceive(tick) { _ in
            if phase == .memorize, seconds > 0, remaining > 0 { remaining -= 1 }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3.bold()) }
                .accessibilityLabel("End practice")
            if let notebook, phase != .finished {
                VStack(alignment: .leading, spacing: 2) {
                    HandwrittenText(notebook.title, size: 17)
                    Text("Page \((notebook.pages.firstIndex { $0.id == item?.pageID } ?? 0) + 1) · \(index + 1) of \(items.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if phase != .finished { phasePills }
            Spacer()
            if phase == .memorize, seconds > 0 {
                Label(timeText, systemImage: "timer")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(remaining == 0 ? Color.red : .primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var phasePills: some View {
        HStack(spacing: 6) {
            pill("Memorize", icon: .timer, active: phase == .memorize)
            pill("Rewrite", icon: .hide, active: phase == .recall)
            pill("Compare", icon: .reveal, active: phase == .compare)
        }
    }

    private func pill(_ title: String, icon: ThemeIcon, active: Bool) -> some View {
        HStack(spacing: 5) {
            ThemedIcon(icon, size: 16)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(active ? Color.white : .secondary)
        .background(active ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
    }

    private var timeText: String {
        remaining == 0 ? "Time's up" : String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private var memorizeView: some View {
        ScrollView {
            if let original {
                Image(uiImage: original).resizable().scaledToFit().studyCard()
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView().padding(80)
            }
        }
    }

    private var recallView: some View {
        GeometryReader { geometry in
            SketchCanvas(drawing: $attempt, ink: ink, paper: page?.kind == .pdf ? .blank : (page?.paper ?? .ruled))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .studyCard()
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        Text("Rewrite everything you remember").font(.headline).foregroundStyle(.secondary)
                        SketchToolbar(ink: $ink, drawing: $attempt)
                    }
                    .padding(.top, 14)
                }
                .onAppear { canvasSize = geometry.size }
                .onChange(of: geometry.size) { _, size in canvasSize = size }
        }
    }

    private var compareView: some View {
        HStack(spacing: 20) {
            comparisonColumn("Original", image: original)
            comparisonColumn("Your rewrite", image: attemptImage)
        }
    }

    private func comparisonColumn(_ title: String, image: UIImage?) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.headline)
            ScrollView {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Text("Nothing written").foregroundStyle(.secondary).padding(60)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .studyCard()
        }
    }

    private var finishedView: some View {
        let average = ratings.isEmpty ? 0 : Double(ratings.map(\.rawValue).reduce(0, +)) / Double(ratings.count)
        return VStack(spacing: 24) {
            CaughtUpView(title: "All caught up!",
                         message: "You practiced \(ratings.count) page\(ratings.count == 1 ? "" : "s"). Average confidence \(String(format: "%.1f", average)) / 5.")
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            switch phase {
            case .memorize:
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .recall }
                } label: {
                    Label { Text("Hide & Rewrite") } icon: { ThemedIcon(.hide, size: 22) }
                        .font(.title3.bold()).frame(maxWidth: 420).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            case .recall:
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .compare }
                } label: {
                    Label { Text("Done — Compare") } icon: { ThemedIcon(.done, size: 22) }
                        .font(.title3.bold()).frame(maxWidth: 420).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            case .compare:
                Text("How well did you remember it?").font(.headline)
                RatingBar(selection: $rating, schedule: item.map { study.pageSchedule($0.pageID) })
                    .frame(maxWidth: 700)
                Button {
                    next()
                } label: {
                    Label { Text("Next Page") } icon: { ThemedIcon(.next, size: 22) }
                        .font(.title3.bold()).frame(maxWidth: 420).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(rating == nil)
            case .finished:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: - Flow

    private func loadPage() {
        guard let item, let page, let notebook else {
            phase = .finished
            return
        }
        if notebook.hasPDF, pdfs[item.notebookID] == nil, let pdf = store.pdfDocument(for: item.notebookID) {
            pdfs[item.notebookID] = pdf
        }
        original = PageRenderer.image(of: page, in: item.notebookID, store: store, pdf: pdfs[item.notebookID], width: 900)
        attempt = PKDrawing()
        rating = nil
        remaining = seconds
        phase = .memorize
    }

    private func next() {
        guard let item, let rating else { return }
        study.reviewPage(item.pageID, rating: rating)
        ratings.append(rating)
        index += 1
        if index < items.count {
            loadPage()
        } else {
            withAnimation { phase = .finished }
        }
    }

    /// The rewrite rendered on the same paper, cropped to what was written.
    private var attemptImage: UIImage? {
        guard !attempt.strokes.isEmpty else { return nil }
        let height = min(canvasSize.height, max(canvasSize.width * 0.6, attempt.bounds.maxY + 40))
        let region = CGRect(x: 0, y: 0, width: canvasSize.width, height: height)
        let paper = page?.kind == .pdf ? PaperStyle.blank : (page?.paper ?? .blank)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: region.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(region)
            if paper != .blank { PageRenderer.drawPaper(paper, in: region, context: context.cgContext) }
            InkRendering.image(of: attempt, rect: region, scale: 2).draw(in: region)
        }
    }
}

/// The intro card at the top of each Study screen.
struct StudyHeader: View {
    let title: String
    let message: String
    let icon: ThemeIcon
    @EnvironmentObject private var study: StudyStore

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ThemedIcon(icon, size: 40)
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(.title2, design: .serif).bold())
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Label("\(study.reviewedToday) reviewed today", systemImage: "checkmark.circle")
                    Label("\(study.streak)-day streak", systemImage: "flame")
                }
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }
}
