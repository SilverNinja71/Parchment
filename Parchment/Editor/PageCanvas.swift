import SwiftUI
import PencilKit

/// SwiftUI wrapper around `PageCanvasController`.
struct PageCanvas: UIViewRepresentable {
    let notebookID: UUID
    let page: Page
    @ObservedObject var editor: EditorModel
    @ObservedObject var settings: AppSettings
    var onEditTextBlock: (TextBlock) -> Void

    func makeCoordinator() -> PageCanvasController {
        PageCanvasController(editor: editor)
    }

    func makeUIView(context: Context) -> CanvasContainerView {
        context.coordinator.container
    }

    func updateUIView(_ view: CanvasContainerView, context: Context) {
        let controller = context.coordinator
        controller.onEditTextBlock = onEditTextBlock
        controller.show(page, of: notebookID)
        controller.apply(tool: editor.pkTool, editorTool: editor.tool,
                         fingerDraws: settings.fingerDraws, rulerActive: editor.rulerActive)
    }

    static func dismantleUIView(_ view: CanvasContainerView, coordinator: PageCanvasController) {
        coordinator.saveNow()
    }
}
