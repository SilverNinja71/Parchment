import Foundation
import PencilKit
import SwiftUI

// MARK: - Work Verification Models

/// The outcome of following and checking a single handwritten or typed line/step on a page.
public struct WorkVerificationResult: Identifiable, Equatable {
    public enum Category: String, Equatable {
        case arithmetic = "Arithmetic"
        case algebra = "Algebra"
        case simplification = "Simplification"
        case writingStyle = "Style Guide"
        case recall = "Active Recall"
    }

    public enum Status: Equatable {
        /// Step is mathematically or stylistically sound.
        case verified(detail: String)
        /// A calculation, algebraic step, or writing style issue was detected.
        case slip(expected: String, got: String, explanation: String)
        /// A standalone expression was evaluated and its answer is ready to insert.
        case evaluated(answer: String)
        /// Plain note text with no errors or calculations.
        case inconclusive
    }

    public let id: UUID
    public let pageID: UUID
    public let lineIndex: Int
    public let strokeIndices: [Int]
    public let textBlockID: UUID?
    public let bounds: CGRect
    public let rawText: String
    public let normalizedExpression: String
    public let category: Category
    public let status: Status
    public let message: String
    public let suggestedCorrection: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        pageID: UUID,
        lineIndex: Int = 0,
        strokeIndices: [Int] = [],
        textBlockID: UUID? = nil,
        bounds: CGRect,
        rawText: String,
        normalizedExpression: String,
        category: Category = .arithmetic,
        status: Status,
        message: String,
        suggestedCorrection: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.pageID = pageID
        self.lineIndex = lineIndex
        self.strokeIndices = strokeIndices
        self.textBlockID = textBlockID
        self.bounds = bounds
        self.rawText = rawText
        self.normalizedExpression = normalizedExpression
        self.category = category
        self.status = status
        self.message = message
        self.suggestedCorrection = suggestedCorrection
        self.timestamp = timestamp
    }

    public var isVerified: Bool {
        if case .verified = status { return true }
        return false
    }

    public var isSlip: Bool {
        if case .slip = status { return true }
        return false
    }

    public var isEvaluated: Bool {
        if case .evaluated = status { return true }
        return false
    }
}

/// Summary of checking an Active Recall or Flashcard rewrite against the original material.
public struct RecallVerificationSummary: Equatable {
    public let accuracy: Double // 0.0 ... 1.0
    public let matchedTerms: [String]
    public let missedTerms: [String]
    public let verifiedEquations: [String]
    public let equationSlips: [String]
    public let suggestedRating: Int // 1 ... 5
    public let feedback: String
}

// MARK: - Work Follower State

/// Real-time tracking state as the user writes with Apple Pencil or types on the page.
public struct WorkFollowerState: Equatable {
    public enum Phase: Equatable {
        case idle
        case following(strokeCount: Int)
        case verifying
        case completed
    }

    public var phase: Phase = .idle
    public var lastWritingPoint: CGPoint? = nil
    public var activeBand: CGRect? = nil
    public var activeLineIndex: Int? = nil
    public var lastStrokeTimestamp: Date = Date()

    public init(
        phase: Phase = .idle,
        lastWritingPoint: CGPoint? = nil,
        activeBand: CGRect? = nil,
        activeLineIndex: Int? = nil,
        lastStrokeTimestamp: Date = Date()
    ) {
        self.phase = phase
        self.lastWritingPoint = lastWritingPoint
        self.activeBand = activeBand
        self.activeLineIndex = activeLineIndex
        self.lastStrokeTimestamp = lastStrokeTimestamp
    }
}

// MARK: - Line Clustering & Page Cache

/// A horizontal line of strokes or typed text on a page, sorted top-to-bottom.
public struct WorkLineCluster: Equatable {
    public let index: Int
    public let strokeIndices: [Int]
    public let textBlockID: UUID?
    public let bounds: CGRect
    public let fingerprint: String
    public var recognizedText: String?
}

// MARK: - Work Checker Engine

/// On-device work follower and step-by-step checker for Parchment.
///
/// Tracks what the user writes across the entire page, clusters strokes into lines,
/// verifies multi-step algebraic derivations, chained equalities, arithmetic, units,
/// prose style rules, and Active Recall rewrites — 100% offline.
public enum WorkChecker {

    /// Clusters all non-marker strokes on a page into horizontal lines from top to bottom.
    static func clusterLines(in strokes: [PKStroke], textBlocks: [TextBlock] = []) -> [WorkLineCluster] {
        struct RawSpan {
            var strokeIndices: [Int]
            var textBlockID: UUID?
            var bounds: CGRect
            var directText: String?
        }

        // 1. Group pen strokes whose vertical bands overlap significantly.
        var inkSpans: [RawSpan] = []
        let lineTolerance = max(18, PaperBackgroundView.lineSpacing * 0.45)

        for index in strokes.indices {
            let stroke = strokes[index]
            guard stroke.ink.inkType != .marker else { continue }
            let box = stroke.renderBounds
            guard !box.isNull, !box.isEmpty, box.width > 1 || box.height > 1 else { continue }

            if let match = inkSpans.indices.last(where: { i in
                let existing = inkSpans[i].bounds
                let verticalGap = max(0, max(existing.minY - box.maxY, box.minY - existing.maxY))
                let midDiff = abs(existing.midY - box.midY)
                return verticalGap < 8 || midDiff < lineTolerance
            }) {
                inkSpans[match].strokeIndices.append(index)
                inkSpans[match].bounds = inkSpans[match].bounds.union(box)
            } else {
                inkSpans.append(RawSpan(strokeIndices: [index], textBlockID: nil, bounds: box, directText: nil))
            }
        }

        // 2. Include typed text blocks (splitting multi-line blocks into logical lines).
        for block in textBlocks {
            let rawLines = block.text.components(separatedBy: .newlines)
            let lineHeight = max(24, block.fontSize * 1.3)
            for (offset, rawLine) in rawLines.enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                // Skip auto-generated "= answer" blocks that sit right to the side of an ink line
                if trimmed.hasPrefix("="), inkSpans.contains(where: { abs($0.bounds.minY - block.y) < lineTolerance && block.x >= $0.bounds.maxX - 8 }) {
                    continue
                }
                let lineRect = CGRect(
                    x: block.x,
                    y: block.y + CGFloat(offset) * lineHeight,
                    width: block.width,
                    height: lineHeight
                )
                inkSpans.append(RawSpan(strokeIndices: [], textBlockID: block.id, bounds: lineRect, directText: trimmed))
            }
        }

        // 3. Sort top-to-bottom by vertical midpoint.
        inkSpans.sort { $0.bounds.midY < $1.bounds.midY }

