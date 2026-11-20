import SwiftUI
import UIKit
import PencilKit

// MARK: - On-Canvas Line Follower & Margin Annotation Layer (UIKit)

/// Renders live line-tracking indicators, dashed slip underlines, and interactive margin pills
/// directly in `PKCanvasView` page coordinates (scaling smoothly with zoom and scroll).
final class WorkAnnotationLayerView: UIView {
    var onTapBadge: ((WorkVerificationResult) -> Void)?
    var onQuickFix: ((WorkVerificationResult) -> Void)?

    private var results: [WorkVerificationResult] = []
    private var followerState = WorkFollowerState()
    private var currentZoom: CGFloat = 1.0
    private var pageSize: CGSize = .zero
    private var badgeButtons: [UUID: UIButton] = [:]

    private let activeLineLayer = CAShapeLayer()
    private let penCursorLayer = CAShapeLayer()
    private let underlineLayer = CAShapeLayer()

    /// Style guide colors matching `Style.swift`
    private static let verifiedUIColor = UIColor(red: 0.18, green: 0.58, blue: 0.32, alpha: 1)
    private static let slipUIColor = UIColor(red: 0.82, green: 0.28, blue: 0.14, alpha: 1)
    private static let accentUIColor = UIColor(red: 0x0A / 255.0, green: 0x60 / 255.0, blue: 0xFF / 255.0, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        // Active line left margin indicator bar
        activeLineLayer.fillColor = Self.accentUIColor.withAlphaComponent(0.18).cgColor
        activeLineLayer.strokeColor = Self.accentUIColor.withAlphaComponent(0.65).cgColor
        activeLineLayer.lineWidth = 2
        layer.addSublayer(activeLineLayer)

        // Subtle pen tip follower halo
        penCursorLayer.fillColor = Self.accentUIColor.withAlphaComponent(0.22).cgColor
        penCursorLayer.strokeColor = Self.accentUIColor.cgColor
        penCursorLayer.lineWidth = 1.5
        layer.addSublayer(penCursorLayer)

        // Dashed terracotta underline for lines with calculation or style slips
        underlineLayer.fillColor = UIColor.clear.cgColor
        underlineLayer.strokeColor = Self.slipUIColor.withAlphaComponent(0.75).cgColor
        underlineLayer.lineWidth = 2
        underlineLayer.lineDashPattern = [5, 4]
        layer.addSublayer(underlineLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(results: [WorkVerificationResult], follower: WorkFollowerState) {
        let actionable = results.filter { $0.status != .inconclusive }
        self.results = actionable
        self.followerState = follower
        syncBadgeButtons()
        layoutAnnotations()
    }

    func layout(pageSize: CGSize, zoom: CGFloat) {
        self.pageSize = pageSize
        self.currentZoom = zoom
        frame = CGRect(x: 0, y: 0, width: pageSize.width * zoom, height: pageSize.height * zoom)
        layoutAnnotations()
    }

    private func syncBadgeButtons() {
        let keepIDs = Set(results.map(\.id))
        for (id, button) in badgeButtons where !keepIDs.contains(id) {
            button.removeFromSuperview()
            badgeButtons[id] = nil
        }

        for result in results where badgeButtons[result.id] == nil {
            let button = UIButton(type: .system)
            button.layer.cornerRadius = 11
            button.layer.masksToBounds = false
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.08
            button.layer.shadowRadius = 6
            button.layer.shadowOffset = CGSize(width: 0, height: 2)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleBadgeTap(_:)))
            // Fingers tap badges; Apple Pencil writes right through them.
            tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            button.addGestureRecognizer(tap)

            addSubview(button)
            badgeButtons[result.id] = button
        }
    }

