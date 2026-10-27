import SwiftData
import SwiftUI

enum StudyRoute: Hashable {
    case all
    case deck(Deck)
}

struct HomeView: View {
    @Binding var path: [StudyRoute]

    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now

    var body: some View {
        NavigationStack(path: $path) {
            HomeContent(now: now)
                .onAppear { now = .now }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now }
        }
    }
}

private struct HomeContent: View {
    let now: Date

    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @Query private var recentLogs: [ReviewLog]
    @AppStorage(AppSettings.Key.newPerDay) private var newPerDay = AppSettings.defaultNewPerDay

    @State private var showingNewDeck = false
    @State private var newDeckName = ""
    @State private var renamingDeck: Deck?
    @State private var renameText = ""
    @State private var deckToDelete: Deck?
    @State private var addingTo: Deck?

    init(now: Date) {
        self.now = now
        let since = Calendar.current.date(byAdding: .day, value: -400, to: Calendar.current.startOfDay(for: now))!
        _recentLogs = Query(filter: #Predicate<ReviewLog> { $0.date >= since }, sort: \ReviewLog.date)
    }

    // MARK: - Chiffres du jour

    private var startOfToday: Date { Calendar.current.startOfDay(for: now) }
    private var todayLogs: [ReviewLog] { recentLogs.filter { $0.date >= startOfToday } }

    private var newLeft: [UUID: Int] {
        var result: [UUID: Int] = [:]
        for deck in decks {
            let seen = todayLogs.filter { $0.wasNew && $0.deckID == deck.id }.count
            result[deck.id] = max(0, newPerDay - seen)
        }
        return result
    }

    private func counts(_ deck: Deck) -> DueCounts {
        StudyQueue.counts(for: deck, newLeft: newLeft[deck.id] ?? 0, until: StudyQueue.endOfDay(now))
    }

    private var dueToday: Int { decks.reduce(0) { $0 + counts($1).total } }

    /// Révisions déjà prévues pour demain (hors nouvelles cartes).
    private var dueTomorrow: Int {
        let endOfToday = StudyQueue.endOfDay(now)
        let endOfTomorrow = StudyQueue.endOfDay(endOfToday.addingTimeInterval(60))
        return decks.flatMap(\.allCards).filter { $0.state != .new && $0.due > endOfToday && $0.due <= endOfTomorrow }.count
    }

    private var difficultCount: Int {
        decks.flatMap(\.allCards).filter(\.isDifficult).count
    }

    private var streak: Int {
        StudyQueue.streak(days: Set(recentLogs.map { Calendar.current.startOfDay(for: $0.date) }), now: now)
    }

    // MARK: - Vue

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if decks.isEmpty {
                    emptyState
                } else {
                    TodayCard(due: dueToday, doneToday: todayLogs.count, streak: streak, tomorrow: dueTomorrow)

                    if difficultCount > 0 {
                        NavigationLink {
                            DifficultCardsView()
                        } label: {
                            DifficultBanner(count: difficultCount)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mes paquets")
                            .font(.title3.bold())
                            .padding(.horizontal, 4)

                        ForEach(decks) { deck in
                            DeckTile(deck: deck, counts: counts(deck),
                                     onAdd: { addingTo = deck },
                                     onRename: { renameText = deck.name; renamingDeck = deck },
                                     onDelete: { deckToDelete = deck })
                        }

                        Button {
                            showingNewDeck = true
                        } label: {
                            Label("Nouveau paquet", systemImage: "plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background {
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mémo")
        .navigationDestination(for: StudyRoute.self) { route in
            StudyView(route: route)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addingTo = decks.first
                } label: {
                    Label("Ajouter une carte", systemImage: "plus")
                }
                .disabled(decks.isEmpty)
            }
        }
        .alert("Nouveau paquet", isPresented: $showingNewDeck) {
            TextField("Ex. : Vocabulaire anglais", text: $newDeckName)
            Button("Annuler", role: .cancel) { newDeckName = "" }
            Button("Créer") { createDeck() }
        } message: {
            Text("Regroupez vos cartes par sujet.")
        }
        .alert("Renommer le paquet", isPresented: Binding(get: { renamingDeck != nil }, set: { if !$0 { renamingDeck = nil } })) {
            TextField("Nom", text: $renameText)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let deck = renamingDeck, !name.isEmpty { deck.name = name }
            }
        }
        .confirmationDialog(
            "Supprimer « \(deckToDelete?.name ?? "") » ?",
            isPresented: Binding(get: { deckToDelete != nil }, set: { if !$0 { deckToDelete = nil } }),
            titleVisibility: .visible,
            presenting: deckToDelete
        ) { deck in
            Button("Supprimer le paquet et ses \(deck.allCards.count) cartes", role: .destructive) {
                context.delete(deck)
                try? context.save()
            }
        } message: { _ in
            Text("Cette action est définitive.")
        }
        .sheet(item: $addingTo) { deck in
            NavigationStack { CardEditorView(mode: .add(deck)) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucun paquet", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Créez un paquet, ajoutez des cartes question / réponse, et Mémo vous les fera réviser au bon moment.")
        } actions: {
            Button("Créer mon premier paquet") { showingNewDeck = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 60)
    }

    private func createDeck() {
        let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        newDeckName = ""
        guard !name.isEmpty else { return }
        let deck = Deck(name: name)
        context.insert(deck)
        try? context.save()
        addingTo = deck
    }
}

// MARK: - Carte « Aujourd'hui »

private struct TodayCard: View {
    let due: Int
    let doneToday: Int
    let streak: Int
    let tomorrow: Int

    private var progress: Double {
        due == 0 ? 1 : Double(doneToday) / Double(doneToday + due)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                ProgressRing(progress: progress, done: due == 0)
                    .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 4) {
                    if due > 0 {
                        Text("\(due)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(due == 1 ? "carte à réviser" : "cartes à réviser")
                            .font(.headline)
                        Text(StudyQueue.estimatedDuration(cards: due))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tout est à jour !")
                            .font(.title2.bold())
                        Text(doneToday > 0 ? "Bravo pour vos révisions d'aujourd'hui." : "Rien à réviser pour l'instant.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if due > 0 {
                NavigationLink(value: StudyRoute.all) {
                    Label("Réviser maintenant", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                StatPill(icon: "flame.fill", color: .orange, value: streak, label: streak > 1 ? "jours de suite" : "jour de suite")
                StatPill(icon: "checkmark.circle.fill", color: .green, value: doneToday, label: "aujourd'hui")
                StatPill(icon: "calendar", color: .blue, value: tomorrow, label: "demain")
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ProgressRing: View {
    let progress: Double
    var done = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(done ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            if done {
                Image(systemName: "checkmark")
                    .font(.title.bold())
                    .foregroundStyle(.green)
            } else {
                Text("\(Int((progress * 100).rounded())) %")
                    .font(.subheadline.bold())
                    .monospacedDigit()
            }
        }
    }
}

private struct StatPill: View {
    let icon: String
    let color: Color
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(color)
                Text("\(value)").bold().monospacedDigit()
            }
            .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Cartes difficiles

private struct DifficultBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 carte difficile" : "\(count) cartes difficiles")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Souvent oubliées : les réécrire aide à les retenir")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Paquet

private struct DeckTile: View {
    let deck: Deck
    let counts: DueCounts
    let onAdd: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    private var subtitle: String {
        let total = deck.allCards.count
        if total == 0 { return "Vide — ajoutez des cartes" }
        var parts: [String] = []
        if counts.new > 0 { parts.append("\(counts.new) nouvelle\(counts.new > 1 ? "s" : "")") }
        if counts.learning + counts.review > 0 { parts.append("\(counts.learning + counts.review) à revoir") }
        if parts.isEmpty { parts.append("À jour") }
        return parts.joined(separator: " · ") + " — \(total) carte\(total > 1 ? "s" : "")"
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: StudyRoute.deck(deck)) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deck.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if counts.total > 0 {
                        Text("\(counts.total)")
                            .font(.subheadline.bold())
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    } else if !deck.allCards.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Ajouter des cartes", systemImage: "plus", action: onAdd)
                Button("Renommer", systemImage: "pencil", action: onRename)
                Button("Supprimer", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
