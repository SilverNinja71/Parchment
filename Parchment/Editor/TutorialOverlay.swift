import SwiftUI

/// Toolbar items the welcome tour can point at.
enum TutorialTarget: Hashable {
    case pen, convert, more, cover
}

struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TutorialTarget: Anchor<CGRect>], nextValue: () -> [TutorialTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks a control so the welcome tour can spotlight it.
    func tutorialAnchor(_ target: TutorialTarget) -> some View {
        anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

struct TutorialStep {
    let target: TutorialTarget
    let title: String
    let message: String

    /// One step per page of the "Welcome to Parchment" notebook.
    static let all = [
        TutorialStep(target: .pen, title: "Scratch-out to erase",
                     message: "Pick the Pen, then scribble back and forth over the words on this page. They disappear, no eraser needed."),
        TutorialStep(target: .convert, title: "Turn handwriting into text",
                     message: "Tap Convert, circle \"Meeting at 3 PM\" with your Pencil, then tap Convert in the sheet."),
        TutorialStep(target: .more, title: "Five kinds of paper",
                     message: "Open this menu and choose Paper Style… to switch this page between Lined, Grid, Dotted, Dotted-Lined and Blank."),
        TutorialStep(target: .cover, title: "Make it yours",
                     message: "Tap here to customize this notebook's cover: colors, finishes, the Cover Library or your own photo."),
    ]
}

/// A pulsing spotlight on the current target plus a tip card.
struct TutorialOverlay: View {
    let anchors: [TutorialTarget: Anchor<CGRect>]
    let step: TutorialStep
    let isLast: Bool
    var onNext: () -> Void
    var onFinish: () -> Void

    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            if let anchor = anchors[step.target] {
                let rect = proxy[anchor]
                ZStack(alignment: .topLeading) {
                    Circle()
                        .stroke(Style.selection, lineWidth: 3)
                        .frame(width: max(rect.width, rect.height) + 18, height: max(rect.width, rect.height) + 18)
                        .scaleEffect(pulse ? 1.25 : 0.95)
                        .opacity(pulse ? 0 : 0.9)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)

                    card
                        .frame(width: 320)
                        .position(x: min(max(rect.midX, 176), proxy.size.width - 176),
                                  y: rect.maxY + 96)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(step.title, systemImage: "sparkles").font(.headline).foregroundStyle(Style.selection)
            Text(step.message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip Tour", action: onFinish).font(.subheadline)
                Spacer()
                Button(isLast ? "Finish" : "Next Page", action: isLast ? onFinish : onNext)
                    .buttonStyle(.borderedProminent)
                    .font(.subheadline.bold())
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Style.cardRadius))
        .ambientShadow()
    }
}
