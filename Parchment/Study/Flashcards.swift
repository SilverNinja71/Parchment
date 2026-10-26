import SwiftUI
import PencilKit

private struct ReviewTarget: Identifiable {
    let id = UUID()
    let deckID: UUID?
    let title: String
}

/// Study → Flashcards: Anki-style deck list with New and Due counts.
struct FlashcardsHomeView: View {
    @EnvironmentObject private var study: StudyStore
    @EnvironmentObject private var store: NotebookStore
    @State private var review: ReviewTarget?
    @State private var newDeckName = ""
    @State private var newDeckSubject: String?
    @State private var addingDeck = false
    @State private var renaming: Deck?
    @State private var deleting: Deck?

    var body: some View {
        List {
            Section {
                StudyHeader(
                    title: "Flashcards",
                    message: "See the front, flip it, write the answer from memory, rate yourself 1–5, then check. Cards you struggle with come back sooner.",
                    icon: .flashcards)
                let total = study.counts(for: nil)
                Button {
                    review = ReviewTarget(deckID: nil, title: "All Decks")
                } label: {
                    Label { Text("Study All Decks (\(total.new + total.due))") } icon: { ThemedIcon(.study, size: 20) }
                        .frame(maxWidth: .infinity).bold()
                }
                .buttonStyle(.borderedProminent)
                .disabled(total.new + total.due == 0)
                .listRowBackground(Color.clear)
            }

            Section {
                if study.decks.isEmpty {
                    Text("No decks yet. Make one, then add cards by writing a front and a back.")
                        .foregroundStyle(.secondary)
                }
                ForEach(study.decks) { deck in
                    let counts = study.counts(for: deck.id)
                    NavigationLink {
                        DeckDetailView(deckID: deck.id)
                    } label: {
                        HStack(spacing: 12) {
                            ThemedIcon(.deck, size: 24).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                HandwrittenText(deck.name, size: 18)
                                if let subject = deck.subject {
                                    Text(subject).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            countColumn(counts.new, color: .blue)
                            countColumn(counts.due, color: .green)
                        }
                    }
                    .contextMenu {
                        Button("Rename") { newDeckName = deck.name; renaming = deck }
                        Button("Delete Deck", role: .destructive) { deleting = deck }
                    }
                }
            } header: {
                HStack {
                    Text("Decks")
                    Spacer()
                    Text("New").frame(width: 50)
                    Text("Due").frame(width: 50)
                }
            }
        }
        .navigationTitle("Flashcards")
        .toolbar {
            Button {
                newDeckName = ""
                newDeckSubject = nil
                addingDeck = true
            } label: { Label("New Deck", systemImage: "plus") }
        }
        .sheet(isPresented: $addingDeck) {
            NavigationStack {
                Form {
                    TextField("Deck name (e.g. Biology – Cells)", text: $newDeckName)
                    Picker("Subject", selection: $newDeckSubject) {
                        Text("None").tag(String?.none)
                        ForEach(store.subjects) { Text($0.name).tag(String?.some($0.name)) }
                    }
                }
                .navigationTitle("New Deck")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { addingDeck = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            study.addDeck(name: newDeckName.trimmingCharacters(in: .whitespaces), subject: newDeckSubject)
                            addingDeck = false
                        }
                        .bold()
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Rename Deck", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newDeckName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if let deck = renaming { study.renameDeck(deck.id, to: newDeckName) } }
        }
        .confirmationDialog("Delete \"\(deleting?.name ?? "")\" and all its cards?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Deck", role: .destructive) { if let deck = deleting { study.deleteDeck(deck.id) } }
        }
        .fullScreenCover(item: $review) { target in
            FlashcardReviewView(deckID: target.deckID, title: target.title)
        }
    }

    private func countColumn(_ value: Int, color: Color) -> some View {
        Text("\(value)")
            .font(.body.monospacedDigit().bold())
            .foregroundStyle(value == 0 ? Color.secondary : color)
            .frame(width: 50)
    }
}

/// One deck: its cards, plus Study and Add Card.
struct DeckDetailView: View {
    let deckID: UUID
    @EnvironmentObject private var study: StudyStore
    @State private var editing: Flashcard?
    @State private var review: ReviewTarget?

