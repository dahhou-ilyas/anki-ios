import SwiftData
import SwiftUI

struct StudyView: View {
    let route: StudyRoute

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Deck.createdAt) private var allDecks: [Deck]

    @State private var current: Card?
    @State private var revealed = false
    @State private var started = false
    @State private var sessionStart = Date.now
    @State private var answers: [Rating] = []
    @State private var extraNew = 0
    @State private var lastAnswer: UndoEntry?
    @State private var editingCard: Card?
    @State private var addingCards = false
    @State private var difficultNotice: Card?

    private struct UndoEntry {
        let card: Card
        let previous: SchedulingInfo
        let log: ReviewLog
    }

    private var decks: [Deck] {
        switch route {
        case .all: allDecks
        case .deck(let deck): [deck]
        }
    }

    private var title: String {
        switch route {
        case .all: "Révision"
        case .deck(let deck): deck.name
        }
    }

    private var newLeft: [UUID: Int] {
        StudyQueue.newLeft(for: decks, context: context, extra: extraNew)
    }

    private var remaining: Int {
        StudyQueue.counts(for: decks, newLeft: newLeft, until: StudyQueue.endOfDay(.now)).total
    }

    var body: some View {
        VStack(spacing: 16) {
            if let card = current {
                progressHeader
                cardView(card)
                answerArea(card)
            } else if started {
                SessionSummary(
                    answers: answers,
                    duration: Date.now.timeIntervalSince(sessionStart),
                    isEmpty: decks.allSatisfy { $0.allCards.isEmpty },
                    nextLearning: StudyQueue.nextLearningDue(in: decks),
                    moreNewAvailable: StudyQueue.newBeyondLimit(in: decks, newLeft: newLeft),
                    onMoreNew: {
                        extraNew += 10
                        loadNext()
                    },
                    onAddCards: { addingCards = true },
                    onFinish: { dismiss() }
                )
            }
        }
        .padding()
        .overlay(alignment: .top) {
            if let notice = difficultNotice {
                DifficultNotice(
                    onEdit: {
                        editingCard = notice
                        difficultNotice = nil
                    },
                    onDismiss: { withAnimation { difficultNotice = nil } }
                )
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    undo()
                } label: {
                    Label("Annuler la dernière réponse", systemImage: "arrow.uturn.backward")
                }
                .disabled(lastAnswer == nil)

                Button {
                    editingCard = current
                } label: {
                    Label("Modifier la carte", systemImage: "pencil")
                }
                .disabled(current == nil)
            }
        }
        .sheet(item: $editingCard, onDismiss: { if current == nil { loadNext() } }) { card in
            NavigationStack {
                CardEditorView(mode: .edit(card), onDelete: {
                    if current?.id == card.id { current = nil }
                    if lastAnswer?.card.id == card.id { lastAnswer = nil }
                })
            }
        }
        .sheet(isPresented: $addingCards, onDismiss: loadNext) {
            NavigationStack { CardEditorView(mode: .add(decks.first)) }
        }
        .task(id: current?.id) {
            if !started {
                started = true
                sessionStart = .now
                loadNext()
                if current != nil { return }
            }
            if current == nil { await waitForLearningCard() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: answers.count)
    }

    // MARK: - Éléments

    private var progressHeader: some View {
        let done = answers.count
        let left = remaining
        return VStack(spacing: 6) {
            ProgressView(value: Double(done), total: Double(max(1, done + left)))
                .tint(.accentColor)
            HStack {
                Text(done == 0 ? "C'est parti !" : "\(done) faite\(done > 1 ? "s" : "")")
                Spacer()
                Text("\(left) restante\(left > 1 ? "s" : "")")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private func cardView(_ card: Card) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        if case .all = route, let name = card.deck?.name {
                            Text(name)
                        }
                        Spacer()
                        Text(card.state == .new ? "Nouvelle" : card.state.isLearning ? "En cours d'apprentissage" : "Révision")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(card.front)
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    if revealed {
                        Divider()
                        Text(card.back)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(minHeight: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture { reveal() }
    }

    @ViewBuilder
    private func answerArea(_ card: Card) -> some View {
        if revealed {
            let delays = Scheduler.preview(card.scheduling, config: AppSettings.schedulerConfig)
            VStack(spacing: 8) {
                Text("Vous vous en souveniez ?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Rating.allCases) { rating in
                        Button {
                            answer(rating)
                        } label: {
                            VStack(spacing: 3) {
                                Text(rating.label)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(Scheduler.formatDelay(delays[rating] ?? 0))
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                        .tint(rating.color)
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Text("Cherchez la réponse de tête, puis vérifiez.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: reveal) {
                    Text("Afficher la réponse")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func reveal() {
        guard !revealed else { return }
        withAnimation(.easeOut(duration: 0.2)) { revealed = true }
    }

    private func loadNext() {
        current = StudyQueue.nextCard(in: decks, newLeft: newLeft)
        revealed = false
    }

    private func answer(_ rating: Rating) {
        guard let card = current, revealed else { return }
        let now = Date.now
        let previous = card.scheduling
        card.scheduling = Scheduler.schedule(previous, rating: rating, now: now, config: AppSettings.schedulerConfig)

        let log = ReviewLog(date: now, deckID: card.deck?.id ?? UUID(), cardID: card.id,
                            rating: rating.rawValue, wasNew: previous.state == .new)
        context.insert(log)
        try? context.save()

        lastAnswer = UndoEntry(card: card, previous: previous, log: log)
        answers.append(rating)
        if card.isDifficult && previous.lapses < Card.difficultThreshold {
            withAnimation { difficultNotice = card }
        }
        loadNext()
    }

    private func undo() {
        guard let entry = lastAnswer else { return }
        entry.card.scheduling = entry.previous
        context.delete(entry.log)
        try? context.save()
        lastAnswer = nil
        difficultNotice = nil
        if !answers.isEmpty { answers.removeLast() }
        current = entry.card
        revealed = false
    }

    /// Si une carte en apprentissage revient bientôt, on attend puis on l'affiche.
    private func waitForLearningCard() async {
        guard let due = StudyQueue.nextLearningDue(in: decks),
              due <= StudyQueue.endOfDay(.now) else { return }
        let wait = due.timeIntervalSinceNow - StudyQueue.learnAhead
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
        }
        guard !Task.isCancelled else { return }
        loadNext()
    }
}

extension Rating {
    var color: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}

// MARK: - Carte devenue difficile

private struct DifficultNotice: View {
    let onEdit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text("Cette carte est souvent oubliée")
                    .font(.subheadline.weight(.semibold))
                Text("La réécrire plus simplement ou la découper vous aidera à la retenir.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Modifier", action: onEdit)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    Button("Plus tard", action: onDismiss)
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Fin de séance

private struct SessionSummary: View {
    let answers: [Rating]
    let duration: TimeInterval
    let isEmpty: Bool
    let nextLearning: Date?
    let moreNewAvailable: Int
    let onMoreNew: () -> Void
    let onAddCards: () -> Void
    let onFinish: () -> Void

    private var successRate: Int {
        guard !answers.isEmpty else { return 0 }
        let remembered = answers.filter { $0 != .again }.count
        return Int((Double(remembered) / Double(answers.count) * 100).rounded())
    }

    private var encouragement: String {
        switch successRate {
        case 90...: "Excellente mémoire !"
        case 70..<90: "Très bon travail !"
        case 50..<70: "Bien joué, la répétition va faire son effet."
        default: "C'est en se trompant qu'on retient le mieux. Ces cartes reviendront vite."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                if isEmpty {
                    header(icon: "tray", color: .secondary, title: "Ce paquet est vide",
                           subtitle: "Ajoutez des cartes question / réponse pour commencer.")
                    Button("Ajouter des cartes", systemImage: "plus", action: onAddCards)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else if answers.isEmpty {
                    header(icon: "checkmark.seal.fill", color: .green, title: "Tout est à jour",
                           subtitle: "Aucune carte à réviser pour le moment.")
                } else {
                    header(icon: "checkmark.seal.fill", color: .green, title: "Séance terminée !", subtitle: encouragement)

                    HStack(spacing: 10) {
                        SummaryStat(value: "\(answers.count)", label: "cartes")
                        SummaryStat(value: "\(successRate) %", label: "retenues")
                        SummaryStat(value: Scheduler.formatDelay(duration), label: "de révision")
                    }
                }

                if let nextLearning, nextLearning <= StudyQueue.endOfDay(.now) {
                    Label("Des cartes reviennent dans \(Scheduler.formatDelay(nextLearning.timeIntervalSinceNow)). Gardez l'app ouverte ou attendez la notification.",
                          systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(spacing: 10) {
                    if moreNewAvailable > 0 {
                        Button(action: onMoreNew) {
                            Label("Apprendre \(min(10, moreNewAvailable)) nouvelles cartes de plus", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    if !isEmpty {
                        Button(action: onFinish) {
                            Text("Terminer").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
        }
    }

    private func header(icon: String, color: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(color)
                .symbolEffect(.bounce, value: answers.count)
            Text(title).font(.title.bold())
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct SummaryStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
