import SwiftUI

/// Shows what Vision read from the circled handwriting and lets the user fix it before converting.
struct ConvertSheet: View {
    @State var request: ConversionRequest
    var onConvert: (ConversionRequest) -> Void
    var onAddAnswer: (ConversionRequest) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    /// Math: the calculation, editable in case a symbol was misread.
    @State private var calculation = ""

    private var solutions: [MathSolver.Solution] { MathSolver.solve(calculation) }

    var body: some View {
        NavigationStack {
            Group {
                if request.mode == .math { mathBody } else { textBody }
            }
            .padding()
            .navigationTitle(request.mode == .math ? "Solve" : "Convert to Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if request.mode == .math {
                        if !solutions.isEmpty {
                            Button("Add Answer") {
                                var result = request
                                result.answer = solutions.map(\.answer).joined(separator: "\n")
                                onAddAnswer(result)
                                dismiss()
                            }
                            Button("Convert") {
                                var result = request
                                result.text = solutions.map { "\($0.expression) = \($0.answer)" }.joined(separator: "\n")
                                onConvert(result)
                                dismiss()
                            }
                            .bold()
                        }
                    } else if !request.text.isEmpty {
                        Button("Copy") {
                            UIPasteboard.general.string = request.text
                            dismiss()
                        }
                        Button("Convert") {
                            onConvert(request)
                            dismiss()
                        }
                        .bold()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            // Start from the bare calculation (without any "= answer").
            calculation = request.text.components(separatedBy: "\n")
                .map { $0.components(separatedBy: " = ").first ?? $0 }
                .joined(separator: "\n")
        }
    }

    @ViewBuilder
    private var textBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if request.text.isEmpty {
                ContentUnavailableView("Couldn't read that",
                                       systemImage: "scribble",
                                       description: Text("Try writing a little larger, or circle a whole word or line."))
            } else {
                Text("Check the text, then convert. Your ink is replaced by typed text you can still edit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $request.text)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: Style.controlRadius))
            }
        }
    }

    private var mathBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calculation (fix it if a symbol was misread)").font(.subheadline).foregroundStyle(.secondary)
            TextField("e.g. 12 × 3 + 4", text: $calculation, axis: .vertical)
                .font(.title2.monospacedDigit())
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: Style.controlRadius))
            if solutions.isEmpty {
                Label("Parchment couldn't find a calculation. Use numbers with + − × ÷ ^ √ % and parentheses.",
                      systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                ForEach(Array(solutions.enumerated()), id: \.offset) { _, solution in
                    HStack(alignment: .firstTextBaseline) {
                        Text(solution.expression + " =").font(.title2).foregroundStyle(.secondary)
                        Text(solution.answer).font(.largeTitle.bold().monospacedDigit()).foregroundStyle(Style.selection)
                    }
                }
                Text("Add Answer keeps your handwriting and writes the answer beside it. Convert turns it all into typed text.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Edit or delete a typeset text block.
struct TextBlockEditor: View {
    @State var block: TextBlock
    var onSave: (TextBlock) -> Void
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool
    @State private var isNew = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $block.text)
                        .frame(minHeight: 160)
                        .focused($typing)
                }
                Section {
                    Stepper("Size: \(Int(block.fontSize)) pt", value: $block.fontSize, in: 10...72, step: 2)
                }
                Section {
                    Button("Copy Text") { UIPasteboard.general.string = block.text }
                    Button("Delete Text", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle(isNew ? "New Text" : "Text")
            .onAppear {
                // A new text box opens ready to type (on-screen or hardware keyboard).
                isNew = block.text.isEmpty
                if isNew { typing = true }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(block)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

/// UIKit's share sheet (AirDrop, Save to Files, Mail…).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
