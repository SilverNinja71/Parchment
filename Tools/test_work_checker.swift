import Foundation
import CoreGraphics
import PencilKit

// Minimal host shims so WorkChecker + InkTools can be unit-tested standalone in <2s
struct TextBlock: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var fontSize: Double = 22
    var flows: Bool?
}

enum PaperBackgroundView {
    static let lineSpacing: CGFloat = 34
}

enum HandwritingRecognizer {
    static func recognize(_ drawing: PKDrawing, language: String) async throws -> String { "" }
}

@main
struct WorkCheckerTestSuite {
    static func main() {
        print("Running comprehensive WorkChecker test suite...")

        let pageID = UUID()

        // 1. Arithmetic equality verified
        let r1 = WorkChecker.evaluate(text: "14 * 3 = 42", pageID: pageID, bounds: .zero)
        assert(r1.isVerified, "14 * 3 = 42 should be verified")
        print("✓ 1. Arithmetic equality verified: \(r1.message)")

        // 2. Arithmetic slip detection
        let r2 = WorkChecker.evaluate(text: "14 * 3 = 48", pageID: pageID, bounds: .zero)
        assert(r2.isSlip && r2.suggestedCorrection == "42", "14 * 3 = 48 should catch slip and suggest 42")
        print("✓ 2. Arithmetic slip caught: \(r2.message)")

        // 3. Chained equality verified
        let r3 = WorkChecker.evaluate(text: "12 * 3 + 4 = 36 + 4 = 40", pageID: pageID, bounds: .zero)
        assert(r3.isVerified, "Chained equality 12 * 3 + 4 = 36 + 4 = 40 should be verified")
        print("✓ 3. Chained equality verified: \(r3.message)")

        // 4. Chained equality slip
        let r4 = WorkChecker.evaluate(text: "12 * 3 + 4 = 38 + 4 = 42", pageID: pageID, bounds: .zero)
        assert(r4.isSlip && r4.suggestedCorrection == "40", "Broken chain should suggest 40")
        print("✓ 4. Chained equality slip caught: \(r4.message)")

        // 5. Algebraic multi-step derivation (valid)
        let alg1 = WorkChecker.evaluate(text: "2x + 6 = 14", pageID: pageID, bounds: .zero)
        assert(alg1.isVerified && alg1.suggestedCorrection == "x = 4", "First algebra step should track root x = 4")
        let alg2 = WorkChecker.evaluate(text: "2x = 8", pageID: pageID, bounds: .zero, previousLineText: "2x + 6 = 14")
        assert(alg2.isVerified, "Second algebra step 2x = 8 should be verified")
        let alg3 = WorkChecker.evaluate(text: "x = 4", pageID: pageID, bounds: .zero, previousLineText: "2x = 8")
        assert(alg3.isVerified, "Final algebra step x = 4 should be verified")
        print("✓ 5. Multi-step linear algebra derivation verified: 2x + 6 = 14 → 2x = 8 → x = 4")

        // 6. Algebraic sign slip (added 6 instead of subtracting 6)
        let algSlip = WorkChecker.evaluate(text: "2x = 20", pageID: pageID, bounds: .zero, previousLineText: "2x + 6 = 14")
        assert(algSlip.isSlip && algSlip.suggestedCorrection == "2x = 8", "Sign slip 2x = 20 should suggest 2x = 8, got \(String(describing: algSlip.suggestedCorrection))")
        print("✓ 6. Algebraic sign slip caught: \(algSlip.message)")

        // 7. Algebraic distribution slip: 3(x - 2) = 12 -> 3x - 2 = 12
        let distSlip = WorkChecker.evaluate(text: "3x - 2 = 12", pageID: pageID, bounds: .zero, previousLineText: "3(x - 2) = 12")
        assert(distSlip.isSlip && distSlip.suggestedCorrection == "3x − 6 = 12", "Distribution slip should suggest 3x − 6 = 12, got \(String(describing: distSlip.suggestedCorrection))")
        print("✓ 7. Algebraic distribution slip caught: \(distSlip.message)")

        // 8. Quadratic equation root tracking: x^2 - 5x + 6 = 0
        let quad = WorkChecker.evaluate(text: "x^2 - 5x + 6 = 0", pageID: pageID, bounds: .zero)
        assert(quad.isVerified && quad.message.contains("2, 3"), "Quadratic should find roots 2, 3, got \(quad.message)")
        print("✓ 8. Quadratic equation roots verified: \(quad.message)")

        // 9. Polynomial expansion step verification: (x + 2)(x + 3) -> x^2 + 5x + 6
        let polyValid = WorkChecker.evaluate(text: "x^2 + 5x + 6", pageID: pageID, bounds: .zero, previousLineText: "(x + 2)(x + 3)")
        assert(polyValid.isVerified, "Polynomial expansion (x+2)(x+3) -> x^2+5x+6 should be verified")
        print("✓ 9. Polynomial expansion verified: \(polyValid.message)")

        // 10. Polynomial expansion slip: (x + 2)(x + 3) -> x^2 + 6x + 6
        let polySlip = WorkChecker.evaluate(text: "x^2 + 6x + 6", pageID: pageID, bounds: .zero, previousLineText: "(x + 2)(x + 3)")
        assert(polySlip.isSlip && polySlip.suggestedCorrection == "x² + 5x + 6", "Polynomial slip should suggest x² + 5x + 6")
        print("✓ 10. Polynomial expansion slip caught: \(polySlip.message)")

        // 11. Trigonometry, roots, percentages, factorials
        let trig = WorkChecker.evaluate(text: "sin(30) + sqrt(144) = 12.5", pageID: pageID, bounds: .zero)
        assert(trig.isVerified, "sin(30) + sqrt(144) = 12.5 should be verified")
        let pct = WorkChecker.evaluate(text: "15% of 80 = 12", pageID: pageID, bounds: .zero)
        assert(pct.isVerified, "15% of 80 = 12 should be verified")
        let fact = WorkChecker.evaluate(text: "5! = 120", pageID: pageID, bounds: .zero)
        assert(fact.isVerified, "5! = 120 should be verified")
        print("✓ 11. Trig, roots, percentages, and factorials verified")

        // 12. Dimensional unit conversion check: 5 m + 30 cm = 5.3 m
        let unitValid = WorkChecker.evaluate(text: "5 m + 30 cm = 5.3 m", pageID: pageID, bounds: .zero)
        assert(unitValid.isVerified, "5 m + 30 cm = 5.3 m should be verified")
        let unitSlip = WorkChecker.evaluate(text: "5 m + 30 cm = 35 m", pageID: pageID, bounds: .zero)
        assert(unitSlip.isSlip && unitSlip.suggestedCorrection == "5.3 m", "5 m + 30 cm = 35 m should suggest 5.3 m")
        print("✓ 12. Unit conversion verified & unit slip caught: \(unitSlip.message)")

        // 13. Prose Writing & Style Guide checks
        let style1 = WorkChecker.evaluate(text: "We could of finished earlier.", pageID: pageID, bounds: .zero)
        assert(style1.isSlip && style1.category == .writingStyle && style1.suggestedCorrection == "We could have finished earlier.")
        let style2 = WorkChecker.evaluate(text: "Check the the second paragraph.", pageID: pageID, bounds: .zero)
        assert(style2.isSlip && style2.suggestedCorrection == "Check the second paragraph.")
        let style3 = WorkChecker.evaluate(text: "Due to the fact that it rained, we stayed inside.", pageID: pageID, bounds: .zero)
        assert(style3.isSlip && style3.category == .writingStyle)
        print("✓ 13. Writing & style guide checks verified: \(style1.message) | \(style2.message) | \(style3.message)")

        // 14. Active Recall comparison check
        let recall = WorkChecker.compareRecall(
            originalText: "Mitosis has four phases: prophase, metaphase, anaphase, telophase. 2x + 6 = 14, x = 4",
            attemptText: "Mitosis phases: prophase, metaphase, anaphase. 2x + 6 = 14, x = 4"
        )
        assert(recall.matchedTerms.contains("prophase") && recall.missedTerms.contains("telophase"))
        assert(!recall.verifiedEquations.isEmpty)
        print("✓ 14. Active Recall verification summary: \(recall.feedback) (Suggested rating: \(recall.suggestedRating)/5)")

        print("✓ All 14 test groups passed!")
    }
}
