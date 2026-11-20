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
        // A short answer has no key terms, so the answer itself has to match; a blank attempt scores nothing.
        assert(WorkChecker.compareRecall(originalText: "42", attemptText: "").suggestedRating == 1)
        assert(WorkChecker.compareRecall(originalText: "x = 5", attemptText: "x=5").suggestedRating == 5)
        assert(WorkChecker.compareRecall(originalText: "Na", attemptText: "Cl").suggestedRating == 1)
        print("✓ 14. Active Recall verification summary: \(recall.feedback) (Suggested rating: \(recall.suggestedRating)/5)")

        // 15. Correct work must not be flagged: precedence, rounding, separators, mixed numbers
        for line in ["-3^2 = -9", "2^3^2 = 512", "2 * -3^2 = -18", "(-3)^2 = 9",
                     "22 / 7 = 3.14", "sqrt(2) = 1.414", "2 * pi = 6.28", "2/3 = 0.67", "2/3 = 0.66",
                     "1,000 + 500 = 1,500", "1 1/2 + 1/2 = 2", "2 * 1 1/2 = 3"] {
            let res = WorkChecker.evaluate(text: line, pageID: pageID, bounds: .zero)
            assert(res.isVerified, "\(line) should be verified, got: \(res.message)")
        }
        for line in ["7 / 2 = 3", "2/3 = 0.68", "2/3 = 0.6", "12.5 * 2 = 25.4"] {
            let res = WorkChecker.evaluate(text: line, pageID: pageID, bounds: .zero)
            assert(res.isSlip, "\(line) should be a slip, got: \(res.message)")
        }
        print("✓ 15. Precedence, rounded answers, thousands separators and mixed numbers")

        // 16. Equations with two solutions
        let negSquare = WorkChecker.evaluate(text: "-x^2 + 4 = 0", pageID: pageID, bounds: .zero)
        assert(negSquare.isVerified && negSquare.message.contains("-2, 2"), "-x^2 + 4 = 0 has roots -2, 2, got \(negSquare.message)")
        for line in ["x = 4", "x = -4", "x = 4 or x = -4", "x = ±4", "x = -4, 4"] {
            let res = WorkChecker.evaluate(text: line, pageID: pageID, bounds: .zero, previousLineText: "x^2 = 16")
            assert(res.isVerified, "\(line) after x^2 = 16 should be verified, got: \(res.message)")
        }
        let wrongRoot = WorkChecker.evaluate(text: "x = 5", pageID: pageID, bounds: .zero, previousLineText: "x^2 = 16")
        assert(wrongRoot.isSlip && wrongRoot.suggestedCorrection == "x = -4 or x = 4", "x = 5 after x^2 = 16 should suggest both roots, got \(String(describing: wrongRoot.suggestedCorrection))")
        let wrongList = WorkChecker.evaluate(text: "x = 4 or x = 5", pageID: pageID, bounds: .zero, previousLineText: "x^2 = 16")
        assert(wrongList.isSlip, "x = 4 or x = 5 after x^2 = 16 should be a slip")
        let noRealRoots = WorkChecker.evaluate(text: "x^2 + 1 = 0", pageID: pageID, bounds: .zero)
        assert(!noRealRoots.isSlip, "x^2 + 1 = 0 is a fair equation, got: \(noRealRoots.message)")
        print("✓ 16. Two-solution equations: \(wrongRoot.message)")

        // 17. Expansion slips name the bracketed side, whichever side it is on
        let expandLeft = WorkChecker.evaluate(text: "2(x + 3) = 2x + 9", pageID: pageID, bounds: .zero)
        assert(expandLeft.isSlip && expandLeft.suggestedCorrection == "2(x + 3) = 2x + 6")
        let expandRight = WorkChecker.evaluate(text: "2x + 6 = 2(x + 4)", pageID: pageID, bounds: .zero)
        assert(expandRight.isSlip && expandRight.suggestedCorrection == "2x + 8 = 2(x + 4)")
        print("✓ 17. Expansion slips: \(expandLeft.message)")

        // 18. A number, list number or date above a line is not the start of that calculation
        for previous in ["1.", "42", "2024", "11/20", "7"] {
            let res = WorkChecker.evaluate(text: "3 + 4 = 7", pageID: pageID, bounds: .zero, previousLineText: previous)
            assert(res.isVerified, "3 + 4 = 7 under \"\(previous)\" should be verified, got: \(res.message)")
        }
        let column = WorkChecker.evaluate(text: "8", pageID: pageID, bounds: .zero, previousLineText: "7")
        assert(!column.isSlip, "Two numbers on consecutive lines are not a step, got: \(column.message)")
        let carriedOn = WorkChecker.evaluate(text: "38 + 4 = 42", pageID: pageID, bounds: .zero, previousLineText: "12 * 3 + 4")
        assert(carriedOn.isSlip && carriedOn.suggestedCorrection == nil, "A line that carries on a calculation wrongly should still be caught")
        print("✓ 18. Unrelated neighbouring lines are left alone")

        // 19. Style fixes keep the sentence's capital letter
        let capital = WorkChecker.evaluate(text: "In order to win, we practice.", pageID: pageID, bounds: .zero)
        assert(capital.suggestedCorrection == "To win, we practice.", "got \(String(describing: capital.suggestedCorrection))")
        print("✓ 19. Style fix keeps capitalisation: \(capital.suggestedCorrection ?? "")")

        // 20. Units: a bare answer is read in the first unit, and fixes use the unit written
        let bareUnit = WorkChecker.evaluate(text: "50 cm + 50 cm = 100", pageID: pageID, bounds: .zero)
        assert(bareUnit.isVerified, "50 cm + 50 cm = 100 should be verified, got: \(bareUnit.message)")
        let wrongUnit = WorkChecker.evaluate(text: "2 km = 200 m", pageID: pageID, bounds: .zero)
        assert(wrongUnit.isSlip && wrongUnit.suggestedCorrection == "2000 m", "2 km = 200 m should suggest 2000 m, got \(String(describing: wrongUnit.suggestedCorrection))")
        print("✓ 20. Unit answers: \(wrongUnit.message)")

        let discount = WorkChecker.evaluate(text: "100 - 15% = 85", pageID: pageID, bounds: .zero)
        assert(discount.isVerified, "100 - 15% = 85 is right the way a calculator reads it, got: \(discount.message)")
        let algebraWithM = WorkChecker.evaluate(text: "5m = 500", pageID: pageID, bounds: .zero)
        assert(!algebraWithM.isSlip, "5m = 500 may be algebra, got: \(algebraWithM.message)")

        // 21. A whole page: one slip doesn't cascade, and a new problem starts fresh
        func checkPageLines(_ lines: [String]) -> [WorkVerificationResult] {
            let clusters = lines.enumerated().map { index, text in
                WorkLineCluster(index: index, strokeIndices: [], textBlockID: nil, bounds: .zero,
                                fingerprint: "\(index)", recognizedText: text)
            }
            return WorkChecker.checkLines(clusters, pageID: pageID)
        }
        let cascade = checkPageLines(["2x + 6 = 14", "2x = 20", "x = 4"])
        assert(cascade[1].isSlip && cascade[2].isVerified, "After the flagged 2x = 20, x = 4 is still right: \(cascade[2].message)")
        let twoProblems = checkPageLines(["2x + 6 = 14", "x = 4", "3x = 9", "x = 3"])
        assert(twoProblems.allSatisfy { $0.isVerified }, "A second problem isn't a step of the first: \(twoProblems.map(\.message))")
        let afterProse = checkPageLines(["2x = 8", "Now the next question", "5x = 10"])
        assert(afterProse[2].isVerified, "Prose ends a derivation: \(afterProse[2].message)")
        let bothRoots = checkPageLines(["x^2 = 16", "x = 4", "x = -4"])
        assert(bothRoots.allSatisfy { $0.isVerified }, "Each root on its own line is right: \(bothRoots.map(\.message))")
        print("✓ 21. Page context: slips don't cascade and new problems start fresh")

        print("✓ All 21 test groups passed!")
    }
}
