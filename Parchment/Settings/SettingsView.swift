import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var sync: SyncEngine
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    /// Languages Vision can read handwriting in (a common subset).
    private let languages: [(code: String, name: String)] = [
        ("automatic", "Automatic"), ("en-US", "English"), ("fr-FR", "French"), ("de-DE", "German"),
        ("es-ES", "Spanish"), ("it-IT", "Italian"), ("pt-BR", "Portuguese"), ("zh-Hans", "Chinese (Simplified)"),
        ("zh-Hant", "Chinese (Traditional)"), ("ja-JP", "Japanese"), ("ko-KR", "Korean"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        HStack {
                            ThemedLabel("Sync", icon: .sync)
                            Spacer()
                            Text(sync.connection?.service.title ?? "Off").foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        PersonalizationSettingsView()
                    } label: {
                        Label("Personalize Parchment", systemImage: "paintbrush.pointed")
                    }
                }

                Section {
                    Toggle("Draw with Finger", isOn: $settings.fingerDraws)
                    Toggle("Scratch Out to Erase", isOn: $settings.scratchOutToErase)
                    Picker("Handwriting Language", selection: $settings.recognitionLanguage) {
                        ForEach(languages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                } header: {
                    Text("Writing")
                } footer: {
                    Text("With Draw with Finger off, Apple Pencil writes and your finger scrolls — just like MyScript's Active Pen. Scribble over ink to erase it. Double-tap Apple Pencil to switch to the eraser.")
                }

                Section("New Pages") {
                    Picker("Default Type", selection: $settings.defaultPageKind) {
                        Text("Document").tag(PageKind.document)
                        Text("Freeform").tag(PageKind.freeform)
                    }
                    Picker("Default Paper", selection: $settings.defaultPaper) {
                        ForEach(PaperStyle.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Price", value: "Free, forever")
                } header: {
                    Text("About")
                } footer: {
                    Text("Parchment has no subscriptions, no ads and no paywalled features. Handwriting recognition runs entirely on your iPad.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct PersonalizationSettingsView: View {
    @EnvironmentObject private var store: NotebookStore
    @ObservedObject private var theme = ThemeStore.shared
    @State private var shareItem: ShareItem?
    @State private var confirmReset = false
    @State private var errorMessage: String?
    @State private var importingDrawn = false
    @State private var readingDrawn = false
    @State private var importMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var kitNotebook: Notebook? { store.notebooks.first { $0.isPersonalizationKit } }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Make every part of Parchment yours").font(.headline)
                    Text("The Personalization Kit is a 5-page sheet of boxes. Draw your own app name, logo, toolbar icons, notebook covers and alphabet, tap Apply, and Parchment uses your drawings everywhere.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if kitNotebook != nil {
                    Text("Your kit is in the library — open the notebook with the Kit badge, draw, then tap Apply to Parchment.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button(kitNotebook == nil ? "Start a Personalization Kit" : "Start a Fresh Kit") {
                    do {
                        let data = KitPDFRenderer.makePDF(ghosts: .standard)
                        _ = try store.importPDF(data: data, title: "Personalization Kit", isPersonalizationKit: true)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                Button("Share Blank Kit (AirDrop, Print…)") {
                    do { shareItem = ShareItem(url: try KitExtractor.blankKitFile()) } catch { errorMessage = error.localizedDescription }
                }
            }

            Section {
                Button {
                    importingDrawn = true
                } label: {
                    HStack {
                        Text("Import Pages Drawn in Procreate or Other Apps")
                        Spacer()
                        if readingDrawn { ProgressView() }
                    }
                }
                .disabled(readingDrawn)
                if let importMessage {
                    Text(importMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Export your finished kit pages as PNG, JPEG or PDF at full page size, with your drawing on top of the kit. Parchment works out which page each one is and keeps only your ink. Darker colors work best.")
            }

            Section("Use My Drawings For") {
                Toggle("Toolbar & App Icons", isOn: $theme.useCustomIcons)
                Toggle("Notebook Titles (My Handwriting)", isOn: $theme.useHandwrittenTitles)
                Toggle("Keep My Ink Colors on Icons", isOn: $theme.keepInkColors)
            }

            if theme.hasPersonalization {
                Section("Preview") {
                    HStack {
                        Image(uiImage: theme.logoOrStandard).resizable().scaledToFit().frame(height: 44)
                        if let wordmark = theme.wordmark { Image(uiImage: wordmark).resizable().scaledToFit().frame(height: 44) }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(KitLayout.icons, id: \.id) { icon in
                                if let kind = ThemeIcon(rawValue: icon.id) {
                                    VStack { ThemedIcon(kind, size: 28); Text(icon.label).font(.caption2) }
                                }
                            }
                        }
                    }
                    HandwrittenText("The quick brown fox", size: 24)
                }
                Section {
                    Button("Reset to Standard Look", role: .destructive) { confirmReset = true }
                }
            }
        }
        .navigationTitle("Personalize")
        .sheet(item: $shareItem) { ActivityView(items: [$0.url]) }
        .fileImporter(isPresented: $importingDrawn, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await importDrawnPages(urls) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Remove all your drawings from the app?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { theme.reset() }
        } message: {
            Text("Your kit notebook stays in the library, so you can apply it again later.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Reads kit pages drawn in another app and applies the boxes found on them.
    private func importDrawnPages(_ urls: [URL]) async {
        readingDrawn = true
        defer { readingDrawn = false }
        guard let kit = KitImageExtractor.blankKit(ghosts: .standard) else { return }

        var pictures: [CGImage] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) {
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { continue }
                    let size = page.bounds(for: .cropBox).size
                    let width: CGFloat = 1600
                    let image = page.thumbnail(of: CGSize(width: width, height: width * size.height / max(size.width, 1)), for: .cropBox)
                    if let cgImage = image.cgImage { pictures.append(cgImage) }
                }
            } else if let data = try? Data(contentsOf: url), let cgImage = UIImage(data: data)?.cgImage {
                pictures.append(cgImage)
            }
        }

        // The pixel work runs in the background so the app stays responsive.
        let results = await Task.detached(priority: .userInitiated) {
            pictures.compactMap { KitImageExtractor.extract(from: $0, kit: kit) }
        }.value

        var applied = 0
        for result in results {
            theme.apply(result.images.mapValues { UIImage(cgImage: $0) }, onPages: [result.page])
            applied += result.images.count
        }
        let pages = results.map { "\($0.page + 1)" }.joined(separator: ", ")
        let skipped = pictures.count - results.count
        importMessage = results.isEmpty
            ? "Couldn't find a kit page in that file. Export the whole page, not a cropped part of it."
            : "Applied \(applied) drawings from page\(results.count == 1 ? "" : "s") \(pages)."
                + (skipped > 0 ? " \(skipped) picture\(skipped == 1 ? " wasn't a kit page" : "s weren't kit pages")." : "")
    }
}