        return inkSpans.enumerated().map { idx, span in
            let fp: String
            if let direct = span.directText {
                fp = "txt:\(span.textBlockID?.uuidString ?? ""):\(idx):\(direct)"
            } else {
                let stamps = span.strokeIndices.map { i -> String in
                    let s = strokes[i]
                    let b = s.renderBounds
                    return "\(i)@\(Int(b.minX)),\(Int(b.minY)),\(Int(b.width))x\(Int(b.height))"
                }.joined(separator: "|")
                fp = "ink:\(stamps)"
            }
            return WorkLineCluster(
                index: idx,
                strokeIndices: span.strokeIndices,
                textBlockID: span.textBlockID,
                bounds: span.bounds,
                fingerprint: fp,
                recognizedText: span.directText
            )
        }
    }

    /// Evaluates an entire page of clustered lines, using cached OCR text where fingerprints match.
    @MainActor
    static func checkPage(
        strokes: [PKStroke],
        textBlocks: [TextBlock],
        pageID: UUID,
        language: String,
        cache: inout [String: String]
    ) async -> [WorkVerificationResult] {
        var clusters = clusterLines(in: strokes, textBlocks: textBlocks)
        guard !clusters.isEmpty else { return [] }

        for i in clusters.indices {
            if let direct = clusters[i].recognizedText {
                cache[clusters[i].fingerprint] = direct
                continue
            }
            if let cached = cache[clusters[i].fingerprint] {
                clusters[i].recognizedText = cached
                continue
            }
            let subStrokes = clusters[i].strokeIndices.compactMap { idx in
                idx < strokes.count ? strokes[idx] : nil
            }
            guard !subStrokes.isEmpty else { continue }
            let drawing = PKDrawing(strokes: subStrokes)
            // Recognize math/prose on-device with Vision.
            let text = (try? await HandwritingRecognizer.recognize(drawing, language: language)) ?? ""
            let cleaned = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                cache[clusters[i].fingerprint] = cleaned
                clusters[i].recognizedText = cleaned
            }
        }

        return checkLines(clusters, pageID: pageID)
    }

    /// Checks recognized lines from top to bottom, carrying each derivation's context from one
    /// line to the next.
    static func checkLines(_ clusters: [WorkLineCluster], pageID: UUID) -> [WorkVerificationResult] {
        var results: [WorkVerificationResult] = []
        var previousMathLine: String? = nil

        for cluster in clusters {
            guard let text = cluster.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }

            let result = evaluate(
                text: text,
                pageID: pageID,
                lineIndex: cluster.index,
                strokeIndices: cluster.strokeIndices,
                textBlockID: cluster.textBlockID,
                bounds: cluster.bounds,
                previousLineText: previousMathLine
            )
            results.append(result)
            previousMathLine = nextContext(after: text, result: result, previous: previousMathLine)
        }

        return results
    }

    /// The line the next one is checked against.
    ///
    /// A step that was flagged, or that gives only one of several solutions, keeps the line above
    /// as context, so one slip doesn't make every later line look wrong. Prose, or a finished
    /// answer ("x = 4"), ends the derivation: what follows is a new problem.
    static func nextContext(after text: String, result: WorkVerificationResult, previous: String?) -> String? {
        guard isMathLike(text) else { return nil }
        if let previous {
            if result.isSlip, result.category == .algebra || result.category == .simplification {
                return previous
            }
            if AlgebraicEngine.isPartialSolution(text, of: previous) { return previous }
        }
        if AlgebraicEngine.isSolvedForm(text) { return nil }
        return text
    }

    /// Single-drawing entry point for checking one line or selection against an optional previous line.
    @MainActor
    public static func checkWork(
        in drawing: PKDrawing,
        pageID: UUID,
        strokeIndices: [Int],
        language: String,
        previousLineText: String? = nil
    ) async -> WorkVerificationResult? {
        guard !strokeIndices.isEmpty else { return nil }
        let bounds = drawing.bounds
        guard !bounds.isNull, !bounds.isEmpty else { return nil }

        guard let recognized = try? await HandwritingRecognizer.recognize(drawing, language: language) else {
            return nil
        }
        let clean = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        return evaluate(
            text: clean,
            pageID: pageID,
            strokeIndices: strokeIndices,
            bounds: bounds,
            previousLineText: previousLineText
        )
    }

    // MARK: - Core Evaluation Router

    /// Evaluates a single line or multi-line snippet of text for math, algebra, and writing style rules.
    public static func evaluate(
        text: String,
        pageID: UUID,
        lineIndex: Int = 0,
        strokeIndices: [Int] = [],
        textBlockID: UUID? = nil,
        bounds: CGRect,
        previousLineText: String? = nil
    ) -> WorkVerificationResult {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let latestLine = lines.last else {
            return WorkVerificationResult(
                pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                textBlockID: textBlockID, bounds: bounds, rawText: text,
                normalizedExpression: text, status: .inconclusive, message: ""
            )
        }

        // If the snippet itself has multiple lines, use the second-to-last line as context when previousLineText is nil.
        let effectivePrevious = (lines.count >= 2 ? lines[lines.count - 2] : nil) ?? previousLineText

        // 1. Leading "=" continuation line (e.g. "= 36 + 4" following "12 * 3 + 4")
        if latestLine.hasPrefix("="), let prev = effectivePrevious {
            let rhs = String(latestLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            let prevTarget = prev.components(separatedBy: "=").first?.trimmingCharacters(in: .whitespaces) ?? prev
            if let stepRes = checkStepTransition(
                previous: prevTarget,
                current: rhs,
                pageID: pageID,
                lineIndex: lineIndex,
                strokeIndices: strokeIndices,
                textBlockID: textBlockID,
                bounds: bounds,
                rawText: latestLine
            ) {
                return stepRes
            }
        }

        // 1b. A list of solutions ("x = 2 or x = 3", "x = ±4") checked against the equation above it
        if let prev = effectivePrevious,
           let listRes = checkSolutionList(
            line: latestLine,
            previousLine: prev,
            pageID: pageID,
            lineIndex: lineIndex,
            strokeIndices: strokeIndices,
            textBlockID: textBlockID,
            bounds: bounds
           ) {
            return listRes
        }

        // 2. Line contains "=" (chained equalities, arithmetic equations, or algebraic equations)
        if latestLine.contains("="), !latestLine.hasPrefix("=") {
            if let eqRes = checkEquationOrChain(
                line: latestLine,
                previousLine: effectivePrevious,
                pageID: pageID,
                lineIndex: lineIndex,
                strokeIndices: strokeIndices,
                textBlockID: textBlockID,
                bounds: bounds
            ) {
                return eqRes
            }
        }

        // 3. Multi-step continuity without "=" (e.g. Step 1: "30 + 12", Step 2: "42", or polynomial expansion)
        if let prev = effectivePrevious?.trimmingCharacters(in: .whitespaces),
           !prev.isEmpty, prev != latestLine, startsCalculation(prev), isMathLike(latestLine) {
            if let stepRes = checkStepTransition(
                previous: prev,
                current: latestLine,
                pageID: pageID,
                lineIndex: lineIndex,
                strokeIndices: strokeIndices,
                textBlockID: textBlockID,
                bounds: bounds,
                rawText: latestLine
            ) {
                return stepRes
            }
        }

        // 4. Standalone calculation or unit expression (e.g. "14 * 3 + 2", "15% of 80", "5 m + 30 cm")
        if let standalone = evaluateStandaloneMath(
            line: latestLine,
            pageID: pageID,
            lineIndex: lineIndex,
            strokeIndices: strokeIndices,
            textBlockID: textBlockID,
            bounds: bounds
        ) {
            return standalone
        }

        // 5. Prose Writing & Style Guide Checker (grammar, repeated words, style improvements)
        if let styleResult = WritingStyleChecker.check(
            line: latestLine,
            pageID: pageID,
            lineIndex: lineIndex,
            strokeIndices: strokeIndices,
            textBlockID: textBlockID,
            bounds: bounds
        ) {
            return styleResult
        }

        return WorkVerificationResult(
            pageID: pageID,
            lineIndex: lineIndex,
            strokeIndices: strokeIndices,
            textBlockID: textBlockID,
            bounds: bounds,
            rawText: latestLine,
            normalizedExpression: latestLine,
            status: .inconclusive,
            message: latestLine
        )
    }

    // MARK: - Equation & Chained Equality Checking

    private static func checkEquationOrChain(
        line: String,
        previousLine: String?,
        pageID: UUID,
        lineIndex: Int,
        strokeIndices: [Int],
        textBlockID: UUID?,
        bounds: CGRect
    ) -> WorkVerificationResult? {
        let segments = line.components(separatedBy: "=")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard segments.count >= 2 else { return nil }

        // A. Pure numeric / unit chain: e.g. "12 * 3 + 4 = 36 + 4 = 40" or "5 m + 30 cm = 5.3 m"
        let numericValues = segments.map { AlgebraicEngine.evaluateNumericOrUnit($0) }
        if numericValues.allSatisfy({ $0 != nil }) {
            let unpacked = numericValues.compactMap { $0 }
            let first = unpacked[0]
            let firstExprPretty = AlgebraicEngine.pretty(segments[0])
            let expectedStr = AlgebraicEngine.formatValue(first.value, unit: first.unit)
            var roundedAnswer = false

            for idx in 1..<unpacked.count {
                let current = unpacked[idx]
                // Check unit compatibility if both have units
                if let u1 = first.baseUnit, let u2 = current.baseUnit, u1 != u2 {
                    let msg = "Unit mismatch: \(first.unit ?? u1) vs \(current.unit ?? u2)"
                    return WorkVerificationResult(
                        pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                        textBlockID: textBlockID, bounds: bounds, rawText: line,
                        normalizedExpression: line, category: .arithmetic,
                        status: .slip(expected: expectedStr, got: segments[idx], explanation: msg),
                        message: msg, suggestedCorrection: expectedStr
                    )
                }

                // Compare in base units when both sides carry a unit; a bare number is read
                // in the first segment's unit ("50 cm + 50 cm = 100").
                let bothUnits = first.baseUnit != nil && current.baseUnit != nil
                let lhsVal = bothUnits ? first.baseValue : first.value
                let rhsVal = bothUnits ? current.baseValue : current.value
                let tolerance = max(1e-6, abs(lhsVal) * 1e-6)

                if abs(lhsVal - rhsVal) > tolerance {
                    // The right answer in the unit this segment was written in ("2 km = 2000 m").
                    var expectedHere = first.value
                    var expectedHereStr = expectedStr
                    if bothUnits, abs(current.value) > 1e-12 {
                        expectedHere = first.baseValue / (current.baseValue / current.value)
                        expectedHereStr = AlgebraicEngine.formatValue(expectedHere, unit: current.unit)
                    }
                    // A decimal rounded to the places written (√2 = 1.41) is right, not a slip.
                    if AlgebraicEngine.isRounding(segments[idx], of: expectedHere) {
                        roundedAnswer = true
                        continue
                    }
                    // "100 − 15% = 85": a percentage taken off (or added to) the number before it,
                    // the way a calculator reads it, is also right.
                    if let calculatorStyle = AlgebraicEngine.percentOfBase(segments[0]),
                       abs(calculatorStyle - current.value) <= max(1e-6, abs(calculatorStyle) * 1e-6) {
                        continue
                    }
                    // One quantity against a bare number can't be judged: "5m = 500" may be algebra
                    // with m unknown, and "2 km = 2000" leaves the unit to the reader.
                    if (first.baseUnit != nil) != (current.baseUnit != nil) {
                        let withUnit = first.baseUnit != nil ? segments[0] : segments[idx]
                        if withUnit.dropFirst().rangeOfCharacter(from: CharacterSet(charactersIn: "+-−")) == nil {
                            return nil
                        }
                    }
                    let gotStr = AlgebraicEngine.formatValue(current.value, unit: current.unit)
                    let diagnosis = diagnoseArithmeticSlip(
                        expression: segments[idx - 1],
                        expected: expectedHere,
                        got: current.value,
                        expectedFormatted: expectedHereStr,
                        gotFormatted: gotStr
                    )
                    return WorkVerificationResult(
                        pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                        textBlockID: textBlockID, bounds: bounds, rawText: line,
                        normalizedExpression: "\(firstExprPretty) ≠ \(gotStr)",
                        category: .arithmetic,
                        status: .slip(expected: expectedHereStr, got: gotStr, explanation: diagnosis),
                        message: diagnosis,
                        suggestedCorrection: expectedHereStr
                    )
                }
            }

            // All links in the chain are equal! Also check if it transitions from previousLine:
            if let prev = previousLine, !prev.contains("="), startsCalculation(prev),
               let prevEval = AlgebraicEngine.evaluateNumericOrUnit(prev) {
                let prevVal = prevEval.baseUnit != nil ? prevEval.baseValue : prevEval.value
                let currVal = first.baseUnit != nil ? first.baseValue : first.value
                if abs(prevVal - currVal) > 1e-6 {
                    let exp = AlgebraicEngine.formatValue(prevEval.value, unit: prevEval.unit)
                    let got = expectedStr
                    let msg = "Step discrepancy: previous line equals \(exp), but this line equals \(got)"
                    return WorkVerificationResult(
                        pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                        textBlockID: textBlockID, bounds: bounds, rawText: line,
                        normalizedExpression: line, category: .arithmetic,
                        status: .slip(expected: exp, got: got, explanation: msg),
                        message: msg, suggestedCorrection: exp
                    )
                }
            }

            let finalStr = AlgebraicEngine.formatValue(unpacked.last!.value, unit: unpacked.last!.unit)
            let verifiedMsg = roundedAnswer
                ? "Verified (rounded): \(firstExprPretty) ≈ \(finalStr)"
                : "Verified: \(firstExprPretty) = \(finalStr)"
            return WorkVerificationResult(
                pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                textBlockID: textBlockID, bounds: bounds, rawText: line,
                normalizedExpression: "\(firstExprPretty) \(roundedAnswer ? "≈" : "=") \(finalStr)",
                category: .arithmetic,
                status: .verified(detail: verifiedMsg),
                message: verifiedMsg
            )
        }

        // B. Algebraic equation or identity (contains a variable like x, y, z, t, n)
        if segments.count == 2 {
            return checkAlgebraicEquation(
                left: segments[0],
                right: segments[1],
                previousLine: previousLine,
                pageID: pageID,
                lineIndex: lineIndex,
                strokeIndices: strokeIndices,
                textBlockID: textBlockID,
                bounds: bounds,
                rawText: line
            )
        }

        return nil
    }

    // MARK: - Algebraic Equations & Step-by-Step Derivations

    private static func checkAlgebraicEquation(
        left: String,
        right: String,
        previousLine: String?,
        pageID: UUID,
        lineIndex: Int,
        strokeIndices: [Int],
        textBlockID: UUID?,
        bounds: CGRect,
        rawText: String
    ) -> WorkVerificationResult? {
        guard let currentEq = AlgebraicEngine.analyzeEquation(left: left, right: right) else {
            return nil
        }
        let v = currentEq.variable

        // 1. Check if this line is an identity (always true, e.g. "2(x + 3) = 2x + 6")
        if currentEq.isIdentity {
            return WorkVerificationResult(
                pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                normalizedExpression: rawText, category: .algebra,
                status: .verified(detail: "Verified algebraic identity"),
                message: "Verified identity: \(left) = \(right)"
            )
        }

        // 2. Check if this line is an algebraic contradiction (e.g. "2x + 4 = 2x + 9" when simplifying "2(x + 3) = ...")
        if currentEq.isContradiction {
            let lhsPoly = AlgebraicEngine.polynomial(of: left, variable: v)
            let rhsPoly = AlgebraicEngine.polynomial(of: right, variable: v)

            // A quadratic that never reaches zero (x² + 1 = 0) is a fair equation, not a slip.
            if let lhsPoly, let rhsPoly, !AlgebraicEngine.differByConstant(lhsPoly, rhsPoly) {
                let msg = "Tracking equation (no real solutions)"
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                    normalizedExpression: rawText, category: .algebra,
                    status: .verified(detail: msg),
                    message: msg
                )
            }

            // An expansion written out wrongly: 2(x + 3) = 2x + 9, or the same the other way round.
            for (bracketed, poly, other) in [(left, lhsPoly, right), (right, rhsPoly, left)] {
                guard bracketed.contains("("), let poly else { continue }
                let expanded = AlgebraicEngine.formatPolynomial(poly, variable: v)
                let msg = "Expansion slip: \(bracketed) simplifies to \(expanded), not \(other)"
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                    normalizedExpression: rawText, category: .algebra,
                    status: .slip(expected: expanded, got: other, explanation: msg),
                    message: msg,
                    suggestedCorrection: expanded
                )
            }
            let msg = "No solution: sides differ by a constant"
            return WorkVerificationResult(
                pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                normalizedExpression: rawText, category: .algebra,
                status: .slip(expected: left, got: right, explanation: msg),
                message: msg
            )
        }

        // 3. If there is a previous equation on the page, verify step-by-step equivalence!
        if let prevText = previousLine, prevText.contains("=") {
            let prevParts = prevText.components(separatedBy: "=")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if prevParts.count == 2,
               let prevEq = AlgebraicEngine.analyzeEquation(left: prevParts[0], right: prevParts[1]),
               prevEq.variable == v, !prevEq.roots.isEmpty {

                if AlgebraicEngine.sameRoots(prevEq.roots, currentEq.roots) {
                    let rootsList = currentEq.roots.map { AlgebraicEngine.formatNumber($0) }.joined(separator: ", ")
                    let isFinalSolvedForm = left.trimmingCharacters(in: .whitespaces) == String(v)
                        || right.trimmingCharacters(in: .whitespaces) == String(v)
                    let msg = isFinalSolvedForm
                        ? "Solution verified: \(v) = \(rootsList)"
                        : "Step verified (\(v) = \(rootsList))"
                    return WorkVerificationResult(
                        pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                        textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                        normalizedExpression: rawText, category: .algebra,
                        status: .verified(detail: msg),
                        message: msg
                    )
                } else if currentEq.roots.count < prevEq.roots.count,
                          AlgebraicEngine.roots(currentEq.roots, areAmong: prevEq.roots) {
                    // One of several solutions (x² = 16 → x = 4): right, but not the whole answer.
                    let found = currentEq.roots.map { AlgebraicEngine.formatNumber($0) }.joined(separator: ", ")
                    let others = prevEq.roots
                        .filter { !AlgebraicEngine.roots([$0], areAmong: currentEq.roots) }
                        .map { AlgebraicEngine.formatNumber($0) }.joined(separator: ", ")
                    let msg = "Verified: \(v) = \(found) is a solution (also \(v) = \(others))"
                    return WorkVerificationResult(
                        pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                        textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                        normalizedExpression: rawText, category: .algebra,
                        status: .verified(detail: msg),
                        message: msg
                    )
                } else {
                    // Diagnose why the step from prevEq to currentEq failed!
                    let diagnosis = diagnoseAlgebraicSlip(
                        prevLeft: prevParts[0], prevRight: prevParts[1], prevEq: prevEq,
                        currLeft: left, currRight: right, currEq: currentEq
                    )
                    return WorkVerificationResult(
                        pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                        textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                        normalizedExpression: rawText, category: .algebra,
                        status: .slip(
                            expected: diagnosis.expectedStep,
                            got: rawText,
                            explanation: diagnosis.explanation
                        ),
                        message: diagnosis.explanation,
                        suggestedCorrection: diagnosis.expectedStep
                    )
                }
            }
        }

        // 4. First line of an algebraic problem (no previous equation yet)
        if !currentEq.roots.isEmpty {
            let rootsList = currentEq.roots.map { AlgebraicEngine.formatNumber($0) }.joined(separator: ", ")
            let isSolved = left.trimmingCharacters(in: .whitespaces) == String(v)
                || right.trimmingCharacters(in: .whitespaces) == String(v)
            if isSolved {
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                    normalizedExpression: "\(v) = \(rootsList)", category: .algebra,
                    status: .verified(detail: "Solution: \(v) = \(rootsList)"),
                    message: "Verified: \(v) = \(rootsList)"
                )
            } else {
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                    normalizedExpression: rawText, category: .algebra,
                    status: .verified(detail: "Equation tracked (\(v) = \(rootsList))"),
                    message: "Tracking equation (solves to \(v) = \(rootsList))",
                    suggestedCorrection: "\(v) = \(rootsList)"
                )
            }
        }

        return nil
    }

    // MARK: - Solution Lists

    /// Checks a line that lists solutions ("x = 2 or x = 3", "x = ±4") against the equation above it.
    private static func checkSolutionList(
        line: String,
        previousLine: String,
        pageID: UUID,
        lineIndex: Int,
        strokeIndices: [Int],
        textBlockID: UUID?,
        bounds: CGRect
    ) -> WorkVerificationResult? {
        guard let listed = AlgebraicEngine.solutionList(in: line) else { return nil }
        let prevParts = previousLine.components(separatedBy: "=")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard prevParts.count == 2,
              let prevEq = AlgebraicEngine.analyzeEquation(left: prevParts[0], right: prevParts[1]),
              prevEq.variable == listed.variable, !prevEq.roots.isEmpty else { return nil }

        let expected = AlgebraicEngine.formatSolutions(prevEq.roots, variable: prevEq.variable)
        if AlgebraicEngine.sameRoots(prevEq.roots, listed.roots) {
            let msg = "Solutions verified: \(expected)"
            return WorkVerificationResult(
                pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                textBlockID: textBlockID, bounds: bounds, rawText: line,
                normalizedExpression: expected, category: .algebra,
                status: .verified(detail: msg),
                message: msg
            )
        }
        let msg = "Check the solutions: \(prevParts[0]) = \(prevParts[1]) gives \(expected)"
        return WorkVerificationResult(
            pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
            textBlockID: textBlockID, bounds: bounds, rawText: line,
            normalizedExpression: line, category: .algebra,
            status: .slip(expected: expected, got: line, explanation: msg),
            message: msg,
            suggestedCorrection: expected
        )
    }

    // MARK: - Step-to-Step Expression Transitions

    private static func checkStepTransition(
        previous: String,
        current: String,
        pageID: UUID,
        lineIndex: Int,
        strokeIndices: [Int],
        textBlockID: UUID?,
        bounds: CGRect,
        rawText: String
    ) -> WorkVerificationResult? {
        let cleanPrev = previous.hasPrefix("=") ? String(previous.dropFirst()).trimmingCharacters(in: .whitespaces) : previous
        let cleanCurr = current.hasPrefix("=") ? String(current.dropFirst()).trimmingCharacters(in: .whitespaces) : current

        // 1. Numeric step transition (e.g. "15 * 4 + 10" -> "60 + 10" -> "70")
        if let prevNum = AlgebraicEngine.evaluateNumericOrUnit(cleanPrev),
           let currNum = AlgebraicEngine.evaluateNumericOrUnit(cleanCurr) {
            let v1 = prevNum.baseUnit != nil ? prevNum.baseValue : prevNum.value
            let v2 = currNum.baseUnit != nil ? currNum.baseValue : currNum.value
            let tol = max(1e-6, abs(v1) * 1e-6)
            let expStr = AlgebraicEngine.formatValue(prevNum.value, unit: prevNum.unit)
            let gotStr = AlgebraicEngine.formatValue(currNum.value, unit: currNum.unit)

            let isRounded = abs(v1 - v2) > tol && prevNum.unit == currNum.unit
                && AlgebraicEngine.isRounding(cleanCurr, of: prevNum.value)
            if abs(v1 - v2) <= tol || isRounded {
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                    normalizedExpression: cleanCurr, category: .simplification,
                    status: .verified(detail: "Consistent step (= \(expStr))"),
                    message: "Step verified (= \(expStr))"
                )
            } else {
                let msg = "Step slip: previous line equals \(expStr), but this step equals \(gotStr)"
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                    normalizedExpression: cleanCurr, category: .simplification,
                    status: .slip(expected: expStr, got: gotStr, explanation: msg),
                    message: msg,
                    suggestedCorrection: expStr
                )
            }
        }

        // 2. Symbolic / Polynomial expression simplification (e.g. "(x + 2)(x + 3)" -> "x^2 + 5x + 6")
        if let variable = AlgebraicEngine.detectVariable(in: cleanPrev + " ; " + cleanCurr),
           let polyPrev = AlgebraicEngine.polynomial(of: cleanPrev, variable: variable),
           let polyCurr = AlgebraicEngine.polynomial(of: cleanCurr, variable: variable) {
            if AlgebraicEngine.samePolynomial(polyPrev, polyCurr) {
                let formatted = AlgebraicEngine.formatPolynomial(polyCurr, variable: variable)
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                    normalizedExpression: formatted, category: .simplification,
                    status: .verified(detail: "Equivalent expression: \(formatted)"),
                    message: "Step verified: equivalent to \(formatted)"
                )
            } else {
                let expectedPoly = AlgebraicEngine.formatPolynomial(polyPrev, variable: variable)
                let msg = "Simplification slip: expected \(expectedPoly), got \(cleanCurr)"
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: rawText,
                    normalizedExpression: cleanCurr, category: .simplification,
                    status: .slip(expected: expectedPoly, got: cleanCurr, explanation: msg),
                    message: msg,
                    suggestedCorrection: expectedPoly
                )
            }
        }

        return nil
    }

    // MARK: - Standalone Math Evaluation

    private static func evaluateStandaloneMath(
        line: String,
        pageID: UUID,
        lineIndex: Int,
        strokeIndices: [Int],
        textBlockID: UUID?,
        bounds: CGRect
    ) -> WorkVerificationResult? {
        let stripped = line.replacingOccurrences(of: "\\s*=\\s*\\??$", with: "", options: .regularExpression)
        guard hasMathOperatorOrFunction(stripped) else { return nil }

        if let eval = AlgebraicEngine.evaluateNumericOrUnit(stripped) {
            let prettyExpr = AlgebraicEngine.pretty(stripped)
            let answerStr = AlgebraicEngine.formatValue(eval.value, unit: eval.unit)
            // Avoid trivial single-number evaluations like "42"
            guard stripped.trimmingCharacters(in: .whitespaces) != answerStr else { return nil }
            return WorkVerificationResult(
                pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                textBlockID: textBlockID, bounds: bounds, rawText: line,
                normalizedExpression: "\(prettyExpr) = \(answerStr)",
                category: .arithmetic,
                status: .evaluated(answer: answerStr),
                message: "\(prettyExpr) = \(answerStr)",
                suggestedCorrection: answerStr
            )
        }

        // Symbolic expression expansion preview (e.g. "(x + 2)(x + 3)")
        if stripped.contains("("),
           let v = AlgebraicEngine.detectVariable(in: stripped),
           let poly = AlgebraicEngine.polynomial(of: stripped, variable: v),
           poly.count >= 2 {
            let expanded = AlgebraicEngine.formatPolynomial(poly, variable: v)
            if expanded.replacingOccurrences(of: " ", with: "") != stripped.replacingOccurrences(of: " ", with: "") {
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: line,
                    normalizedExpression: "\(stripped) = \(expanded)",
                    category: .simplification,
                    status: .evaluated(answer: expanded),
                    message: "Expands to \(expanded)",
                    suggestedCorrection: expanded
                )
            }
        }

        return nil
    }

    // MARK: - Error Diagnostics

    private static func diagnoseArithmeticSlip(
        expression: String,
        expected: Double,
        got: Double,
        expectedFormatted: String,
        gotFormatted: String
    ) -> String {
        let norm = MathSolver.normalize(expression)
        let pretty = AlgebraicEngine.pretty(expression)

        // Check if sign error (expected == -got)
        if abs(expected + got) < 1e-6 && abs(expected) > 1e-6 {
            return "Sign error: \(pretty) = \(expectedFormatted), not \(gotFormatted)"
        }
        // Off by 10 or 1 (carry / borrow slip)
        let diff = abs(expected - got)
        if abs(diff - 10) < 1e-6 || abs(diff - 100) < 1e-6 {
            return "Carry/borrow slip: \(pretty) = \(expectedFormatted) (off by \(Int(diff.rounded())))"
        }
        if norm.contains("*") {
            return "Multiplication slip: \(pretty) = \(expectedFormatted), not \(gotFormatted)"
        } else if norm.contains("/") {
            return "Division slip: \(pretty) = \(expectedFormatted), not \(gotFormatted)"
        } else if norm.contains("-") {
            return "Subtraction slip: \(pretty) = \(expectedFormatted), not \(gotFormatted)"
        } else if norm.contains("+") {
            return "Addition slip: \(pretty) = \(expectedFormatted), not \(gotFormatted)"
        } else if norm.contains("^") {
            return "Exponent slip: \(pretty) = \(expectedFormatted), not \(gotFormatted)"
        }
        return "Check calculation: \(pretty) = \(expectedFormatted), not \(gotFormatted)"
    }

    private static func diagnoseAlgebraicSlip(
        prevLeft: String, prevRight: String, prevEq: AlgebraicEngine.EquationAnalysis,
        currLeft: String, currRight: String, currEq: AlgebraicEngine.EquationAnalysis
    ) -> (expectedStep: String, explanation: String) {
        let v = prevEq.variable
        if prevEq.roots.count > 1 {
            let all = AlgebraicEngine.formatSolutions(prevEq.roots, variable: v)
            return (all, "Step changes the solutions: \(prevLeft) = \(prevRight) gives \(all)")
        }
        let expectedRoot = prevEq.roots[0]
        let expectedRootStr = AlgebraicEngine.formatNumber(expectedRoot)
        let gotRootStr = currEq.roots.first.map { AlgebraicEngine.formatNumber($0) } ?? "?"

        // Case 1: Current left side is a single polynomial term like "2x" or "x", e.g. user wrote "2x = 20" instead of "2x = 8"
        if let currLHSValAtRoot = AlgebraicEngine.evaluate(currLeft, variable: v, at: expectedRoot),
           currLHSValAtRoot.isFinite {
            let correctRHS = AlgebraicEngine.formatNumber(currLHSValAtRoot)
            let cleanLeft = currLeft.trimmingCharacters(in: .whitespaces)
            let expectedStep = "\(cleanLeft) = \(correctRHS)"

            // Check if the user added instead of subtracting (or vice versa)
            if let prevLPoly = AlgebraicEngine.polynomial(of: prevLeft, variable: v),
               let prevRPoly = AlgebraicEngine.polynomial(of: prevRight, variable: v),
               prevLPoly.count <= 2, prevRPoly.count <= 2 {
                let constL = prevLPoly.first ?? 0
                let constR = prevRPoly.first ?? 0
                if abs(constL) > 1e-6, let currRVal = Double(currRight.trimmingCharacters(in: .whitespaces)) {
                    if abs(currRVal - (constR + constL)) < 1e-6 {
                        let op = constL > 0 ? "subtract \(AlgebraicEngine.formatNumber(abs(constL))) from" : "add \(AlgebraicEngine.formatNumber(abs(constL))) to"
                        return (expectedStep, "Sign slip: \(op) both sides → \(expectedStep), not \(currRight)")
                    }
                }
            }

            // Check if user forgot to distribute across parentheses: e.g. 3(x - 2) = 12 -> 3x - 2 = 12
            if prevLeft.contains("("), let expandedPrevLeft = AlgebraicEngine.polynomial(of: prevLeft, variable: v) {
                let properLeft = AlgebraicEngine.formatPolynomial(expandedPrevLeft, variable: v)
                if properLeft != cleanLeft && currRight.trimmingCharacters(in: .whitespaces) == prevRight.trimmingCharacters(in: .whitespaces) {
                    let step = "\(properLeft) = \(prevRight.trimmingCharacters(in: .whitespaces))"
                    return (step, "Distribution slip: \(prevLeft) expands to \(properLeft), not \(cleanLeft)")
                }
            }

            return (expectedStep, "Algebraic slip: from \(prevLeft) = \(prevRight), we get \(expectedStep) (\(v) = \(expectedRootStr), not \(gotRootStr))")
        }

        let fallback = "\(v) = \(expectedRootStr)"
        return (fallback, "Step changes solution from \(v) = \(expectedRootStr) to \(v) = \(gotRootStr)")
    }

    // MARK: - Active Recall & Flashcard Comparison

    /// Compares a student's recall rewrite against the original page/card text and equations.
    public static func compareRecall(originalText: String, attemptText: String) -> RecallVerificationSummary {
        let origTokens = extractKeyTerms(from: originalText)
        let attemptTokens = Set(extractKeyTerms(from: attemptText).map { $0.lowercased() })

        var matched: [String] = []
        var missed: [String] = []
        for term in origTokens {
            if attemptTokens.contains(term.lowercased()) {
                matched.append(term)
            } else {
                missed.append(term)
            }
        }

        // Also check any equations written in the attempt (whether on their own line or inline in clauses)
        var verifiedEqs: [String] = []
        var slips: [String] = []
        let clauses = attemptText
            .replacingOccurrences(of: ". ", with: "\n")
            .replacingOccurrences(of: ";", with: "\n")
            .replacingOccurrences(of: ",", with: "\n")
            .components(separatedBy: .newlines)
        for clause in clauses {
            let trimmed = clause.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, isMathLike(trimmed) else { continue }
            let res = evaluate(text: trimmed, pageID: UUID(), bounds: .zero)
            if res.isVerified {
                verifiedEqs.append(res.normalizedExpression)
            } else if res.isSlip {
                slips.append(res.message)
            }
        }

        let termScore = origTokens.isEmpty ? 1.0 : Double(matched.count) / Double(origTokens.count)
        let penalty = Double(slips.count) * 0.15
        let accuracy = max(0.0, min(1.0, termScore - penalty))

        let rating: Int
        switch accuracy {
        case 0.88...: rating = 5
        case 0.72..<0.88: rating = 4
        case 0.50..<0.72: rating = 3
        case 0.25..<0.50: rating = 2
        default: rating = 1
        }

        let pct = Int((accuracy * 100).rounded())
        let feedback: String
        if slips.isEmpty && missed.isEmpty {
            feedback = "Spot on! You recalled all \(matched.count) key concepts accurately."
        } else if !slips.isEmpty {
            feedback = "Recalled \(pct)% of key concepts, with \(slips.count) calculation slip\(slips.count == 1 ? "" : "s") to review."
        } else {
            feedback = "Recalled \(matched.count) of \(origTokens.count) key concepts (\(pct)%). Review the missed terms below."
        }

        return RecallVerificationSummary(
            accuracy: accuracy,
            matchedTerms: matched,
            missedTerms: missed,
            verifiedEquations: verifiedEqs,
            equationSlips: slips,
            suggestedRating: rating,
            feedback: feedback
        )
    }

    private static func extractKeyTerms(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "that", "this", "with", "from", "your", "have", "are",
            "was", "were", "been", "has", "had", "not", "but", "what", "all", "when",
            "can", "said", "there", "use", "each", "which", "she", "how", "their",
            "will", "other", "about", "out", "many", "then", "them", "these", "some",
            "into", "more", "two", "like", "him", "see", "time", "could", "make", "than",
            "first", "its", "who", "now", "people", "made", "over", "did", "down", "only"
        ]
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0.lowercased()) }
        var seen: Set<String> = []
        var unique: [String] = []
        for w in words {
            let lower = w.lowercased()
            if !seen.contains(lower) {
                seen.insert(lower)
                unique.append(w)
            }
        }
        return unique
    }

    // MARK: - Helpers

    public static func isMathLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("=") { return true }
        if hasMathOperatorOrFunction(trimmed) {
            let digitCount = trimmed.filter(\.isNumber).count
            let wordCount = trimmed.components(separatedBy: .whitespaces).filter { $0.count >= 4 && $0.allSatisfy(\.isLetter) }.count
            return digitCount > 0 && wordCount <= 2
        }
        // Single number or variable expression like "42" or "2x"
        if Double(trimmed) != nil { return true }
        if trimmed.range(of: "^-?[0-9]*\\.?[0-9]*[xyztn](\\^[0-9]+)?$", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// True for a line the next line can carry on from: an expression like "12 × 3 + 4",
    /// not a bare number, a list number ("1.") or a date ("11/20").
    private static func startsCalculation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard isMathLike(trimmed), hasMathOperatorOrFunction(trimmed) else { return false }
        return trimmed.range(of: "^[0-9]{1,2}/[0-9]{1,2}(/[0-9]{2,4})?$", options: .regularExpression) == nil
    }

    private static func hasMathOperatorOrFunction(_ text: String) -> Bool {
        let ops = CharacterSet(charactersIn: "+-*/×÷−^%√π²³")
        if text.rangeOfCharacter(from: ops) != nil { return true }
        let lower = text.lowercased()
        for fn in ["sqrt", "sin", "cos", "tan", "log", "ln", "pi", "% of"] {
            if lower.contains(fn) { return true }
        }
        return false
    }
}

