import UIKit
import PencilKit
import Vision

/// MyScript-style scratch-out: scribbling back and forth over ink erases it.
enum ScratchOut {
    static func isScratchOut(_ stroke: PKStroke) -> Bool {
        let points = stroke.path.interpolatedPoints(by: .distance(3)).map { $0.location.applying(stroke.transform) }
        guard points.count > 12 else { return false }

        let xs = points.map(\.x), ys = points.map(\.y)
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        let span = max(width, height)
        guard span > 18 else { return false }

        var length: CGFloat = 0
        for index in 1..<points.count {
            length += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }

        // Count direction reversals along the scribble's main axis.
        let values = width >= height ? xs : ys
        let threshold = max(6, span * 0.25)
        var direction = 0
        var extreme = values[0]
        var reversals = 0
        for value in values.dropFirst() {
            switch direction {
            case 0:
                if value - extreme > threshold { direction = 1; extreme = value }
                else if extreme - value > threshold { direction = -1; extreme = value }
            case 1:
                if value > extreme { extreme = value }
                else if extreme - value > threshold { reversals += 1; direction = -1; extreme = value }
            default:
                if value < extreme { extreme = value }
                else if value - extreme > threshold { reversals += 1; direction = 1; extreme = value }
            }
        }
        return reversals >= 4 && length > span * 3.5
    }

    /// Indices of strokes (before the scratch itself) that the scratch covers.
    static func coveredStrokeIndices(in strokes: [PKStroke], by scratch: CGRect) -> [Int] {
        strokes.indices.filter { overlap(of: strokes[$0].renderBounds, with: scratch) > 0.35 }
    }

    static func overlap(of rect: CGRect, with scratch: CGRect) -> CGFloat {
        let padded = rect.insetBy(dx: -1, dy: -1)
        let intersection = padded.intersection(scratch)
        guard !intersection.isNull else { return 0 }
        return (intersection.width * intersection.height) / max(padded.width * padded.height, 1)
    }
}

/// On-device handwriting recognition with Apple's Vision framework (free, private, offline).
enum HandwritingRecognizer {
    @MainActor
    static func recognize(_ drawing: PKDrawing, language: String) async throws -> String {
        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        guard !bounds.isNull, !bounds.isEmpty else { return "" }

        // Dark ink on white paper gives Vision the best results.
        let scale = min(3, max(1, 1600 / max(bounds.width, bounds.height)))
        let ink = InkRendering.image(of: drawing, rect: bounds, scale: scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            ink.draw(at: .zero)
        }
        guard let cgImage = image.cgImage else { return "" }

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if language == "automatic" {
                request.automaticallyDetectsLanguage = true
            } else {
                request.recognitionLanguages = [language]
            }
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let observations = (request.results ?? []).sorted { first, second in
                let a = first.boundingBox, b = second.boundingBox
                // Vision's origin is bottom-left: higher midY means higher on the page.
                if abs(a.midY - b.midY) < min(a.height, b.height) / 2 { return a.minX < b.minX }
                return a.midY > b.midY
            }
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}