    private func layoutAnnotations() {
        let z = max(currentZoom, 0.25)

        // 1. Active writing line bar & pen follower dot
        if case .following = followerState.phase, let band = followerState.activeBand, !band.isNull {
            let barX = max(12 * z, (band.minX - 14) * z)
            let barRect = CGRect(
                x: barX,
                y: (band.minY - 2) * z,
                width: 3.5 * z,
                height: max(18, band.height + 4) * z
            )
            activeLineLayer.path = UIBezierPath(roundedRect: barRect, cornerRadius: 2 * z).cgPath
            activeLineLayer.isHidden = false

            if let pt = followerState.lastWritingPoint {
                let r = 5.0 * z
                let dotRect = CGRect(x: pt.x * z - r, y: pt.y * z - r, width: r * 2, height: r * 2)
                penCursorLayer.path = UIBezierPath(ovalIn: dotRect).cgPath
                penCursorLayer.isHidden = false
            } else {
                penCursorLayer.isHidden = true
            }
        } else {
            activeLineLayer.isHidden = true
            penCursorLayer.isHidden = true
        }

        // 2. Dashed underlines & inline margin badges for each checked line
        let underlinePath = UIBezierPath()

        for result in results {
            let box = result.bounds
            if result.isSlip, !box.isNull, !box.isEmpty {
                let y = (box.maxY + 3) * z
                underlinePath.move(to: CGPoint(x: box.minX * z, y: y))
                underlinePath.addLine(to: CGPoint(x: box.maxX * z, y: y))
            }

            guard let button = badgeButtons[result.id] else { continue }
            configureBadge(button, for: result, zoom: z)

            let fitted = button.sizeThatFits(CGSize(width: 280 * z, height: 34 * z))
            let badgeW = min(max(fitted.width + 18 * z, 54 * z), 260 * z)
            let badgeH = max(fitted.height + 6 * z, 22 * z)

            // Position right beside the written line, clamped inside page width
            let maxPageX = max(badgeW + 12 * z, pageSize.width * z - badgeW - 12 * z)
            let x = min((box.maxX + 14) * z, maxPageX)
            let y = max(8 * z, box.midY * z - badgeH / 2)
            button.frame = CGRect(x: x, y: y, width: badgeW, height: badgeH)
            button.layer.cornerRadius = badgeH / 2
        }

        underlineLayer.path = underlinePath.cgPath
        underlineLayer.lineWidth = max(1.5, 2.0 * z)
    }

    private func configureBadge(_ button: UIButton, for result: WorkVerificationResult, zoom: CGFloat) {
        let fontSize = max(10, min(14, 12 * zoom))
        button.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .semibold)
        button.titleLabel?.lineBreakMode = .byTruncatingTail

        switch result.status {
        case .verified:
            let label = result.category == .algebra ? "✓ \(result.message.replacingOccurrences(of: "Verified: ", with: ""))" : "✓ Verified"
            button.setTitle(label, for: .normal)
            button.setTitleColor(Self.verifiedUIColor, for: .normal)
            button.backgroundColor = Self.verifiedUIColor.withAlphaComponent(0.12)
            button.layer.borderColor = Self.verifiedUIColor.withAlphaComponent(0.32).cgColor
            button.layer.borderWidth = 1

        case .slip(let expected, _, _):
            let label = result.category == .writingStyle ? "⚠ Style: \(expected)" : "⚠ Check → \(expected)"
            button.setTitle(label, for: .normal)
            button.setTitleColor(Self.slipUIColor, for: .normal)
            button.backgroundColor = Self.slipUIColor.withAlphaComponent(0.14)
            button.layer.borderColor = Self.slipUIColor.withAlphaComponent(0.40).cgColor
            button.layer.borderWidth = 1

        case .evaluated(let answer):
            button.setTitle("= \(answer)  + Add", for: .normal)
            button.setTitleColor(Self.accentUIColor, for: .normal)
            button.backgroundColor = Self.accentUIColor.withAlphaComponent(0.12)
            button.layer.borderColor = Self.accentUIColor.withAlphaComponent(0.32).cgColor
            button.layer.borderWidth = 1

        case .inconclusive:
            break
        }
    }

    @objc private func handleBadgeTap(_ gesture: UITapGestureRecognizer) {
        guard let button = gesture.view as? UIButton,
              let id = badgeButtons.first(where: { $0.value === button })?.key,
              let result = results.first(where: { $0.id == id }) else { return }
        Style.tap()
        if result.isEvaluated {
            onQuickFix?(result)
        } else {
            onTapBadge?(result)
        }
    }

    // Only finger taps on the badge buttons are captured; Apple Pencil and canvas touches pass through.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let touches = event?.allTouches, touches.contains(where: { $0.type == .pencil }) {
            return nil
        }
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

