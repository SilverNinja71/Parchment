import SwiftUI

/// Shows what Vision read from the circled handwriting and lets the user fix it before converting.
struct ConvertSheet: View {
    @State var request: ConversionRequest
    var onConvert: (ConversionRequest) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
            .navigationTitle("Convert to Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if !request.text.isEmpty {
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
    }
}

/// Edit or delete a typeset text block.
struct TextBlockEditor: View {
    @State var block: TextBlock
    var onSave: (TextBlock) -> Void
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $block.text)
                        .frame(minHeight: 160)
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
            .navigationTitle("Text")
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
