import SwiftUI

/// The tool palette under the top bar: tools, colors, sizes and the ruler.
struct EditorToolbar: View {
    @ObservedObject var editor: EditorModel
    @State private var showOptions = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(EditorTool.allCases) { tool in
                toolButton(tool)
            }

            Divider().frame(height: 26).padding(.horizontal, 6)

            colorSwatches

            Divider().frame(height: 26).padding(.horizontal, 6)

            Button {
                editor.rulerActive.toggle()
            } label: {
                ThemedIcon(.ruler)
                    .frame(width: 40, height: 36)
                    .background(editor.rulerActive ? Style.selection.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Ruler")

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        let selected = editor.tool == tool
        return Button {
            Style.tap()
            if selected, tool.hasOptions {
                showOptions = true
            } else {
                withAnimation(Style.spring) { editor.tool = tool }
            }
        } label: {
            ThemedIcon(tool.icon)
                .foregroundStyle(selected ? Style.selection : .primary)
                .frame(width: 44, height: 36)
                .background(selected ? Style.selection.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(tool.title)
        .modifier(TutorialAnchorModifier(tool: tool))
        .popover(isPresented: Binding(get: { showOptions && editor.tool == tool }, set: { showOptions = $0 })) {
            ToolOptions(editor: editor)
                .padding()
                .frame(width: 300)
        }
    }

    @ViewBuilder
    private var colorSwatches: some View {
        switch editor.tool {
        case .highlighter:
            ForEach(EditorModel.highlighterColors.indices, id: \.self) { index in
                swatch(EditorModel.highlighterColors[index], selected: editor.highlighterColorIndex == index) {
                    editor.highlighterColorIndex = index
                }
            }
        case .pen:
            ForEach(EditorModel.penColors.indices, id: \.self) { index in
                swatch(EditorModel.penColors[index], selected: editor.penColorIndex == index) {
                    editor.penColorIndex = index
                }
            }
        case .eraser:
            Text(editor.eraserMode.title).font(.footnote).foregroundStyle(.secondary)
        case .lasso, .text, .convert, .math, .shapes:
            Text(editor.tool.hint ?? "").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func swatch(_ color: UIColor, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                .padding(4)
                .overlay(Circle().strokeBorder(selected ? Style.selection : .clear, lineWidth: 2))
        }
        .accessibilityLabel("Color")
    }
}

/// Size, pen style and eraser mode (shown when tapping the selected tool again).
struct ToolOptions: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch editor.tool {
            case .pen:
                Picker("Pen", selection: $editor.penStyle) {
                    ForEach(PenStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                widthSlider(value: $editor.penWidth, range: 1...12)
            case .highlighter:
                widthSlider(value: $editor.highlighterWidth, range: 8...40)
            case .eraser:
                Picker("Eraser", selection: $editor.eraserMode) {
                    ForEach(EraserMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            default:
                EmptyView()
            }
        }
    }

    private func widthSlider(value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading) {
            Text("Thickness").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Circle().frame(width: 6, height: 6)
                Slider(value: value, in: range)
                Circle().frame(width: 18, height: 18)
            }
        }
    }
}

/// Lets the welcome tour spotlight the Pen and Convert tools.
private struct TutorialAnchorModifier: ViewModifier {
    let tool: EditorTool

    func body(content: Content) -> some View {
        switch tool {
        case .pen: content.tutorialAnchor(.pen)
        case .convert: content.tutorialAnchor(.convert)
        default: content
        }
    }
}
