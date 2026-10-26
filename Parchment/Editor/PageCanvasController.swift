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
    private lazy var textTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTextTap(_:)))
    private var currentTool: EditorTool = .pen
    private var liveTextWorkItem: DispatchWorkItem?
    private var liveTextTask: Task<Void, Never>?
    /// Left/right margin for flowing paragraphs on document pages.
    private let paragraphMargin: Double = 60
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
        textTapGesture.isEnabled = false
        canvasView.addGestureRecognizer(textTapGesture)

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

        if editorTool != currentTool { editor?.livePreview = nil }
        currentTool = editorTool
        let converting = editorTool.circlesInk
        let typing = editorTool == .text
        canvasView.drawingGestureRecognizer.isEnabled = !converting && !typing
        lassoGesture.isEnabled = converting
        textTapGesture.isEnabled = typing
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
        scheduleLiveText()
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

        if currentTool == .shapes {
            cleanUpShapes(indices)
            return
        }

        let selected = PKDrawing(strokes: indices.map { strokes[$0] })
        let bounds = selected.bounds
        let solvingMath = currentTool == .math
        editor.isRecognizing = true
        // Math is digits and symbols, which English recognition reads most reliably.
        let language = solvingMath ? "en-US" : settings.recognitionLanguage
        Task { @MainActor in
            defer { editor.isRecognizing = false }
            let text = (try? await HandwritingRecognizer.recognize(selected, language: language)) ?? ""
            if solvingMath {
                let solutions = MathSolver.solve(text)
                editor.conversion = ConversionRequest(
                    pageID: page.id, strokeIndices: indices, bounds: bounds,
                    text: solutions.isEmpty ? text : solutions.map { "\($0.expression) = \($0.answer)" }.joined(separator: "\n"),
                    mode: .math,
                    answer: solutions.isEmpty ? nil : solutions.map(\.answer).joined(separator: "\n"))
            } else {
                editor.conversion = ConversionRequest(pageID: page.id, strokeIndices: indices, bounds: bounds, text: text)
            }
        }
    }

    // MARK: - Diagram cleanup

    private func cleanUpShapes(_ indices: [Int]) {
        guard let page else { return }
        var strokes = canvasView.drawing.strokes
        var cleaned = 0
        for index in indices {
            if let shape = ShapeRecognizer.cleaned(strokes[index]) {
                strokes[index] = shape
                cleaned += 1
            }
        }
        guard cleaned > 0 else {
            editor?.notice = "No shapes found. Circle a line, circle, triangle, rectangle or polygon."
            return
        }
        applyEdit(drawing: PKDrawing(strokes: strokes), textBlocks: page.textBlocks, actionName: "Clean Up Shapes")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        editor?.notice = "Straightened \(cleaned) shape\(cleaned == 1 ? "" : "s")"
    }

    // MARK: - Typing

    @objc private func handleTextTap(_ gesture: UITapGestureRecognizer) {
        guard let page else { return }
        let zoom = canvasView.zoomScale
        let location = gesture.location(in: canvasView)
        let point = CGPoint(x: location.x / zoom, y: location.y / zoom)

        // Tapping existing text edits it; tapping empty paper starts a new text box.
        if let block = page.textBlocks.first(where: { $0.frame.insetBy(dx: -8, dy: -8).contains(point) }) {
            onEditTextBlock?(block)
            return
        }
        let flows = page.kind == .document
        let x = flows ? paragraphMargin : point.x
        let width = flows ? page.width - paragraphMargin * 2 : min(420, page.width - point.x - 20)
        onEditTextBlock?(TextBlock(text: "", x: x, y: point.y - 14, width: max(width, 160), height: 34,
                                   fontSize: 22, flows: flows ? true : nil))
    }

    // MARK: - Live Text

    /// After a short pause in writing, reads the line you just wrote.
    private func scheduleLiveText() {
        liveTextWorkItem?.cancel()
        liveTextTask?.cancel()
        editor?.livePreview = nil
        guard settings.liveTextPreview, currentTool == .pen, page?.kind == .document else { return }
        let item = DispatchWorkItem { [weak self] in self?.readCurrentLine() }
        liveTextWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    private func readCurrentLine() {
        guard let page, let editor, let last = canvasView.drawing.strokes.last else { return }
        let strokes = canvasView.drawing.strokes
        // The current line: recent pen strokes that share a band with the last stroke.
        let band = last.renderBounds.insetBy(dx: -10_000, dy: -PaperBackgroundView.lineSpacing * 0.35)
        let cutoff = last.path.creationDate.addingTimeInterval(-60)
        let indices = strokes.indices.filter { index in
            let stroke = strokes[index]
            return stroke.ink.inkType != .marker && stroke.path.creationDate >= cutoff
                && band.intersects(stroke.renderBounds)
        }
        guard !indices.isEmpty else { return }
        let line = PKDrawing(strokes: indices.map { strokes[$0] })
        let language = settings.recognitionLanguage
        let count = strokes.count
        liveTextTask = Task { @MainActor [weak self] in
            let text = (try? await HandwritingRecognizer.recognize(line, language: language)) ?? ""
            guard let self, !Task.isCancelled, self.canvasView.drawing.strokes.count == count,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            editor.livePreview = LivePreview(pageID: page.id, strokeIndices: indices, bounds: line.bounds,
                                             text: text.replacingOccurrences(of: "\n", with: " "))
        }
    }

    func convertLivePreview() {
        guard let preview = editor?.livePreview else { return }
        editor?.livePreview = nil
        applyConversion(ConversionRequest(pageID: preview.pageID, strokeIndices: preview.strokeIndices,
                                          bounds: preview.bounds, text: preview.text))
    }

    /// Swaps the circled ink for a typeset text block.
    func applyConversion(_ request: ConversionRequest) {
        guard let page, request.pageID == page.id else { return }
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let remove = Set(request.strokeIndices)
        let strokes = canvasView.drawing.strokes
        guard remove.allSatisfy({ $0 < strokes.count }) else { return }
        let remaining = PKDrawing(strokes: strokes.enumerated().filter { !remove.contains($0.offset) }.map(\.element))

        let lines = CGFloat(max(1, text.components(separatedBy: "\n").count))
        let fontSize = min(48, max(14, request.bounds.height / lines * 0.62))
        var blocks = page.textBlocks

        if page.kind == .document {
            // Document pages: converted text becomes a flowing paragraph across the page.
            // Writing right below a paragraph continues it, and the text rewraps.
            let continues = blocks.lastIndex { block in
                block.flows == true && request.bounds.minY - block.frame.maxY < PaperBackgroundView.lineSpacing * 1.6
                    && request.bounds.minY >= block.frame.minY
            }
            if let index = continues {
                blocks[index].text += (request.mode == .math ? "\n" : " ") + text
                blocks[index].height = paragraphHeight(blocks[index])
            } else {
                var block = TextBlock(text: text, x: paragraphMargin, y: request.bounds.minY,
                                      width: page.width - paragraphMargin * 2, height: request.bounds.height,
                                      fontSize: fontSize, flows: true)
                block.height = paragraphHeight(block)
                blocks.append(block)
            }
        } else {
            blocks.append(TextBlock(text: text, x: request.bounds.minX, y: request.bounds.minY,
                                    width: max(request.bounds.width, 120), height: request.bounds.height,
                                    fontSize: fontSize))
        }
        applyEdit(drawing: remaining, textBlocks: blocks, actionName: "Convert")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Keeps the handwritten calculation and writes the answer next to it.
    func addMathAnswer(_ request: ConversionRequest) {
        guard let page, request.pageID == page.id, let answer = request.answer else { return }
        let fontSize = min(44, max(16, request.bounds.height * 0.55))
        let block = TextBlock(text: "= " + answer, x: request.bounds.maxX + 12, y: request.bounds.minY,
                              width: max(120, CGFloat(answer.count + 2) * fontSize * 0.62), height: request.bounds.height,
                              fontSize: fontSize)
        applyEdit(drawing: canvasView.drawing, textBlocks: page.textBlocks + [block], actionName: "Solve")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Height a paragraph needs at its width, so scratch-out and continuing paragraphs line up.
    private func paragraphHeight(_ block: TextBlock) -> Double {
        let rect = (block.text as NSString).boundingRect(
            with: CGSize(width: block.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: block.fontSize)], context: nil)
        return ceil(rect.height) + 6
    }
}