// MARK: - Floating Work Follower & Step Inspector Pill (SwiftUI)

/// Floating status pill and multi-step inspector for `NotebookView`.
///
/// Follows the user's active writing state and displays step verification, calculation slips,
/// and style guide suggestions strictly following `Style.swift`.
struct WorkFollowerView: View {
    @ObservedObject var editor: EditorModel
    let onApplyCorrection: (WorkVerificationResult, String) -> Void

    @State private var showDetails = false

    private let verifiedGreen = Color(red: 0.18, green: 0.58, blue: 0.32)
    private let slipTerracotta = Color(red: 0.82, green: 0.28, blue: 0.14)

    private var actionableResults: [WorkVerificationResult] {
        editor.pageWorkResults.filter { $0.status != .inconclusive }
    }

    var body: some View {
        Group {
            if let result = editor.workCheckResult {
                resultPill(result)
            } else if case .following(let strokes) = editor.followerState.phase, strokes > 0, editor.tool == .pen {
                followingIndicator(strokeCount: strokes)
            } else if case .verifying = editor.followerState.phase, editor.tool == .pen {
                verifyingIndicator
            }
        }
        .animation(Style.spring, value: editor.workCheckResult)
        .animation(Style.spring, value: editor.followerState.phase)
    }

    // MARK: - Follower Indicator (Active Writing)