// MARK: - Symbolic & Numerical Algebraic Engine

public enum AlgebraicEngine {
    public struct EvaluatedQuantity: Equatable {
        public let value: Double
        public let unit: String?
        public let baseValue: Double
        public let baseUnit: String?
    }

    public struct EquationAnalysis: Equatable {
        public let variable: Character
        public let roots: [Double]
        public let isIdentity: Bool
        public let isContradiction: Bool
    }

    private static let candidateVariables: [Character] = ["x", "y", "z", "t", "n", "a", "b", "c"]

    /// Unit conversion table to base SI units.
    private static let unitTable: [String: (base: String, factor: Double)] = [
        "mm": ("m", 0.001),
        "cm": ("m", 0.01),
        "m":  ("m", 1.0),
        "km": ("m", 1000.0),
        "mg": ("g", 0.001),
        "g":  ("g", 1.0),
        "kg": ("g", 1000.0),
        "ms": ("s", 0.001),
        "s":  ("s", 1.0),
        "sec": ("s", 1.0),
        "min": ("s", 60.0),
        "hr": ("s", 3600.0),
        "h":  ("s", 3600.0),
        "ml": ("l", 0.001),
        "l":  ("l", 1.0),
    ]

    /// Evaluates a pure numeric expression, percentage ("15% of 80"), or dimensional unit expression ("5 m + 30 cm").
    public static func evaluateNumericOrUnit(_ raw: String) -> EvaluatedQuantity? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Handle "A% of B" -> "(A/100)*(B)"
        text = text.replacingOccurrences(
            of: "([0-9.]+)\\s*%\\s*of\\s*",
            with: "($1/100)*",
            options: [.regularExpression, .caseInsensitive]
        )

