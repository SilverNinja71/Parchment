import SwiftUI
import PencilKit

// MARK: - Writing canvas

enum SketchInk: Equatable {
    case pen(Int)
    case eraser
}

/// A plain sheet of paper to write on (flashcard sides, recall attempts).
struct SketchCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var ink: SketchInk = .pen(0)
    var paper: PaperStyle = .blank
    @ObservedObject private var settings = AppSettings.shared

    final class Container: UIView {
        let canvas = PKCanvasView()
        let paperView = PaperBackgroundView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            overrideUserInterfaceStyle = .light
            backgroundColor = .paper
            addSubview(paperView)
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.alwaysBounceVertical = false
            addSubview(canvas)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            paperView.layout(pageSize: bounds.size, zoom: 1)
            canvas.frame = bounds
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if drawing.wrappedValue != canvasView.drawing { drawing.wrappedValue = canvasView.drawing }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> Container {
        let container = Container()
        container.canvas.delegate = context.coordinator
        container.canvas.drawing = drawing
        container.paperView.configure(style: paper)
        return container
    }

    func updateUIView(_ container: Container, context: Context) {
        context.coordinator.drawing = $drawing
        if container.canvas.drawing != drawing { container.canvas.drawing = drawing }
        container.canvas.drawingPolicy = settings.fingerDraws ? .anyInput : .pencilOnly
        switch ink {
        case .pen(let index):
            container.canvas.tool = PKInkingTool(.pen, color: EditorModel.penColors[index], width: 3)
        case .eraser:
            container.canvas.tool = PKEraserTool(.vector)
        }
        container.paperView.configure(style: paper)
        container.setNeedsLayout()
    }
}

/// Pen colors, eraser and clear for a `SketchCanvas`.
struct SketchToolbar: View {
    @Binding var ink: SketchInk
    @Binding var drawing: PKDrawing

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Button { ink = .pen(index) } label: {
                    Circle().fill(Color(EditorModel.penColors[index])).frame(width: 22, height: 22)
                        .padding(4)
                        .overlay(Circle().strokeBorder(ink == .pen(index) ? Color.accentColor : .clear, lineWidth: 2))
                }
            }
            Button { ink = .eraser } label: {
                ThemedIcon(.eraser, size: 22)
                    .padding(6)
                    .background(ink == .eraser ? Color.accentColor.opacity(0.15) : .clear, in: Circle())
            }
            Button(role: .destructive) { drawing = PKDrawing() } label: {
                ThemedIcon(.trash, size: 20)
            }
            .disabled(drawing.strokes.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - 1–5 rating

/// The rating row at the bottom of every study screen.
struct RatingBar: View {
    @Binding var selection: RecallRating?
    /// When given, each button shows when you'll see it again (like Anki).
    var schedule: ReviewSchedule?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(RecallRating.allCases) { rating in
                let selected = selection == rating
                let color = Color(hex: rating.colorHex)
                Button {
                    selection = rating
                } label: {
                    VStack(spacing: 3) {
                        RatingMark(rating: rating, size: 30)
                            .foregroundStyle(color)
                        Text(rating.title).font(.caption.bold())
                        if let schedule {
                            Text(schedule.preview(rating)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selected ? color.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? color : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(rating.rawValue), \(rating.title)")
                .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
            }
        }
    }
}

/// The number for a rating, or the user's own drawing of it from the Personalization Kit.
struct RatingMark: View {
    let rating: RecallRating
    var size: CGFloat = 30
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        if let image = theme.rating(rating.rawValue) {
            Image(uiImage: image)
                .renderingMode(theme.keepInkColors ? .original : .template)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text("\(rating.rawValue)")
                .font(.system(size: size * 0.8, weight: .bold, design: .serif))
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Showing ink

/// Shows saved PencilKit data scaled to fit.
struct InkImageView: View {
    let data: Data?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: data) {
            guard let data, let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else {
                image = nil
                return
            }
            image = InkRendering.image(of: drawing, rect: drawing.bounds.insetBy(dx: -12, dy: -12), scale: 2)
        }
    }
}

/// One side of a flashcard: its text and drawing on a white card.
struct CardFaceView: View {
    let card: Flashcard
    let side: CardSide
    @EnvironmentObject private var study: StudyStore

    var body: some View {
        let text = side == .front ? card.frontText : card.backText
        let drawing = study.drawing(for: card.id, side: side)
        VStack(spacing: 16) {
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black)
            }
            if drawing != nil {
                InkImageView(data: drawing)
            }
            if text.isEmpty && drawing == nil {
                Text("(empty)").foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .studyCard()
    }
}

extension View {
    /// White card styling used across Study.
    func studyCard() -> some View {
        background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .environment(\.colorScheme, .light)
    }
}

/// Shown when a session is finished: the user's "all caught up" doodle if they drew one.
struct CaughtUpView: View {
    let title: String
    let message: String
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(spacing: 18) {
            if let doodle = theme.caughtUpDoodle {
                Image(uiImage: doodle).resizable().scaledToFit().frame(maxHeight: 160)
            } else {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 72)).foregroundStyle(Color.accentColor)
            }
            Text(title).font(.system(.largeTitle, design: .serif).bold())
            Text(message).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