    private func followingIndicator(strokeCount: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Style.selection)
                .frame(width: 8, height: 8)

            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Style.selection)

            Text("Following work…")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if !actionableResults.isEmpty {
                let verifiedCount = actionableResults.filter(\.isVerified).count
                let slipCount = actionableResults.filter(\.isSlip).count
                Divider().frame(height: 14)
                Text("\(verifiedCount) ✓" + (slipCount > 0 ? " · \(slipCount) ⚠" : ""))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(slipCount > 0 ? slipTerracotta : verifiedGreen)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .ambientShadow()
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var verifyingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
            Text("Checking step…")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .ambientShadow()
        .transition(.opacity)
    }

    // MARK: - Work Result Pill

    private func resultPill(_ result: WorkVerificationResult) -> some View {
        let verifiedCount = actionableResults.filter(\.isVerified).count
        let slipCount = actionableResults.filter(\.isSlip).count

        return HStack(spacing: 10) {
            // Status Icon
            Group {
                switch result.status {
                case .verified:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(verifiedGreen)
                case .slip:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(slipTerracotta)
                case .evaluated:
                    Image(systemName: "equal.circle.fill")
                        .foregroundStyle(Style.selection)
                case .inconclusive:
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 18, weight: .semibold))

            // Main Message + Page Step Summary
            Button {
                Style.tap()
                showDetails.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.category.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(badgeTint(for: result).opacity(0.14), in: Capsule())
                            .foregroundStyle(badgeTint(for: result))

                        if actionableResults.count > 1 {
                            Text("Line \(result.lineIndex + 1) · \(verifiedCount) verified\(slipCount > 0 ? ", \(slipCount) to review" : "")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(result.message)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(result.isSlip ? slipTerracotta : .primary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            // One-tap Action Button
            if let correction = result.suggestedCorrection {
                Button {
                    Style.tap()
                    onApplyCorrection(result, correction)
                } label: {
                    Text(result.isSlip ? "Fix: \(correction)" : "Add = \(correction)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(result.isSlip ? slipTerracotta : Style.accent, in: Capsule())
                }
            }

            // Inspect all steps button
            Button {
                Style.tap()
                showDetails.toggle()
            } label: {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .accessibilityLabel("Inspect all steps")

            // Dismiss button
            Button {
                Style.tap()
                withAnimation(Style.spring) {
                    editor.workCheckResult = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .accessibilityLabel("Dismiss work check")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Style.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Style.cardRadius)
                .strokeBorder(badgeTint(for: result).opacity(0.32), lineWidth: 1)
        )
        .ambientShadow()
        .popover(isPresented: $showDetails) {
            WorkDetailPopover(
                selectedResult: result,
                allResults: actionableResults,
                onApplyCorrection: onApplyCorrection
            )
            .presentationCompactAdaptation(.popover)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func badgeTint(for result: WorkVerificationResult) -> Color {
        if result.isSlip { return slipTerracotta }
        if result.isVerified { return verifiedGreen }
        return Style.selection
    }
}

// MARK: - Multi-Step Work Detail Popover

struct WorkDetailPopover: View {
    let selectedResult: WorkVerificationResult
    let allResults: [WorkVerificationResult]
    let onApplyCorrection: (WorkVerificationResult, String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let verifiedGreen = Color(red: 0.18, green: 0.58, blue: 0.32)
    private let slipTerracotta = Color(red: 0.82, green: 0.28, blue: 0.14)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Work Check & Step Log", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Style.accent)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Selected Line Detail
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Line \(selectedResult.lineIndex + 1) · \(selectedResult.category.rawValue)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text(selectedResult.rawText)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.chrome, in: RoundedRectangle(cornerRadius: Style.controlRadius))

                Text(selectedResult.message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(selectedResult.isSlip ? slipTerracotta : .primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.paper, in: RoundedRectangle(cornerRadius: Style.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Style.controlRadius)
                            .strokeBorder(Color.hairline, lineWidth: 1)
                    )

                if let correction = selectedResult.suggestedCorrection {
                    Button {
                        Style.tap()
                        onApplyCorrection(selectedResult, correction)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text(selectedResult.isSlip ? "Apply Fix: \(correction)" : "Insert Answer: = \(correction)")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedResult.isSlip ? slipTerracotta : Style.accent)
                }
            }

            // Full Page Step-by-Step History
            if allResults.count > 1 {
                Divider()
                Text("All Steps on This Page (\(allResults.count))")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(allResults) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isSlip ? "exclamationmark.triangle.fill" : item.isVerified ? "checkmark.circle.fill" : "equal.circle.fill")
                                    .foregroundStyle(item.isSlip ? slipTerracotta : item.isVerified ? verifiedGreen : Style.selection)
                                    .font(.caption)

                                Text("L\(item.lineIndex + 1):")
                                    .font(.caption.monospacedDigit().bold())
                                    .foregroundStyle(.secondary)

                                Text(item.rawText)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)

                                Spacer()

                                if let fix = item.suggestedCorrection, item.isSlip {
                                    Button("Fix") {
                                        Style.tap()
                                        onApplyCorrection(item, fix)
                                        dismiss()
                                    }
                                    .font(.caption2.bold())
                                    .buttonStyle(.bordered)
                                    .tint(slipTerracotta)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.paper, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

// MARK: - Active Recall & Flashcard Work Check Summary Card

/// Shown in `RecallSessionView` and `FlashcardReviewView` when comparing the user's
/// handwritten rewrite against the original page or card.
struct RecallWorkSummaryCard: View {
    let summary: RecallVerificationSummary
    var onApplySuggestedRating: ((Int) -> Void)?

    private let verifiedGreen = Color(red: 0.18, green: 0.58, blue: 0.32)
    private let slipTerracotta = Color(red: 0.82, green: 0.28, blue: 0.14)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                let pct = Int((summary.accuracy * 100).rounded())
                Text("\(pct)%")
                    .font(.system(.title3, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(pct >= 75 ? verifiedGreen : pct >= 45 ? Style.accent : slipTerracotta, in: Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Work Check Summary")
                        .font(.subheadline.bold())
                    Text(summary.feedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let onApplySuggestedRating {
                    Button {
                        Style.tap()
                        onApplySuggestedRating(summary.suggestedRating)
                    } label: {
                        Text("Rate \(summary.suggestedRating)/5")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(Style.accent)
                }
            }

            if !summary.matchedTerms.isEmpty || !summary.missedTerms.isEmpty || !summary.equationSlips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(summary.verifiedEquations.prefix(4), id: \.self) { eq in
                            chip("✓ \(eq)", color: verifiedGreen)
                        }
                        ForEach(summary.equationSlips.prefix(3), id: \.self) { slip in
                            chip("⚠ \(slip)", color: slipTerracotta)
                        }
                        ForEach(summary.matchedTerms.prefix(6), id: \.self) { term in
                            chip("✓ \(term)", color: verifiedGreen)
                        }
                        ForEach(summary.missedTerms.prefix(6), id: \.self) { term in
                            chip("Missed: \(term)", color: slipTerracotta)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: Style.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Style.cardRadius)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        .ambientShadow()
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}
