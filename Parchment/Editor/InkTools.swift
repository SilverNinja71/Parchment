import Foundation
import PencilKit

// MARK: - Math

/// Solves handwritten arithmetic: Vision reads the ink, this cleans up what it read
/// and evaluates it. Supports + − × ÷, powers, roots, percent, π and parentheses.
enum MathSolver {
    struct Solution {
        /// The calculation, written nicely ("12 × 3 + 4").
        let expression: String
        let answer: String
    }

    /// One solution per line that contains a calculation.
    static func solve(_ recognized: String) -> [Solution] {
        recognized.components(separatedBy: .newlines).compactMap { line in
            let expression = normalize(line)
            guard expression.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%")) != nil
                    || expression.contains("sqrt") || expression.contains("pi"),
                  let value = evaluate(expression), value.isFinite else { return nil }
            return Solution(expression: pretty(expression), answer: format(value))
        }
    }

    /// Turns what handwriting recognition read into a plain expression.
    static func normalize(_ raw: String) -> String {
        var text = raw
        // Anything after "=" is the (empty or old) answer.
        if let equals = text.firstIndex(of: "=") { text = String(text[..<equals]) }
        let replacements: [(String, String)] = [
            ("×", "*"), ("✕", "*"), ("∗", "*"), ("·", "*"), ("÷", "/"), (":", "/"),
            ("−", "-"), ("–", "-"), ("—", "-"), ("√", "sqrt"), ("π", "pi"),
            ("²", "^2"), ("³", "^3"), ("?", ""), (",", "."), (" ", ""),
        ]
        for (from, to) in replacements { text = text.replacingOccurrences(of: from, with: to) }
        // Common handwriting mix-ups next to digits: x→×, O→0, l/I/|→1.
        let fixes: [(String, String)] = [
            ("(?<=[0-9)])[xX](?=[0-9(])", "*"),
            ("(?<=[0-9])[oO]|[oO](?=[0-9])", "0"),
            ("(?<=[0-9])[lI|]|[lI|](?=[0-9])", "1"),
        ]
        for (pattern, replacement) in fixes {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return text
    }

    static func evaluate(_ expression: String) -> Double? {
        var parser = Parser(Array(expression.lowercased()))
        guard let value = parser.expression(), parser.isAtEnd else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        if abs(value - value.rounded()) < 1e-9, abs(value) < 1e15 { return String(Int(value.rounded())) }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func pretty(_ expression: String) -> String {
        var text = expression
        for (from, to) in [("*", " × "), ("/", " ÷ "), ("+", " + "), ("sqrt", "√"), ("pi", "π")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        // Spaced minus, but keep negative numbers like "-3" tight.
        text = text.replacingOccurrences(of: "(?<=[0-9)π])-", with: " − ", options: .regularExpression)
        return text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// expression = term (+|- term)* ; term = power ((*|/|implicit) power)* ;
    /// power = unary (^ power)? ; unary = -unary | postfix ; postfix = primary %?
    private struct Parser {
        let characters: [Character]
        var index = 0

        init(_ characters: [Character]) { self.characters = characters }

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
                } else if next == "(" || next == "s" || next == "p" {
                    // Implicit multiplication: 2(3+4), 2√9, 2π
                    guard let right = power() else { return nil }
                    value *= right
                } else {
                    break
                }
            }
            return value
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if current == "^" {
                index += 1
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func unary() -> Double? {
            if current == "-" { index += 1; return unary().map { -$0 } }
            if current == "+" { index += 1; return unary() }
            guard var value = primary() else { return nil }
            if current == "%" { index += 1; value /= 100 }
            return value
        }

        mutating func primary() -> Double? {
            if current == "(" {
                index += 1
                let value = expression()
                guard current == ")" else { return value } // forgive a missing ")"
                index += 1
                return value
            }
            if consume("sqrt") { return primary().map { $0.squareRoot() } }
            if consume("pi") { return .pi }
            var digits = ""
            while let character = current, character.isNumber || character == "." {
                digits.append(character)
                index += 1
            }
            return Double(digits)
        }

        private mutating func consume(_ word: String) -> Bool {
            let end = index + word.count
            guard end <= characters.count, String(characters[index..<end]) == word else { return false }
            index = end
            return true
        }
    }
}

// MARK: - Shapes

/// Diagram cleanup: recognizes hand-drawn lines, circles, ellipses, triangles,
/// rectangles and polygons, and redraws them neatly in the same ink.
enum ShapeRecognizer {
    static func cleaned(_ stroke: PKStroke) -> PKStroke? {
        let points = stroke.path.interpolatedPoints(by: .distance(3)).map { $0.location.applying(stroke.transform) }
        return outline(for: points).map { makeStroke(polyline: $0, like: stroke) }
    }

    /// The neat outline for a hand-drawn shape, or nil if it isn't one.
    static func outline(for points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 8, let first = points.first, let last = points.last else { return nil }

        let xs = points.map(\.x), ys = points.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let diagonal = hypot(box.width, box.height)
        guard diagonal > 20 else { return nil }

        // A straight line: no point strays far from the line between the two ends.
        let chord = distance(first, last)
        let wobble = points.map { distance($0, toLineFrom: first, to: last) }.max() ?? 0
        if chord > 30, wobble < max(5, chord * 0.06) {
            var end = last
            let angle = atan2(last.y - first.y, last.x - first.x)
            let snap = CGFloat.pi / 2
            let nearest = (angle / snap).rounded() * snap
            if abs(angle - nearest) < .pi / 22 { // within ~8°: make it level or upright
                let span = distance(first, last)
                end = CGPoint(x: first.x + cos(nearest) * span, y: first.y + sin(nearest) * span)
            }
            return [first, end]
        }

        // Everything else must be a closed shape.
        guard distance(first, last) < max(box.width, box.height) * 0.25 else { return nil }

        let center = CGPoint(x: box.midX, y: box.midY)
        let rx = max(box.width / 2, 1), ry = max(box.height / 2, 1)
        let ellipseError = points.reduce(0) { total, point in
            total + abs(hypot((point.x - center.x) / rx, (point.y - center.y) / ry) - 1)
        } / CGFloat(points.count)

        var corners = simplify(points, epsilon: diagonal * 0.08)
        if corners.count > 2, distance(corners.first!, corners.last!) < diagonal * 0.15 { corners.removeLast() }

        if (3...4).contains(corners.count), ellipseError > 0.07 {
            if corners.count == 4, isAxisAlignedRectangle(corners) {
                return [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                                             CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY),
                                             CGPoint(x: box.minX, y: box.minY)]
            }
            return corners + [corners[0]]
        }
        if ellipseError < 0.14 {
            var radiusX = rx, radiusY = ry
            if abs(rx - ry) / max(rx, ry) < 0.12 { radiusX = (rx + ry) / 2; radiusY = radiusX } // a circle
            let outline = (0...72).map { step -> CGPoint in
                let angle = CGFloat(step) / 72 * 2 * .pi
                return CGPoint(x: center.x + cos(angle) * radiusX, y: center.y + sin(angle) * radiusY)
            }
            return outline
        }
        if (5...8).contains(corners.count) {
            return corners + [corners[0]]
        }
        return nil
    }

    private static func isAxisAlignedRectangle(_ corners: [CGPoint]) -> Bool {
        for index in 0..<4 {
            let a = corners[index], b = corners[(index + 1) % 4]
            let angle = abs(atan2(b.y - a.y, b.x - a.x))
            let fromAxis = min(angle, abs(angle - .pi / 2), abs(angle - .pi))
            if fromAxis > .pi / 12 { return false } // more than 15° off level/upright
        }
        return true
    }

    /// Ramer–Douglas–Peucker: keeps only the points where the outline really turns.
    private static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var farthest = 0
        var maxDistance: CGFloat = 0
        for index in 1..<(points.count - 1) {
            let d = distance(points[index], toLineFrom: first, to: last)
            if d > maxDistance { maxDistance = d; farthest = index }
        }
        guard maxDistance > epsilon else { return [first, last] }
        let left = simplify(Array(points[...farthest]), epsilon: epsilon)
        let right = simplify(Array(points[farthest...]), epsilon: epsilon)
        return left.dropLast() + right
    }

    private static func distance(_ point: CGPoint, toLineFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let span = hypot(dx, dy)
        guard span > 0 else { return distance(point, a) }
        return abs(dy * point.x - dx * point.y + b.x * a.y - b.y * a.x) / span
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// A neat stroke along `polyline`, in the same ink and thickness as the original.
    private static func makeStroke(polyline: [CGPoint], like original: PKStroke) -> PKStroke {
        var samples: [CGPoint] = []
        for (a, b) in zip(polyline, polyline.dropFirst()) {
            let steps = max(1, Int(distance(a, b) / 4))
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                samples.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        if let end = polyline.last { samples.append(end) }

        let size = original.path.first?.size ?? CGSize(width: 3, height: 3)
        let points = samples.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.005, size: size,
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: original.ink, path: PKStrokePath(controlPoints: points, creationDate: original.path.creationDate))
    }
}
