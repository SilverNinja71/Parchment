import SwiftUI

/// `⌘K` Command Palette for BelloBook (macOS & iPad hardware keyboards):
/// Jump to any notebook, folder, study mode, or settings in a few keystrokes.
struct CommandPaletteView: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss

    var onOpenNotebook: (UUID) -> Void
    var onSelectSidebar: (SidebarItem) -> Void
    var onOpenSettings: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matchingNotebooks: [Notebook] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(store.notebooks.prefix(8)) }
        return store.notebooks.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            ($0.folderPath ?? "").localizedCaseInsensitiveContains(q) ||
            ($0.subject ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Style.accent)
                    TextField("Jump to notebook, folder, Flashcards, Recall, Settings…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($searchFocused)
                        .onSubmit {
                            if let first = matchingNotebooks.first {
                                dismiss()
                                onOpenNotebook(first.id)
                            }
                        }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(Color.chrome)

                Divider()

                List {
                    Section("Quick Actions") {
                        Button {
                            dismiss()
                            onSelectSidebar(.flashcards)
                        } label: {
                            Label("Study Anki Flashcards", systemImage: "rectangle.stack")
                        }
                        Button {
                            dismiss()
                            onSelectSidebar(.recall)
                        } label: {
                            Label("Active Recall Practice", systemImage: "brain.head.profile")
                        }
                        Button {
                            dismiss()
                            onOpenSettings()
                        } label: {
                            Label("Settings & Sync (Obsidian / Amphi / iCloud)", systemImage: "gearshape")
                        }
                    }

                    Section("Notebooks (\(matchingNotebooks.count))") {
                        ForEach(matchingNotebooks) { nb in
                            Button {
                                dismiss()
                                onOpenNotebook(nb.id)
                            } label: {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: nb.coverColor))
                                        .frame(width: 18, height: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(nb.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                        if let folder = nb.folderPath, !folder.isEmpty {
                                            Text(folder).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.return.left").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Command Palette (⌘K)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Esc") { dismiss() }
                }
            }
            .onAppear { searchFocused = true }
        }
        .wideSheet()
    }
}