    private var deck: Deck? { study.decks.first { $0.id == deckID } }

    var body: some View {
        let cards = study.cards(in: deckID)
        let counts = study.counts(for: deckID)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 24) {
                    stat("New", counts.new, .blue)
                    stat("Due", counts.due, .green)
                    stat("Total", cards.count, .secondary)
                    Spacer()
                    Button {
                        review = ReviewTarget(deckID: deckID, title: deck?.name ?? "Deck")
                    } label: {
                        Label { Text("Study Now") } icon: { ThemedIcon(.study, size: 20) }.bold()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(counts.new + counts.due == 0)
                }

                if cards.isEmpty {
                    ContentUnavailableView("No cards yet", systemImage: "rectangle.on.rectangle.angled",
                                           description: Text("Tap Add Card, write a question on the front and the answer on the back."))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 18) {
                    ForEach(cards) { card in
                        Button { editing = card } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CardFaceView(card: card, side: .front)
                                    .frame(height: 150)
                                Text(card.schedule.isNew ? "New"
                                     : card.schedule.isDue() ? "Due now"
                                     : "Next review \(card.schedule.due.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete Card", role: .destructive) { study.deleteCard(card.id) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(deck?.name ?? "Deck")
        .toolbar {
            Button {
                editing = Flashcard(deckID: deckID)
            } label: { Label("Add Card", systemImage: "plus") }
        }
        .sheet(item: $editing) { card in
            CardEditorView(card: card)
        }
        .fullScreenCover(item: $review) { target in
            FlashcardReviewView(deckID: target.deckID, title: target.title)
        }
    }

    private func stat(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading) {
            Text("\(value)").font(.title.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Write (or type) the front and back of a card.
struct CardEditorView: View {
    @State var card: Flashcard
    @EnvironmentObject private var study: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var front = PKDrawing()
    @State private var back = PKDrawing()
    @State private var frontInk = SketchInk.pen(0)
    @State private var backInk = SketchInk.pen(0)
    @State private var loaded = false

    private var isNew: Bool { study.card(card.id) == nil }

    var body: some View {
        NavigationStack {
            HStack(spacing: 20) {
                side("Front", hint: "Question, term or picture", text: $card.frontText, drawing: $front, ink: $frontInk)
                side("Back", hint: "Answer you'll have to write", text: $card.backText, drawing: $back, ink: $backInk)
            }
            .padding(20)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(isNew ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if isNew {
                        Button("Save & Add Another") {
                            save()
                            card = Flashcard(deckID: card.deckID)
                            front = PKDrawing()
                            back = PKDrawing()
                        }
                        .disabled(isEmpty)
                    }
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .bold()
                    .disabled(isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                front = study.drawing(for: card.id, side: .front).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
                back = study.drawing(for: card.id, side: .back).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
            }
        }
    }

    private var isEmpty: Bool {
        (card.frontText.isEmpty && front.strokes.isEmpty) || (card.backText.isEmpty && back.strokes.isEmpty)
    }

    private func side(_ title: String, hint: String, text: Binding<String>, drawing: Binding<PKDrawing>, ink: Binding<SketchInk>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.title3, design: .serif).bold())
            TextField("Type (optional)", text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            SketchCanvas(drawing: drawing, ink: ink.wrappedValue)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .studyCard()
                .overlay(alignment: .top) {
                    SketchToolbar(ink: ink, drawing: drawing).padding(.top, 10)
                }
                .overlay {
                    if drawing.wrappedValue.strokes.isEmpty {
                        Text(hint).foregroundStyle(.tertiary).allowsHitTesting(false)
                    }
                }
        }
    }

    private func save() {
        study.saveCard(card,
                       front: front.strokes.isEmpty ? nil : front.dataRepresentation(),
                       back: back.strokes.isEmpty ? nil : back.dataRepresentation())
    }
}

/// Review: front → flip → write the answer → rate 1–5 → Done shows the real answer → Next.
struct FlashcardReviewView: View {
    let deckID: UUID?
    let title: String

    private enum Phase { case front, writing, revealed }

    @EnvironmentObject private var study: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [UUID] = []
    @State private var started = false
    @State private var phase = Phase.front
    @State private var attempt = PKDrawing()
    @State private var ink = SketchInk.pen(0)
    @State private var rating: RecallRating?
    @State private var flipAngle: Double = 0
    @State private var reviewed = 0

    private var card: Flashcard? { queue.first.flatMap { study.card($0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let card {
                cardArea(card)
                    .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                bottomBar(card)
            } else if started {
                VStack(spacing: 24) {
                    CaughtUpView(title: "All caught up!",
                                 message: reviewed == 0 ? "Nothing is due right now." : "You reviewed \(reviewed) card\(reviewed == 1 ? "" : "s"). Come back later for the next round.")
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            guard !started else { return }
            queue = study.sessionQueue(for: deckID)
            started = true
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3.bold()) }
                .accessibilityLabel("End review")
            HandwrittenText(title, size: 18).padding(.leading, 8)
            Spacer()
            if !queue.isEmpty {
                Text("\(queue.count) left").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func cardArea(_ card: Flashcard) -> some View {
        switch phase {
        case .front:
            CardFaceView(card: card, side: .front)
                .frame(maxWidth: 820, maxHeight: 560)
                .onTapGesture(perform: flip)

        case .writing:
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text("Q").font(.headline).foregroundStyle(.secondary)
                    CardFaceView(card: card, side: .front)
                        .frame(maxWidth: 360, maxHeight: 110)
                    Text("Write the answer from memory").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                }
                SketchCanvas(drawing: $attempt, ink: ink)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .studyCard()
                    .overlay(alignment: .top) {
                        SketchToolbar(ink: $ink, drawing: $attempt).padding(.top, 10)
                    }
            }

        case .revealed:
            HStack(spacing: 20) {
                VStack(spacing: 10) {
                    Text("Your answer").font(.headline)
                    Group {
                        if attempt.strokes.isEmpty {
                            Text("Nothing written").foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            InkImageView(data: attempt.dataRepresentation()).padding(24)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .studyCard()
                }
                VStack(spacing: 10) {
                    Text("Correct answer").font(.headline)
                    CardFaceView(card: card, side: .back)
                }
            }
        }
    }

    private func bottomBar(_ card: Flashcard) -> some View {
        VStack(spacing: 12) {
            switch phase {
            case .front:
                Button(action: flip) {
                    Label { Text("Flip & Write") } icon: { ThemedIcon(.flip, size: 22) }
                        .font(.title3.bold()).frame(maxWidth: 420).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
            case .writing, .revealed:
                Text(phase == .writing ? "How sure are you?" : "Change your rating if you need to")
                    .font(.headline)
                RatingBar(selection: $rating, schedule: card.schedule)
                    .frame(maxWidth: 700)
                Button {
                    if phase == .writing {
                        withAnimation(.easeInOut(duration: 0.3)) { phase = .revealed }
                    } else {
                        next(card)
                    }
                } label: {
                    Label { Text(phase == .writing ? "Done — Show Answer" : "Next Card") } icon: {
                        ThemedIcon(phase == .writing ? .done : .next, size: 22)
                    }
                    .font(.title3.bold()).frame(maxWidth: 420).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(rating == nil)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func flip() {
        withAnimation(.easeIn(duration: 0.18)) { flipAngle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            phase = .writing
            flipAngle = -90
            withAnimation(.easeOut(duration: 0.2)) { flipAngle = 0 }
        }
    }

    private func next(_ card: Flashcard) {
        guard let rating else { return }
        study.review(card.id, rating: rating)
        reviewed += 1
        queue.removeFirst()
        // Missed cards come back at the end of this session, like Anki's learning steps.
        if rating.rawValue <= 2 { queue.append(card.id) }
        attempt = PKDrawing()
        self.rating = nil
        withAnimation { phase = .front }
    }
}
