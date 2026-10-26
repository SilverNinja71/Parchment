import UIKit

/// Ruled / grid / dotted paper (and the PDF page for PDF notebooks) drawn behind the ink.
///
/// It lives inside the PKCanvasView's scroll content, so it is laid out in zoomed
/// coordinates. The pattern is a tiny tiled image regenerated per zoom level, which
/// stays cheap even for huge freeform pages.
final class PaperBackgroundView: UIView {
    static let lineSpacing: CGFloat = 34
    static let topMargin: CGFloat = 96

    private let patternView = UIView()
    private let pdfImageView = UIImageView()
    private var style: PaperStyle = .ruled
    private var renderedZoom: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        pdfImageView.contentMode = .scaleToFill
        addSubview(pdfImageView)
        addSubview(patternView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var pdfImage: UIImage? {
        get { pdfImageView.image }
        set { pdfImageView.image = newValue }
    }

    func configure(style: PaperStyle) {
        self.style = style
        renderedZoom = 0
    }

    func layout(pageSize: CGSize, zoom: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: pageSize.width * zoom, height: pageSize.height * zoom)
        pdfImageView.frame = bounds

        let top = style.hasTopMargin ? Self.topMargin * zoom : 0
        patternView.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        if abs(renderedZoom - zoom) > 0.001 {
            renderedZoom = zoom
            patternView.backgroundColor = Self.pattern(style, spacing: Self.lineSpacing * zoom)
        }
    }

    private static func pattern(_ style: PaperStyle, spacing: CGFloat) -> UIColor {
        guard style != .blank, spacing > 2 else { return .clear }
        let size: CGSize
        switch style {
        case .ruled, .dottedLined: size = CGSize(width: 8, height: spacing)
        default: size = CGSize(width: spacing, height: spacing)
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let tile = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.paperLine.setFill()
            switch style {
            case .ruled:
                context.fill(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1))
            case .dottedLined:
                // Solid baseline plus a light dashed midline, like a penmanship guide.
                context.fill(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1))
                UIColor.paperLine.withAlphaComponent(0.2).setFill()
                context.fill(CGRect(x: 0, y: size.height / 2 - 0.5, width: 3, height: 1))
            case .grid:
                context.fill(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1))
                context.fill(CGRect(x: size.width - 1, y: 0, width: 1, height: size.height))
            case .dotted:
                UIColor.paperLine.withAlphaComponent(0.5).setFill()
                let dot: CGFloat = max(1.6, min(3, spacing / 16))
                context.cgContext.fillEllipse(in: CGRect(x: size.width / 2 - dot / 2, y: size.height / 2 - dot / 2, width: dot, height: dot))
            case .blank:
                break
            }
        }
        return UIColor(patternImage: tile)
    }
}

/// Shows converted (typeset) text blocks on top of the ink.
final class TextBlockLayerView: UIView {
    var onTap: ((UUID) -> Void)?
    private var labels: [UUID: UILabel] = [:]
    private var blocks: [TextBlock] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setBlocks(_ blocks: [TextBlock]) {
        self.blocks = blocks
        let ids = Set(blocks.map(\.id))
        for (id, label) in labels where !ids.contains(id) {
            label.removeFromSuperview()
            labels[id] = nil
        }
        for block in blocks where labels[block.id] == nil {
            let label = UILabel()
            label.numberOfLines = 0
            label.textColor = .black
            label.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            // Fingers edit text; Apple Pencil keeps writing over it.
            tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            label.addGestureRecognizer(tap)
            addSubview(label)
            labels[block.id] = label
        }
    }

    func layout(pageSize: CGSize, zoom: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: pageSize.width * zoom, height: pageSize.height * zoom)
        for block in blocks {
            guard let label = labels[block.id] else { continue }
            label.text = block.text
            label.font = .systemFont(ofSize: block.fontSize * zoom)
            let frame = block.frame.applying(CGAffineTransform(scaleX: zoom, y: zoom))
            let fitted = label.sizeThatFits(CGSize(width: frame.width, height: .greatestFiniteMagnitude))
            label.frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(frame.height, fitted.height))
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let label = gesture.view as? UILabel,
              let id = labels.first(where: { $0.value === label })?.key else { return }
        onTap?(id)
    }

    // Only the labels themselves take touches; everything else falls through to the canvas.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
