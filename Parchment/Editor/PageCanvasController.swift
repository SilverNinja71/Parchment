import UIKit
@preconcurrency import PencilKit

/// Hosts the canvas, the paper behind it and the typeset text on top of it.
final class CanvasContainerView: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Drives one PKCanvasView for whichever page of a notebook is open.
@MainActor
final class PageCanvasController: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
    let container = CanvasContainerView()
    let canvasView = PKCanvasView()

    private let paper = PaperBackgroundView()
    private let textLayer = TextBlockLayerView()
    private let lassoLayer = CAShapeLayer()
    private lazy var lassoGesture = UIPanGestureRecognizer(target: self, action: #selector(handleLasso(_:)))
    private var lassoPoints: [CGPoint] = []

    private let store: NotebookStore
    private let settings: AppSettings
    private weak var editor: EditorModel?

    private(set) var notebookID: UUID?
    private(set) var page: Page?
    private var lastStrokeCount = 0
    private var isApplyingChange = false
    private var needsSave = false
    private var saveWorkItem: DispatchWorkItem?
    private var laidOutWidth: CGFloat = 0
    private var renderedPDFScale: CGFloat = 0

    var onEditTextBlock: ((TextBlock) -> Void)?

    init(editor: EditorModel, store: NotebookStore? = nil, settings: AppSettings? = nil) {
        self.editor = editor
        self.store = store ?? .shared
        self.settings = settings ?? .shared
        super.init()

        // Paper always looks like paper, even in dark mode.
        container.overrideUserInterfaceStyle = .light
        container.backgroundColor = UIColor(white: 0.93, alpha: 1)
        container.addSubview(canvasView)
        container.onLayout = { [weak self] in self?.containerDidLayout() }

        canvasView.delegate = self
        canvasView.backgroundColor = .paper
        canvasView.isOpaque = true
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.alwaysBounceVertical = true
        canvasView.insertSubview(paper, at: 0)
        canvasView.addSubview(textLayer)

        lassoLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
        lassoLayer.strokeColor = UIColor.systemBlue.cgColor
        lassoLayer.lineWidth = 2
        lassoLayer.lineDashPattern = [6, 4]
        canvasView.layer.addSublayer(lassoLayer)
        lassoGesture.maximumNumberOfTouches = 1
        lassoGesture.isEnabled = false
        canvasView.addGestureRecognizer(lassoGesture)

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        canvasView.addInteraction(pencilInteraction)
        textLayer.onTap = { [weak self] id in
            guard let block = self?.page?.textBlocks.first(where: { $0.id == id }) else { return }
            self?.onEditTextBlock?(block)
        }
        editor.canvas = self
    }

    // MARK: - Pages

    /// Shows `page`. Switching pages saves the previous one first.
    func show(_ page: Page, of notebookID: UUID) {
        if self.page?.id == page.id, self.notebookID == notebookID {
            refresh(page)
            return
        }
        saveNow()
        self.notebookID = notebookID
        self.page = page

        isApplyingChange = true
        let drawing = store.loadDrawing(notebook: notebookID, page: page.id).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        canvasView.drawing = drawing
        isApplyingChange = false
        lastStrokeCount = drawing.strokes.count
        canvasView.undoManager?.removeAllActions()

        paper.configure(style: page.kind == .pdf ? .blank : page.paper)
        renderedPDFScale = 0
        paper.pdfImage = nil
        textLayer.setBlocks(page.textBlocks)
        laidOutWidth = 0 // forces a fresh fit-to-width zoom
        container.setNeedsLayout()
        updateUndoState()
    }

    /// The same page changed outside the canvas (paper style, text blocks, size).
    func refresh(_ page: Page) {
        guard let current = self.page, current != page else { return }
        self.page = page
        if current.paper != page.paper { paper.configure(style: page.kind == .pdf ? .blank : page.paper) }
        textLayer.setBlocks(page.textBlocks)
        updateContentSize()
    }

    // MARK: - Tools

    func apply(tool: PKTool, editorTool: EditorTool, fingerDraws: Bool, rulerActive: Bool) {
        canvasView.tool = tool
        canvasView.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
        canvasView.isRulerActive = rulerActive

        let converting = editorTool == .convert
        canvasView.drawingGestureRecognizer.isEnabled = !converting
        lassoGesture.isEnabled = converting
        lassoGesture.allowedTouchTypes = fingerDraws
            ? [NSNumber(value: UITouch.TouchType.pencil.rawValue), NSNumber(value: UITouch.TouchType.direct.rawValue)]
            : [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        canvasView.isScrollEnabled = !(converting && fingerDraws)
    }

    func undo() {
        canvasView.undoManager?.undo()
        updateUndoState()
    }

    func redo() {
        canvasView.undoManager?.redo()
        updateUndoState()
    }

    private func updateUndoState() {
        editor?.canUndo = canvasView.undoManager?.canUndo ?? false
        editor?.canRedo = canvasView.undoManager?.canRedo ?? false
    }

    // MARK: - Layout and zoom

    private var fitZoom: CGFloat {
        guard let page, canvasView.bounds.width > 0 else { return 1 }
        return canvasView.bounds.width / page.width
    }

    private func containerDidLayout() {
        canvasView.frame = container.bounds
        guard let page, container.bounds.width > 0 else { return }
        if abs(laidOutWidth - container.bounds.width) > 0.5 {
            laidOutWidth = container.bounds.width
            let fit = fitZoom
            canvasView.minimumZoomScale = page.kind == .freeform ? fit * 0.25 : fit
            canvasView.maximumZoomScale = fit * 4
            canvasView.zoomScale = fit
        }
        updateContentSize()
    }

    private func updateContentSize() {
        guard let page else { return }
        let zoom = canvasView.zoomScale
        canvasView.contentSize = CGSize(width: page.width * zoom, height: page.height * zoom)
        layoutOverlays()
    }

    private func layoutOverlays() {
        guard let page else { return }
        let zoom = canvasView.zoomScale
        paper.layout(pageSize: page.size, zoom: zoom)
        textLayer.layout(pageSize: page.size, zoom: zoom)
        canvasView.sendSubviewToBack(paper)
        canvasView.bringSubviewToFront(textLayer)

        // Center content that is narrower than the screen (zoomed-out freeform pages).
        let inset = max(0, (canvasView.bounds.width - canvasView.contentSize.width) / 2)
        canvasView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: 0)
        renderPDFIfNeeded(zoom: zoom)
    }

    private func renderPDFIfNeeded(zoom: CGFloat) {
        guard let page, page.kind == .pdf, let index = page.pdfPageIndex,
              let pdfPage = editor?.pdfDocument?.page(at: index + 1) else { return }
        // Re-render sharper as you zoom in (capped to keep memory reasonable).
        let screenScale = canvasView.traitCollection.displayScale
        let wanted = min(3, max(1, (zoom * screenScale * 2).rounded() / 2))
        guard wanted > renderedPDFScale else { return }
        renderedPDFScale = wanted
        paper.pdfImage = PDFDrawing.image(of: pdfPage, size: page.size, scale: wanted)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentSize()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updateContentSize()
    }

    // MARK: - Drawing changes

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingChange else { return }
        let strokes = canvasView.drawing.strokes
        let addedOneStroke = strokes.count == lastStrokeCount + 1
        lastStrokeCount = strokes.count

        if settings.scratchOutToErase, addedOneStroke, editor?.tool == .pen,
           let scratch = strokes.last, ScratchOut.isScratchOut(scratch) {
            // Let PencilKit finish committing the stroke, but remember exactly which stroke
            // it was, so a quick follow-up stroke can't be mistaken for it.
            DispatchQueue.main.async { [weak self] in self?.applyScratchOut(scratch) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        growPageIfNeeded()
        needsSave = true
        scheduleSave()
        updateUndoState()
    }

    private func applyScratchOut(_ scratch: PKStroke) {
        guard let page else { return }
        let strokes = canvasView.drawing.strokes
        // Find the scratch stroke itself (by creation time and position), wherever it now is.
        guard let scratchIndex = strokes.lastIndex(where: {
            $0.path.creationDate == scratch.path.creationDate && $0.renderBounds == scratch.renderBounds
        }) else { return }

        let earlier = Array(strokes[..<scratchIndex])
        let erased = Set(ScratchOut.coveredStrokeIndices(in: earlier, by: scratch.renderBounds))
        let erasedText = Set(page.textBlocks.filter { ScratchOut.overlap(of: $0.frame, with: scratch.renderBounds) > 0.3 }.map(\.id))
        guard !erased.isEmpty || !erasedText.isEmpty else { return } // just a zig-zag drawing

        let kept = strokes.enumerated()
            .filter { $0.offset != scratchIndex && !erased.contains($0.offset) }
            .map(\.element)
        applyEdit(drawing: PKDrawing(strokes: kept),
                  textBlocks: page.textBlocks.filter { !erasedText.contains($0.id) },
                  actionName: "Scratch Out")
    }

    /// Changes ink and typed text together as one undoable step, so Undo always
    /// restores both (and Redo re-applies both).
    private func applyEdit(drawing: PKDrawing, textBlocks: [TextBlock], actionName: String) {
        guard var page, let notebookID else { return }
        let previousDrawing = canvasView.drawing
        let previousBlocks = page.textBlocks

        isApplyingChange = true
        canvasView.drawing = drawing
        isApplyingChange = false
        lastStrokeCount = drawing.strokes.count

        if textBlocks != previousBlocks {
            page.textBlocks = textBlocks
            self.page = page
            textLayer.setBlocks(textBlocks)
            layoutOverlays()
            store.updatePage(page.id, in: notebookID) { $0.textBlocks = textBlocks }
        }

        canvasView.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated {
                controller.applyEdit(drawing: previousDrawing, textBlocks: previousBlocks, actionName: actionName)
            }
        }
        canvasView.undoManager?.setActionName(actionName)
        needsSave = true
        scheduleSave()
        updateUndoState()
    }

    private func growPageIfNeeded() {
        guard var page, let notebookID else { return }
        let bounds = canvasView.drawing.bounds
        guard !bounds.isNull, !bounds.isEmpty else { return }

        var size = page.size
        switch page.kind {
        case .document:
            size.height = max(size.height, bounds.maxY + 500)
        case .freeform:
            size.width = max(size.width, bounds.maxX + 800)
            size.height = max(size.height, bounds.maxY + 800)
        case .pdf:
            return
        }
        guard size != page.size else { return }
        page.size = size
        self.page = page
        updateContentSize()
        store.updatePage(page.id, in: notebookID, touch: false) { $0.size = size }
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard needsSave, let page, let notebookID else { return }
        needsSave = false
        store.saveDrawing(canvasView.drawing.dataRepresentation(), notebook: notebookID, page: page.id)
    }

    // MARK: - Apple Pencil double-tap

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        editor?.handlePencilDoubleTap(UIPencilInteraction.preferredTapAction)
    }

    // MARK: - Convert to text

    @objc private func handleLasso(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: canvasView)
        switch gesture.state {
        case .began:
            lassoPoints = [point]
        case .changed:
            lassoPoints.append(point)
            let path = UIBezierPath()
            path.move(to: lassoPoints[0])
            lassoPoints.dropFirst().forEach { path.addLine(to: $0) }
            path.close()
            lassoLayer.path = path.cgPath
        case .ended:
            finishLasso()
        default:
            lassoPoints = []
            lassoLayer.path = nil
        }
    }

    private func finishLasso() {
        defer {
            lassoPoints = []
            lassoLayer.path = nil
        }
        guard let page, lassoPoints.count > 3, let editor else { return }

        // Lasso points are in zoomed content space; ink is in page space.
        let zoom = canvasView.zoomScale
        let path = UIBezierPath()
        path.move(to: CGPoint(x: lassoPoints[0].x / zoom, y: lassoPoints[0].y / zoom))
        lassoPoints.dropFirst().forEach { path.addLine(to: CGPoint(x: $0.x / zoom, y: $0.y / zoom)) }
        path.close()

        let strokes = canvasView.drawing.strokes
        let indices = strokes.indices.filter { index in
            let stroke = strokes[index]
            let bounds = stroke.renderBounds
            return stroke.ink.inkType != .marker && path.contains(CGPoint(x: bounds.midX, y: bounds.midY))
        }
        guard !indices.isEmpty else { return }

        let selected = PKDrawing(strokes: indices.map { strokes[$0] })
        let bounds = selected.bounds
        editor.isRecognizing = true
        let language = settings.recognitionLanguage
        Task { @MainActor in
            defer { editor.isRecognizing = false }
            let text = (try? await HandwritingRecognizer.recognize(selected, language: language)) ?? ""
            editor.conversion = ConversionRequest(pageID: page.id, strokeIndices: indices, bounds: bounds, text: text)
        }
    }

    /// Swaps the circled ink for a typeset text block.
    func applyConversion(_ request: ConversionRequest) {
        guard let page, request.pageID == page.id else { return }
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let remove = Set(request.strokeIndices)
        let strokes = canvasView.drawing.strokes
        guard remove.allSatisfy({ $0 < strokes.count }) else { return }

        let lines = CGFloat(max(1, text.components(separatedBy: "\n").count))
        let fontSize = min(48, max(14, request.bounds.height / lines * 0.62))
        let block = TextBlock(text: text, x: request.bounds.minX, y: request.bounds.minY,
                              width: max(request.bounds.width, 120), height: request.bounds.height,
                              fontSize: fontSize)
        applyEdit(drawing: PKDrawing(strokes: strokes.enumerated().filter { !remove.contains($0.offset) }.map(\.element)),
                  textBlocks: page.textBlocks + [block],
                  actionName: "Convert")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
