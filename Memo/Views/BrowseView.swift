import SwiftData
import SwiftUI

struct BrowseView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Card.createdAt, order: .reverse) private var cards: [Card]
    @Query(sort: \Deck.createdAt) private var decks: [Deck]

    @State private var search = ""
    @State private var deckFilter: Deck?
    @State private var onlyDifficult = false
    @State private var editing: Card?
    @State private var adding = false

    private var filtered: [Card] {
        cards.filter { card in
            (deckFilter == nil || card.deck == deckFilter)
                && (!onlyDifficult || card.isDifficult)
                && (search.isEmpty
                    || card.front.localizedStandardContains(search)
                    || card.back.localizedStandardContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { card in
                    Button {
                        editing = card
                    } label: {
                        CardRow(card: card, showDeck: deckFilter == nil && decks.count > 1)
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    let list = filtered
                    for index in offsets { context.delete(list[index]) }
                    try? context.save()
                }
            }
            .overlay {
                if cards.isEmpty {
                    ContentUnavailableView("Aucune carte", systemImage: "rectangle.on.rectangle",
                                           description: Text("Ajoutez vos premières cartes avec le bouton +."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Rechercher une carte")
            .navigationTitle("Cartes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Paquet", selection: $deckFilter) {
                            Text("Tous les paquets").tag(Deck?.none)
                            ForEach(decks) { deck in
                                Text(deck.name).tag(Optional(deck))
                            }
                        }
                        Toggle("Cartes difficiles seulement", systemImage: "exclamationmark.triangle", isOn: $onlyDifficult)
                    } label: {
                        Label("Filtrer", systemImage: deckFilter == nil && !onlyDifficult
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        adding = true
                    } label: {
                        Label("Ajouter une carte", systemImage: "plus")
                    }
                    .disabled(decks.isEmpty)
                }
            }
            .sheet(item: $editing) { card in
                NavigationStack { CardEditorView(mode: .edit(card)) }
            }
            .sheet(isPresented: $adding) {
                NavigationStack { CardEditorView(mode: .add(deckFilter)) }
            }
        }
    }
}

private struct CardRow: View {
    let card: Card
    let showDeck: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.front)
                .font(.body.weight(.medium))
                .lineLimit(2)
            Text(card.back)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(StudyQueue.describeDue(card))
                if showDeck, let name = card.deck?.name {
                    Text("·")
                    Text(name)
                }
                if card.isDifficult {
                    Label("Difficile", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch card.state {
        case .new: .blue
        case .learning, .relearning: .orange
        case .review: .green
        }
    }
}
