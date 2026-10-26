import SwiftUI
import PencilKit

enum EditorTool: String, CaseIterable, Identifiable {
    case pen, highlighter, eraser, lasso, text, convert, math, shapes

    var id: String { rawValue }

    var icon: ThemeIcon {
        switch self {
        case .pen: return .pen
        case .highlighter: return .highlighter
        case .eraser: return .eraser
        case .lasso: return .lasso
        case .text: return .typeText
        case .convert: return .convert
        case .math: return .math
        case .shapes: return .shapes
        }
    }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .lasso: return "Lasso"
        case .text: return "Type text"
        case .convert: return "Convert to text"
        case .math: return "Solve math"
        case .shapes: return "Clean up shapes"
        }
    }

    /// Tools that work by circling ink (instead of drawing).
    var circlesInk: Bool { self == .convert || self == .math || self == .shapes }

    /// Tools with a size/style popover when tapped again.
    var hasOptions: Bool { self == .pen || self == .highlighter || self == .eraser }

    /// Short instruction shown in the toolbar while the tool is selected.
    var hint: String? {
        switch self {
        case .lasso: return "Circle ink to move, copy or resize it"
        case .text: return "Tap the page to type"
        case .convert: return "Circle handwriting to convert it"
        case .math: return "Circle a calculation to solve it"
        case .shapes: return "Circle rough shapes to straighten them"
        default: return nil
        }
    }
}

enum PenStyle: String, CaseIterable, Identifiable {
    case ballpoint, pen, fountain

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var inkType: PKInk.InkType {
        switch self {
        case .ballpoint: return .monoline
        case .pen: return .pen
        case .fountain: return .fountainPen
        }
    }
}

enum EraserMode: String, CaseIterable, Identifiable {
    case stroke, pixel
    var id: String { rawValue }
    var title: String { self == .stroke ? "Erase whole strokes" : "Erase pixels" }
}

/// Strokes the user circled with the Convert tool, plus what Vision read from them.
struct ConversionRequest: Identifiable {
    enum Mode { case text, math }

    let id = UUID()
    let pageID: UUID
    let strokeIndices: [Int]
    let bounds: CGRect
    var text: String
    var mode: Mode = .text
    /// For math: the result, shown next to the ink or typed in place of it.
    var answer: String?
}

/// What Live Text read from the line you're writing right now.
struct LivePreview: Equatable {
    let pageID: UUID
    let strokeIndices: [Int]
    let bounds: CGRect
    let text: String
}

/// Tool state for the notebook editor (shared by the toolbar and the canvas).
@MainActor
final class EditorModel: ObservableObject {
    static let penColors: [UIColor] = [
        .black,
        UIColor(red: 0.12, green: 0.32, blue: 0.78, alpha: 1),
        UIColor(red: 0.80, green: 0.16, blue: 0.16, alpha: 1),
        UIColor(red: 0.13, green: 0.55, blue: 0.27, alpha: 1),
        UIColor(red: 0.50, green: 0.24, blue: 0.70, alpha: 1),
        UIColor(red: 0.55, green: 0.29, blue: 0.18, alpha: 1),
    ]
    static let highlighterColors: [UIColor] = [
        UIColor(red: 1.00, green: 0.88, blue: 0.20, alpha: 1),
        UIColor(red: 0.55, green: 0.90, blue: 0.45, alpha: 1),
        UIColor(red: 1.00, green: 0.55, blue: 0.75, alpha: 1),
        UIColor(red: 0.45, green: 0.78, blue: 1.00, alpha: 1),
    ]

    @Published var tool: EditorTool = .pen {
        didSet { if oldValue != tool { previousTool = oldValue } }
    }
    @Published var penStyle: PenStyle = .pen
    @Published var penColorIndex = 0
    @Published var highlighterColorIndex = 0
    @Published var penWidth: CGFloat = 3
    @Published var highlighterWidth: CGFloat = 18
    @Published var eraserMode: EraserMode = .stroke
    @Published var rulerActive = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var isRecognizing = false
    @Published var conversion: ConversionRequest?
    @Published var livePreview: LivePreview?
    /// A short message shown at the bottom of the editor ("Couldn't find any shapes").
    @Published var notice: String?

    private(set) var previousTool: EditorTool = .eraser
    weak var canvas: PageCanvasController?
    /// The notebook's source PDF, opened once and shared by every page.
    let pdfDocument: CGPDFDocument?

    init(pdfDocument: CGPDFDocument? = nil) {
        self.pdfDocument = pdfDocument
    }

    var pkTool: PKTool {
        switch tool {
        case .pen, .text, .convert, .math, .shapes:
            return PKInkingTool(penStyle.inkType, color: Self.penColors[penColorIndex], width: penWidth)
        case .highlighter:
            return PKInkingTool(.marker, color: Self.highlighterColors[highlighterColorIndex], width: highlighterWidth)
        case .eraser:
            return eraserMode == .stroke ? PKEraserTool(.vector) : PKEraserTool(.bitmap, width: 16)
        case .lasso:
            return PKLassoTool()
        }
    }

    /// Apple Pencil double-tap, honoring the user's system-wide preference.
    func handlePencilDoubleTap(_ action: UIPencilPreferredAction) {
        switch action {
        case .switchEraser:
            tool = tool == .eraser ? previousTool : .eraser
        case .switchPrevious:
            tool = previousTool
        default:
            break
        }
    }

    func undo() { canvas?.undo() }
    func redo() { canvas?.redo() }
    func applyConversion(_ request: ConversionRequest) { canvas?.applyConversion(request) }
    func addMathAnswer(_ request: ConversionRequest) { canvas?.addMathAnswer(request) }
    func convertLivePreview() { canvas?.convertLivePreview() }
}