        // Check for dimensional units (e.g. "5 m + 30 cm" or "5.3 m")
        if let unitResult = evaluateWithUnits(text) {
            return unitResult
        }

        // Standard numeric evaluation (no free variables)
        guard detectVariable(in: text) == nil else { return nil }
        if let val = evaluate(text, variable: "x", at: 0), val.isFinite {
            return EvaluatedQuantity(value: val, unit: nil, baseValue: val, baseUnit: nil)
        }
        return nil
    }

    private static func evaluateWithUnits(_ text: String) -> EvaluatedQuantity? {
        let pattern = "^\\s*(-?[0-9.]+)\\s*([a-zA-Z]+)(?:\\s*([+\\-])\\s*(-?[0-9.]+)\\s*([a-zA-Z]+))?\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        func group(_ idx: Int) -> String? {
            let r = match.range(at: idx)
            guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
            return String(text[range])
        }

        guard let v1Str = group(1), let v1 = Double(v1Str),
              let u1Raw = group(2)?.lowercased(),
              let u1Info = unitTable[u1Raw] else { return nil }

        if let op = group(3), let v2Str = group(4), let v2 = Double(v2Str),
           let u2Raw = group(5)?.lowercased(), let u2Info = unitTable[u2Raw] {
            guard u1Info.base == u2Info.base else { return nil }
            let base1 = v1 * u1Info.factor
            let base2 = v2 * u2Info.factor
            let totalBase = op == "+" ? base1 + base2 : base1 - base2
            let inFirstUnit = totalBase / u1Info.factor
            return EvaluatedQuantity(value: inFirstUnit, unit: u1Raw, baseValue: totalBase, baseUnit: u1Info.base)
        } else {
            let base1 = v1 * u1Info.factor
            return EvaluatedQuantity(value: v1, unit: u1Raw, baseValue: base1, baseUnit: u1Info.base)
        }
    }

    /// Detects the primary algebraic variable in an expression, ignoring function names like sin/cos/sqrt/pi.
    public static func detectVariable(in raw: String) -> Character? {
        var stripped = raw.lowercased()
        for word in ["sqrt", "cbrt", "sin", "cos", "tan", "log", "ln", "pi", "of", "deg", "rad"] {
            stripped = stripped.replacingOccurrences(of: word, with: " ")
        }
        // Replace multiplication 'x' only when spaces surround 'x' between two numbers (e.g. "12 x 3")
        stripped = stripped.replacingOccurrences(
            of: "(?<=[0-9)])\\s+x\\s+(?=[0-9(])",
            with: "*",
            options: .regularExpression
        )
        for candidate in candidateVariables {
            if stripped.contains(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Normalizes a mathematical or algebraic string while keeping the chosen variable intact.
    public static func normalize(_ raw: String, variable: Character = "x") -> String {
        var text = raw.lowercased()
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: #"\left"#, with: "")
            .replacingOccurrences(of: #"\right"#, with: "")

        // LaTeX \frac{a}{b} -> ((a)/(b)) and \sqrt{a} -> sqrt(a)
        text = text.replacingOccurrences(of: #"\\frac\{([^{}]+)\}\{([^{}]+)\}"#, with: "(($1)/($2))", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\\sqrt\{([^{}]+)\}"#, with: "sqrt($1)", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\^\{([^{}]+)\}"#, with: "^($1)", options: .regularExpression)

        text = text.replacingOccurrences(
            of: "([0-9.]+)\\s*%\\s*of\\s*",
            with: "($1/100)*",
            options: .regularExpression
        )
        // Thousands separators ("1,000") and mixed numbers ("1 1/2" → "(1+1/2)")
        text = MathSolver.removingGroupingCommas(text)
        text = text.replacingOccurrences(
            of: "(?<![0-9./])([0-9]+)\\s+([0-9]+)\\s*/\\s*([0-9]+)(?![0-9.])",
            with: "($1+$2/$3)",
            options: .regularExpression
        )
        // Multiplication 'x' only when explicitly surrounded by spaces between numbers, e.g. "14 x 3"
        if variable != "x" {
            text = text.replacingOccurrences(of: "(?<=[0-9)])[x](?=[0-9(])", with: "*", options: .regularExpression)
        } else {
            text = text.replacingOccurrences(of: "(?<=[0-9])\\s+x\\s+(?=[0-9])", with: "*", options: .regularExpression)
        }

        let replacements: [(String, String)] = [
            (#"\cdot"#, "*"), (#"\times"#, "*"), (#"\div"#, "/"),
            (#"\sin"#, "sin"), (#"\cos"#, "cos"), (#"\tan"#, "tan"),
            (#"\ln"#, "ln"), (#"\log"#, "log"), (#"\pi"#, "pi"),
            ("{", "("), ("}", ")"),
            ("×", "*"), ("✕", "*"), ("∗", "*"), ("·", "*"), ("÷", "/"),
            ("−", "-"), ("–", "-"), ("—", "-"), ("√", "sqrt"), ("π", "pi"),
            ("⁰", "^0"), ("¹", "^1"), ("²", "^2"), ("³", "^3"), ("⁴", "^4"),
            ("?", ""), (",", "."), (" ", "")
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text
    }

    /// Evaluates an expression in `variable` at `variable = xValue`.
    public static func evaluate(_ raw: String, variable: Character = "x", at xValue: Double) -> Double? {
        let norm = normalize(raw, variable: variable)
        guard !norm.isEmpty else { return nil }
        var parser = AlgebraicParser(Array(norm), variable: variable, variableValue: xValue)
        guard let result = parser.expression(), parser.isAtEnd else { return nil }
        return result
    }

    /// Extracts polynomial coefficients `[c0, c1, c2, c3]` for $c_0 + c_1 x + c_2 x^2 + c_3 x^3$ if the expression is a polynomial of degree <= 3.
    public static func polynomial(of raw: String, variable: Character = "x") -> [Double]? {
        // Sample at 4 points to interpolate a degree <= 3 polynomial via Vandermonde / finite differences,
        // then verify at 2 independent test points to ensure it's truly a polynomial (not 1/x or sin(x)).
        guard let f0 = evaluate(raw, variable: variable, at: 0),
              let f1 = evaluate(raw, variable: variable, at: 1),
              let fm1 = evaluate(raw, variable: variable, at: -1),
              let f2 = evaluate(raw, variable: variable, at: 2),
              f0.isFinite, f1.isFinite, fm1.isFinite, f2.isFinite else {
            return nil
        }

        let c0 = f0
        let c2 = (f1 + fm1 - 2 * c0) / 2.0
        let c1plusc3 = (f1 - fm1) / 2.0
        // f(2) = c0 + 2*c1 + 4*c2 + 8*c3 = c0 + 4*c2 + 2*(c1 + c3) + 6*c3
        let c3 = (f2 - c0 - 4 * c2 - 2 * c1plusc3) / 6.0
        let c1 = c1plusc3 - c3

        let coeffs = [c0, c1, c2, c3].map { abs($0) < 1e-9 ? 0.0 : $0 }

        // Verify at x = 3 and x = -2.5
        for testX in [3.0, -2.5] {
            guard let actual = evaluate(raw, variable: variable, at: testX), actual.isFinite else { return nil }
            let predicted = coeffs[0] + coeffs[1] * testX + coeffs[2] * testX * testX + coeffs[3] * testX * testX * testX
            if abs(actual - predicted) > max(1e-6, abs(actual) * 1e-6) {
                return nil
            }
        }

        // Trim trailing zeros
        var trimmed = coeffs
        while trimmed.count > 1 && abs(trimmed.last ?? 0) < 1e-9 {
            trimmed.removeLast()
        }
        return trimmed
    }

    public static func samePolynomial(_ a: [Double], _ b: [Double]) -> Bool {
        let count = max(a.count, b.count)
        for i in 0..<count {
            let va = i < a.count ? a[i] : 0
            let vb = i < b.count ? b[i] : 0
            if abs(va - vb) > 1e-6 { return false }
        }
        return true
    }

    public static func formatPolynomial(_ coeffs: [Double], variable: Character) -> String {
        var terms: [String] = []
        for power in coeffs.indices.reversed() {
            let c = coeffs[power]
            guard abs(c) > 1e-9 else { continue }
            let sign = c < 0 ? "−" : (terms.isEmpty ? "" : "+")
            let absC = abs(c)
            let coeffStr = (power > 0 && abs(absC - 1.0) < 1e-9) ? "" : formatNumber(absC)
            let varStr: String
            switch power {
            case 0: varStr = ""
            case 1: varStr = String(variable)
            case 2: varStr = "\(variable)²"
            case 3: varStr = "\(variable)³"
            default: varStr = "\(variable)^\(power)"
            }
            let piece = "\(coeffStr)\(varStr)"
            if terms.isEmpty {
                terms.append(c < 0 ? "−\(piece)" : piece)
            } else {
                terms.append("\(sign) \(piece)")
            }
        }
        return terms.isEmpty ? "0" : terms.joined(separator: " ")
    }

    /// Analyzes an equation `left = right` to find its variable, roots, or identity/contradiction state.
    public static func analyzeEquation(left: String, right: String) -> EquationAnalysis? {
        guard let v = detectVariable(in: left + " = " + right) else { return nil }

        // Fast & exact path for degree <= 2 polynomials: P(x) = left(x) - right(x)
        if let pLeft = polynomial(of: left, variable: v),
           let pRight = polynomial(of: right, variable: v) {
            let maxDeg = max(pLeft.count, pRight.count)
            var diff = [Double](repeating: 0, count: maxDeg)
            for i in 0..<maxDeg {
                let a = i < pLeft.count ? pLeft[i] : 0
                let b = i < pRight.count ? pRight[i] : 0
                diff[i] = a - b
            }
            while diff.count > 1 && abs(diff.last ?? 0) < 1e-8 {
                diff.removeLast()
            }

            if diff.count == 1 {
                if abs(diff[0]) < 1e-7 {
                    return EquationAnalysis(variable: v, roots: [], isIdentity: true, isContradiction: false)
                } else {
                    return EquationAnalysis(variable: v, roots: [], isIdentity: false, isContradiction: true)
                }
            } else if diff.count == 2 {
                // Linear: c0 + c1 * x = 0 -> x = -c0 / c1
                let root = -diff[0] / diff[1]
                return EquationAnalysis(variable: v, roots: [cleanZero(root)], isIdentity: false, isContradiction: false)
            } else if diff.count == 3 {
                // Quadratic: c0 + c1 * x + c2 * x^2 = 0
                let c = diff[0], b = diff[1], a = diff[2]
                let disc = b * b - 4 * a * c
                if disc < -1e-7 {
                    return EquationAnalysis(variable: v, roots: [], isIdentity: false, isContradiction: true)
                } else if abs(disc) <= 1e-7 {
                    let r = cleanZero(-b / (2 * a))
                    return EquationAnalysis(variable: v, roots: [r], isIdentity: false, isContradiction: false)
                } else {
                    let r1 = cleanZero((-b - disc.squareRoot()) / (2 * a))
                    let r2 = cleanZero((-b + disc.squareRoot()) / (2 * a))
                    let sorted = [r1, r2].sorted()
                    return EquationAnalysis(variable: v, roots: sorted, isIdentity: false, isContradiction: false)
                }
            }
        }

        // General numerical root finding (for rational/radical/trig equations)
        var foundRoots: [Double] = []
        let seeds: [Double] = [-10, -5, -2, -1, -0.5, 0, 0.5, 1, 2, 3, 5, 10, 20]
        for seed in seeds {
            var x = seed
            for _ in 0..<28 {
                guard let fl = evaluate(left, variable: v, at: x),
                      let fr = evaluate(right, variable: v, at: x) else { break }
                let fx = fl - fr
                if abs(fx) < 1e-9 {
                    let cleaned = cleanZero(x)
                    if !foundRoots.contains(where: { abs($0 - cleaned) < 1e-5 }) {
                        foundRoots.append(cleaned)
                    }
                    break
                }
                let h = 1e-6
                guard let flh = evaluate(left, variable: v, at: x + h),
                      let frh = evaluate(right, variable: v, at: x + h) else { break }
                let df = ((flh - frh) - fx) / h
                guard abs(df) > 1e-12 else { break }
                x -= fx / df
            }
        }

        if !foundRoots.isEmpty {
            return EquationAnalysis(variable: v, roots: foundRoots.sorted(), isIdentity: false, isContradiction: false)
        }
        return nil
    }

    public static func sameRoots(_ a: [Double], _ b: [Double]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        let sa = a.sorted(), sb = b.sorted()
        for i in sa.indices {
            if abs(sa[i] - sb[i]) > 1e-5 { return false }
        }
        return true
    }

    /// "100 - 15%" read as a calculator does: 100 less 15% of 100.
    public static func percentOfBase(_ raw: String) -> Double? {
        let pattern = "^\\s*([0-9]*\\.?[0-9]+)\\s*([+\\-−])\\s*([0-9]*\\.?[0-9]+)\\s*%\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let baseRange = Range(match.range(at: 1), in: raw),
              let signRange = Range(match.range(at: 2), in: raw),
              let percentRange = Range(match.range(at: 3), in: raw),
              let base = Double(raw[baseRange]), let percent = Double(raw[percentRange]) else { return nil }
        let change = base * percent / 100
        return raw[signRange] == "+" ? base + change : base - change
    }

    /// True for a finished answer: "x = 4", "4 = x", "x = 2 or x = 3".
    public static func isSolvedForm(_ line: String) -> Bool {
        if solutionList(in: line) != nil { return true }
        let parts = line.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard parts.count == 2 else { return false }
        for (name, value) in [(parts[0], parts[1]), (parts[1], parts[0])]
        where name.count == 1 && name.first?.isLetter == true {
            if detectVariable(in: value) == nil, evaluate(value, variable: "x", at: 0) != nil { return true }
        }
        return false
    }

    /// True when `line` gives some, but not all, of the solutions of the equation in `previous`
    /// (x² = 16, then x = 4).
    public static func isPartialSolution(_ line: String, of previous: String) -> Bool {
        func analysis(_ text: String) -> EquationAnalysis? {
            let parts = text.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return nil }
            return analyzeEquation(left: parts[0], right: parts[1])
        }
        guard let current = analysis(line), let before = analysis(previous),
              current.variable == before.variable else { return false }
        return current.roots.count < before.roots.count && roots(current.roots, areAmong: before.roots)
    }

    /// True when two polynomials differ only in their constant term.
    public static func differByConstant(_ a: [Double], _ b: [Double]) -> Bool {
        for power in 1..<max(a.count, b.count, 2) {
            let va = power < a.count ? a[power] : 0
            let vb = power < b.count ? b[power] : 0
            if abs(va - vb) > 1e-7 { return false }
        }
        return true
    }

    /// True when every value in `subset` is one of `roots`.
    public static func roots(_ subset: [Double], areAmong roots: [Double]) -> Bool {
        !subset.isEmpty && subset.allSatisfy { value in roots.contains { abs($0 - value) < 1e-5 } }
    }

    /// "x = 2 or x = 3"
    public static func formatSolutions(_ roots: [Double], variable: Character) -> String {
        roots.map { "\(variable) = \(formatNumber($0))" }.joined(separator: " or ")
    }

    /// Reads a line that lists several solutions: "x = 2 or x = 3", "x = 2, 3", "x = ±4".
    public static func solutionList(in raw: String) -> (variable: Character, roots: [Double])? {
        let text = raw.lowercased().trimmingCharacters(in: .whitespaces)
        let parts = text
            .replacingOccurrences(of: "\\s+(or|and)\\s+|,\\s+|;", with: "|", options: .regularExpression)
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var variable: Character?
        var roots: [Double] = []
        for part in parts {
            var value = part
            if let equals = part.firstIndex(of: "=") {
                let name = part[..<equals].trimmingCharacters(in: .whitespaces)
                guard name.count == 1, let letter = name.first, letter.isLetter,
                      variable == nil || variable == letter else { return nil }
                variable = letter
                value = String(part[part.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            } else if variable == nil {
                return nil
            }
            var bothSigns = false
            for prefix in ["±", "+/-", "+-"] where value.hasPrefix(prefix) {
                bothSigns = true
                value = String(value.dropFirst(prefix.count))
                break
            }
            guard !value.contains("="), detectVariable(in: value) == nil,
                  let number = evaluate(value, variable: "x", at: 0), number.isFinite else { return nil }
            roots.append(number)
            if bothSigns, abs(number) > 1e-12 { roots.append(-number) }
        }
        guard variable != nil, roots.count >= 2 else { return nil }
        return (variable!, roots.sorted())
    }

    /// True when `written` is a plain decimal equal to `exact` rounded (or cut off) to the
    /// places written, so "22/7 = 3.14" and "√2 = 1.414" count as right.
    public static func isRounding(_ written: String, of exact: Double) -> Bool {
        let text = written.trimmingCharacters(in: .whitespaces)
        guard let match = text.range(of: "^-?[0-9]*[.,][0-9]+", options: .regularExpression) else { return false }
        let unit = text[match.upperBound...].trimmingCharacters(in: .whitespaces)
        guard unit.allSatisfy(\.isLetter) else { return false }
        let literal = text[match].replacingOccurrences(of: ",", with: ".")
        guard let value = Double(literal), let point = literal.firstIndex(of: ".") else { return false }
        let places = literal.distance(from: point, to: literal.endIndex) - 1
        let step = pow(10.0, -Double(places))
        let error = abs(exact - value)
        if error <= step / 2 + 1e-9 { return true }
        // Cut off instead of rounded (2/3 = 0.66): accept from two places on.
        return places >= 2 && error < step && abs(value) < abs(exact) && (value < 0) == (exact < 0)
    }

    private static func cleanZero(_ value: Double) -> Double {
        if abs(value - value.rounded()) < 1e-7 { return value.rounded() }
        return value
    }

    public static func formatNumber(_ value: Double) -> String {
        MathSolver.format(value)
    }

    public static func formatValue(_ value: Double, unit: String?) -> String {
        let num = MathSolver.format(value)
        if let unit, !unit.isEmpty {
            return "\(num) \(unit)"
        }
        return num
    }

    public static func pretty(_ raw: String) -> String {
        // Keep mixed numbers ("1 1/2"), units ("5 m + 30 cm") and "15% of 80" as written;
        // the cleanup below would run them together.
        let asWritten = raw.trimmingCharacters(in: .whitespaces)
        if asWritten.range(of: "(?<![0-9./])[0-9]+\\s+[0-9]+\\s*/\\s*[0-9]+", options: .regularExpression) != nil
            || asWritten.range(of: "%\\s*of\\b", options: [.regularExpression, .caseInsensitive]) != nil
            || evaluateWithUnits(asWritten) != nil {
            return asWritten
        }
        return MathSolver.pretty(MathSolver.normalize(raw))
    }

    // MARK: - Recursive Descent Algebraic & Scientific Parser

    private struct AlgebraicParser {
        let characters: [Character]
        let variable: Character
        let variableValue: Double
        var index = 0

        init(_ characters: [Character], variable: Character, variableValue: Double) {
            self.characters = characters
            self.variable = variable
            self.variableValue = variableValue
        }

        var isAtEnd: Bool { index >= characters.count }
        private var current: Character? { isAtEnd ? nil : characters[index] }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let op = current, op == "+" || op == "-" {
                index += 1
                guard let right = term() else { return nil }
                value = op == "+" ? value + right : value - right
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while let next = current {
                if next == "*" || next == "/" {
                    index += 1
                    guard let right = power() else { return nil }
                    value = next == "*" ? value * right : value / right
                } else if next == "(" || next == variable || startsFunction() {
                    // Implicit multiplication: 2x, 3(x-2), (x+1)(x+2), 2sin(30), 2pi
                    guard let right = power() else { return nil }
                    value *= right
                } else {
                    break
                }
            }
            return value
        }

        /// A leading minus applies to the whole power (-3^2 = -9, -x^2 = -(x^2)),
        /// and exponents chain to the right (2^3^2 = 2^9).
        mutating func power() -> Double? {
            if current == "-" { index += 1; return power().map { -$0 } }
            if current == "+" { index += 1; return power() }
            guard let base = postfix() else { return nil }
            if current == "^" {
                index += 1
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func postfix() -> Double? {
            guard var value = primary() else { return nil }
            while let post = current {
                if post == "%" {
                    index += 1
                    value /= 100.0
                } else if post == "!" {
                    index += 1
                    guard value >= 0, value <= 20, abs(value - value.rounded()) < 1e-9 else { return nil }
                    let n = Int(value.rounded())
                    value = n <= 1 ? 1.0 : (2...n).reduce(1.0) { $0 * Double($1) }
                } else {
                    break
                }
            }
            return value
        }

        mutating func primary() -> Double? {
            if current == "(" {
                index += 1
                let value = expression()
                if current == ")" { index += 1 }
                return value
            }
            if current == variable {
                index += 1
                return variableValue
            }
            if consume("sqrt") { return primary().map { $0.squareRoot() } }
            if consume("cbrt") { return primary().map { cbrt($0) } }
            if consume("sin") {
                return primary().map { arg in
                    // Treat whole degree angles like 30, 45, 60, 90, 180 as degrees
                    let rad = (abs(arg) > 2 * .pi || [30.0, 45.0, 60.0, 90.0, 120.0, 135.0, 150.0, 180.0, 270.0, 360.0].contains(abs(arg)))
                        ? arg * .pi / 180.0 : arg
                    return sin(rad)
                }
            }
            if consume("cos") {
                return primary().map { arg in
                    let rad = (abs(arg) > 2 * .pi || [30.0, 45.0, 60.0, 90.0, 120.0, 135.0, 150.0, 180.0, 270.0, 360.0].contains(abs(arg)))
                        ? arg * .pi / 180.0 : arg
                    return cos(rad)
                }
            }
            if consume("tan") {
                return primary().map { arg in
                    let rad = (abs(arg) > 2 * .pi || [30.0, 45.0, 60.0, 120.0, 135.0, 150.0, 180.0, 360.0].contains(abs(arg)))
                        ? arg * .pi / 180.0 : arg
                    return tan(rad)
                }
            }
            if consume("ln") { return primary().map { log($0) } }
            if consume("log") { return primary().map { log10($0) } }
            if consume("pi") { return .pi }
            if current == "e", (index + 1 >= characters.count || !characters[index + 1].isLetter) {
                index += 1
                return M_E
            }

            var digits = ""
            while let character = current, character.isNumber || character == "." {
                digits.append(character)
                index += 1
            }
            return Double(digits)
        }

        private func startsFunction() -> Bool {
            for fn in ["sqrt", "cbrt", "sin", "cos", "tan", "ln", "log", "pi"] {
                let end = index + fn.count
                if end <= characters.count, String(characters[index..<end]) == fn {
                    return true
                }
            }
            return false
        }

        private mutating func consume(_ word: String) -> Bool {
            let end = index + word.count
            guard end <= characters.count, String(characters[index..<end]) == word else { return false }
            index = end
            return true
        }
    }
}

// MARK: - Prose Writing & Style Guide Checker

/// Checks handwritten and typed prose against standard grammar and composition style guides
/// (Strunk & White / MLA / APA clarity, conciseness, mechanics, and common confusions).
public enum WritingStyleChecker {
    private struct StyleRule {
        let pattern: String
        let replacement: String
        let explanation: String
        let caseInsensitive: Bool
    }

    private static let rules: [StyleRule] = [
        // Common modal grammar errors
        StyleRule(pattern: "\\bcould of\\b", replacement: "could have", explanation: "Grammar: use \"could have\" instead of \"could of\"", caseInsensitive: true),
        StyleRule(pattern: "\\bshould of\\b", replacement: "should have", explanation: "Grammar: use \"should have\" instead of \"should of\"", caseInsensitive: true),
        StyleRule(pattern: "\\bwould of\\b", replacement: "would have", explanation: "Grammar: use \"would have\" instead of \"would of\"", caseInsensitive: true),
        StyleRule(pattern: "\\bmust of\\b", replacement: "must have", explanation: "Grammar: use \"must have\" instead of \"must of\"", caseInsensitive: true),
        // Common spelling & usage slips
        StyleRule(pattern: "\\balot\\b", replacement: "a lot", explanation: "Spelling: \"a lot\" is two words", caseInsensitive: true),
        StyleRule(pattern: "\\bits'\\b", replacement: "its", explanation: "Punctuation: \"its'\" is not a word (use \"its\" or \"it's\")", caseInsensitive: true),
        StyleRule(pattern: "\\bdefinately\\b", replacement: "definitely", explanation: "Spelling: \"definitely\"", caseInsensitive: true),
        StyleRule(pattern: "\\bseperate\\b", replacement: "separate", explanation: "Spelling: \"separate\"", caseInsensitive: true),
        StyleRule(pattern: "\\brecieve\\b", replacement: "receive", explanation: "Spelling: \"receive\" (i before e except after c)", caseInsensitive: true),
        StyleRule(pattern: "\\boccured\\b", replacement: "occurred", explanation: "Spelling: \"occurred\" (double r)", caseInsensitive: true),
        StyleRule(pattern: "\\buntill\\b", replacement: "until", explanation: "Spelling: \"until\" has one l", caseInsensitive: true),
        StyleRule(pattern: "\\btheir\\s+(is|are|was|were)\\b", replacement: "there $1", explanation: "Usage: use \"there\" for existence, not \"their\"", caseInsensitive: true),
        StyleRule(pattern: "\\byour\\s+(welcome|right|correct|going\\s+to)\\b", replacement: "you're $1", explanation: "Usage: use \"you're\" (you are) instead of possessive \"your\"", caseInsensitive: true),
        StyleRule(pattern: "\\b(more|less|better|worse|faster|higher|lower|greater|smaller)\\s+then\\b", replacement: "$1 than", explanation: "Usage: use \"than\" for comparisons, not \"then\"", caseInsensitive: true),
        // Conciseness & Style Guide (Strunk & White / Academic Style)
        StyleRule(pattern: "\\bdue to the fact that\\b", replacement: "because", explanation: "Style guide (conciseness): replace \"due to the fact that\" with \"because\"", caseInsensitive: true),
        StyleRule(pattern: "\\bin order to\\b", replacement: "to", explanation: "Style guide (conciseness): \"to\" is cleaner than \"in order to\"", caseInsensitive: true),
        StyleRule(pattern: "\\bat this point in time\\b", replacement: "now", explanation: "Style guide (conciseness): replace \"at this point in time\" with \"now\"", caseInsensitive: true),
        StyleRule(pattern: "\\bin the event that\\b", replacement: "if", explanation: "Style guide (conciseness): replace \"in the event that\" with \"if\"", caseInsensitive: true),
        StyleRule(pattern: "\\bfor the purpose of\\b", replacement: "to", explanation: "Style guide (conciseness): replace \"for the purpose of\" with \"to\"", caseInsensitive: true),
    ]

    public static func check(
        line: String,
        pageID: UUID,
        lineIndex: Int,
        strokeIndices: [Int],
        textBlockID: UUID?,
        bounds: CGRect
    ) -> WorkVerificationResult? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count >= 2 else { return nil }

        // 1. Check for accidental repeated words ("the the", "is is", "to to")
        for i in 1..<words.count {
            let prev = words[i - 1].trimmingCharacters(in: .punctuationCharacters)
            let curr = words[i].trimmingCharacters(in: .punctuationCharacters)
            if prev.count >= 2, prev.lowercased() == curr.lowercased() {
                var fixedWords = words
                fixedWords.remove(at: i)
                let fixed = fixedWords.joined(separator: " ")
                let msg = "Style check: repeated word \"\(curr)\""
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: trimmed,
                    normalizedExpression: fixed, category: .writingStyle,
                    status: .slip(expected: fixed, got: trimmed, explanation: msg),
                    message: msg,
                    suggestedCorrection: fixed
                )
            }
        }

        // 2. Check grammar, usage, and style guide rules
        for rule in rules {
            let options: NSString.CompareOptions = rule.caseInsensitive
                ? [.regularExpression, .caseInsensitive]
                : [.regularExpression]
            if let matchRange = trimmed.range(of: rule.pattern, options: options) {
                let matchedSubstring = String(trimmed[matchRange])
                var fixed = trimmed.replacingOccurrences(of: rule.pattern, with: rule.replacement, options: options)
                if matchRange.lowerBound == trimmed.startIndex, matchedSubstring.first?.isUppercase == true {
                    fixed = fixed.prefix(1).uppercased() + fixed.dropFirst()
                }
                return WorkVerificationResult(
                    pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                    textBlockID: textBlockID, bounds: bounds, rawText: trimmed,
                    normalizedExpression: fixed, category: .writingStyle,
                    status: .slip(expected: fixed, got: matchedSubstring, explanation: rule.explanation),
                    message: rule.explanation,
                    suggestedCorrection: fixed
                )
            }
        }

        // 3. Check unbalanced quotation marks or parentheses in multi-word prose sentences
        let quoteCount = trimmed.filter { $0 == "\"" || $0 == "“" || $0 == "”" }.count
        if quoteCount % 2 == 1 && words.count >= 4 {
            let fixed = trimmed + "\""
            let msg = "Punctuation check: unclosed quotation mark"
            return WorkVerificationResult(
                pageID: pageID, lineIndex: lineIndex, strokeIndices: strokeIndices,
                textBlockID: textBlockID, bounds: bounds, rawText: trimmed,
                normalizedExpression: fixed, category: .writingStyle,
                status: .slip(expected: fixed, got: trimmed, explanation: msg),
                message: msg,
                suggestedCorrection: fixed
            )
        }

        return nil
    }
}
