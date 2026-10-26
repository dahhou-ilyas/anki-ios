import SwiftData
import SwiftUI

/// Liste des cartes souvent oubliées, avec des conseils pour les réécrire.
struct DifficultCardsView: View {
    @Query private var cards: [Card]
    @State private var editing: Card?

    init() {
        let threshold = Card.difficultThreshold
        _cards = Query(filter: #Predicate<Card> { $0.lapses >= threshold }, sort: \Card.lapses, order: .reverse)
    }

    var body: some View {
        List {
            Section {
                DifficultTips()
            }

            if !cards.isEmpty {
                Section("Touchez une carte pour la modifier") {
                    ForEach(cards) { card in
                        Button {
                            editing = card
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.front)
                                    .font(.body.weight(.medium))
                                    .lineLimit(2)
                                Text(card.back)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Label("Oubliée \(card.lapses) fois", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 2)
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .overlay {
            if cards.isEmpty {
                ContentUnavailableView("Aucune carte difficile", systemImage: "checkmark.seal",
                                       description: Text("Vous retenez bien toutes vos cartes."))
            }
        }
        .navigationTitle("Cartes difficiles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { card in
            NavigationStack { CardEditorView(mode: .edit(card)) }
        }
    }
}

/// Conseils pour réécrire une carte souvent oubliée.
struct DifficultTips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Une carte souvent oubliée est en général trop longue ou trop vague. La réécrire marche mieux que la revoir encore et encore.")
                .font(.subheadline)
            Tip(icon: "scissors", text: "Découpez-la en 2 ou 3 petites cartes")
            Tip(icon: "1.circle", text: "Une seule idée par carte")
            Tip(icon: "text.quote", text: "Ajoutez un exemple ou une phrase")
            Tip(icon: "lightbulb", text: "Trouvez une astuce pour vous en souvenir")
        }
        .padding(.vertical, 4)
    }

    private struct Tip: View {
        let icon: String
        let text: String

        var body: some View {
            Label {
                Text(text).font(.subheadline)
            } icon: {
                Image(systemName: icon).foregroundStyle(.orange)
            }
        }
    }
}
