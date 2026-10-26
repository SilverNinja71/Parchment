import SwiftUI

/// Two-pane notebook creation: details on the left, a live cover customizer on the right.
struct NewNotebookSheet: View {
    var subject: String? = nil
    var onCreate: (Notebook) -> Void

    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var title = ""
    @State private var kind: PageKind = AppSettings.shared.defaultPageKind
    @State private var paper: PaperStyle = AppSettings.shared.defaultPaper
    @State private var appearance = CoverAppearance()
    @State private var chosenSubject: String?
    @State private var didSetSubject = false
    @State private var addingSubject = false
    @State private var newSubjectName = ""

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled Notebook" : trimmed
    }

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .compact {
                    ScrollView {
                        VStack(spacing: 0) {
                            details
                            Divider()
                            CoverCustomizer(appearance: $appearance, title: displayTitle)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ScrollView { details }
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(Color.hairline).frame(width: 1)
                        ScrollView { CoverCustomizer(appearance: $appearance, title: displayTitle) }
                            .frame(maxWidth: .infinity)
                            .background(Color.chrome)
                    }
                }
            }
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).bold()
                }
            }
            .onAppear {
                if !didSetSubject { chosenSubject = subject; didSetSubject = true }
            }
            .alert("New Subject", isPresented: $addingSubject) {
                TextField("e.g. Biology", text: $newSubjectName)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    let name = newSubjectName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    store.addSubject(name, colorHex: Notebook.coverPalette[store.subjects.count % Notebook.coverPalette.count])
                    withAnimation(Style.spring) { chosenSubject = name }
                }
            }
        }
        .wideSheet()
    }

    // MARK: - Left pane

    private var details: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Untitled Notebook", text: $title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                Rectangle().fill(Color.hairline).frame(height: 1)
            }

            group("Subject") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        subjectChip("None", color: nil, selected: chosenSubject == nil) { chosenSubject = nil }
                        ForEach(store.subjects) { subject in
                            subjectChip(subject.name, color: subject.colorHex, selected: chosenSubject == subject.name) {
                                chosenSubject = subject.name
                            }
                        }
                        Button {
                            newSubjectName = ""
                            addingSubject = true
                        } label: {
                            Label("New Subject", systemImage: "plus")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            group("Page Type") {
                HStack(spacing: 12) {
                    kindCard(.document, icon: "arrow.down.doc", title: "Document",
                             detail: "Scrolls down forever, like a real notebook page.")
                    kindCard(.freeform, icon: "square.dashed", title: "Freeform",
                             detail: "An endless 2D canvas for diagrams and mind maps.")
                }
            }

            group("Paper") {
                PaperStylePicker(selection: $paper, columns: 5)
            }
        }
        .padding(28)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            content()
        }
    }

    private func subjectChip(_ name: String, color: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Style.tap()
            withAnimation(Style.spring) { action() }
        } label: {
            HStack(spacing: 6) {
                if let color { Circle().fill(Color(hex: color)).frame(width: 10, height: 10) }
                Text(name).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Style.selection : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func kindCard(_ value: PageKind, icon: String, title: String, detail: String) -> some View {
        let selected = kind == value
        return Button {
            Style.tap()
            withAnimation(Style.spring) { kind = value }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(selected ? Style.selection : .secondary)
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Style.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Style.cardRadius)
                .strokeBorder(selected ? Style.selection : Color.hairline, lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create

    private func create() {
        var notebook = store.createNotebook(title: displayTitle, kind: kind, paper: paper,
                                            coverColor: appearance.colorHex, subject: chosenSubject)
        if let photo = appearance.image?.jpegData(compressionQuality: 0.85) {
            store.setCoverImageData(photo, for: notebook.id)
        }
        store.update(notebook.id) { appearance.apply(to: &$0) }
        notebook = store.notebook(notebook.id) ?? notebook
        Style.tap()
        dismiss()
        onCreate(notebook)
    }
}
