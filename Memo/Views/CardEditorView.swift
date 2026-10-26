import SwiftData
import SwiftUI

struct CardEditorView: View {
    enum Mode {
        case add(Deck?)
        case edit(Card)
    }

    let mode: Mode
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]

    @State private var front = ""
    @State private var back = ""
    @State private var deck: Deck?
    @State private var addedCount = 0
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    private enum Field { case front, back }

    private var editedCard: Card? {
        if case .edit(let card) = mode { card } else { nil }
    }

    private var canSave: Bool {
        deck != nil
            && !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            if let card = editedCard, card.isDifficult {
                Section {
                    DifficultTips()
                } header: {
                    Label("Carte oubliée \(card.lapses) fois", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Paquet", selection: $deck) {
                    ForEach(decks) { deck in
                        Text(deck.name).tag(Optional(deck))
                    }
                }
            }

            Section {
                TextField("Ex. : Comment dit-on « pomme » en anglais ?", text: $front, axis: .vertical)
                    .lineLimit(2...8)
                    .focused($focus, equals: .front)
                    .submitLabel(.next)
            } header: {
                Text("Question")
            }

            Section {
                TextField("Ex. : Apple", text: $back, axis: .vertical)
                    .lineLimit(2...8)
                    .focused($focus, equals: .back)
            } header: {
                Text("Réponse")
            } footer: {
                if editedCard == nil {
                    Text("Astuce : une carte = une seule idée. Des questions courtes se retiennent beaucoup mieux.")
                }
            }

            if let card = editedCard {
                Section("Progression") {
                    LabeledContent("État", value: card.state.label)
                    LabeledContent("Prochaine révision", value: StudyQueue.describeDue(card))
                    LabeledContent("Révisions", value: "\(card.reps)")
                    LabeledContent("Oublis", value: "\(card.lapses)")
                }
                Section {
                    Button("Recommencer l'apprentissage de cette carte", systemImage: "arrow.counterclockwise") {
                        card.resetProgress()
                        try? context.save()
                    }
                    Button("Supprimer la carte", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                }
            } else {
                Section {
                    NavigationLink {
                        BulkImportView(initialDeck: deck)
                    } label: {
                        Label("Ajouter plusieurs cartes d'un coup", systemImage: "text.badge.plus")
                    }
                } footer: {
                    if addedCount > 0 {
                        Label("\(addedCount) carte\(addedCount > 1 ? "s" : "") ajoutée\(addedCount > 1 ? "s" : "")", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .navigationTitle(editedCard == nil ? "Nouvelle carte" : "Modifier la carte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(editedCard == nil ? "Fermer" : "Annuler") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editedCard == nil ? "Ajouter" : "Enregistrer", action: save)
                    .disabled(!canSave)
            }
        }
        .confirmationDialog("Supprimer cette carte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive, action: delete)
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .add(let initialDeck):
            deck = initialDeck ?? decks.first
            focus = .front
        case .edit(let card):
            front = card.front
            back = card.back
            deck = card.deck
        }
    }

    private func save() {
        let question = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let deck, !question.isEmpty, !answer.isEmpty else { return }

        switch mode {
        case .add:
            let card = Card(front: question, back: answer)
            context.insert(card)
            card.deck = deck
            try? context.save()
            withAnimation { addedCount += 1 }
            front = ""
            back = ""
            focus = .front
        case .edit(let card):
            card.front = question
            card.back = answer
            card.deck = deck
            try? context.save()
            dismiss()
        }
    }

    private func delete() {
        guard let card = editedCard else { return }
        onDelete?()
        context.delete(card)
        try? context.save()
        dismiss()
    }
}

/// Ajout de plusieurs cartes à partir d'un texte : une carte par ligne.
struct BulkImportView: View {
    let initialDeck: Deck?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]

    @State private var deck: Deck?
    @State private var text = ""

    private var parsed: [(front: String, back: String)] { Self.parse(text) }

    var body: some View {
        Form {
            Section {
                Picker("Paquet", selection: $deck) {
                    ForEach(decks) { deck in
                        Text(deck.name).tag(Optional(deck))
                    }
                }
            }

            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 220)
                    .font(.body)
                    .autocorrectionDisabled()
            } header: {
                Text("Une carte par ligne")
            } footer: {
                Text("Séparez la question et la réponse par « ; », « :: » ou une tabulation.\nExemple :\nbonjour ; hello\nmerci ; thank you")
            }

            Section {
                Button {
                    importCards()
                } label: {
                    Label(parsed.isEmpty ? "Ajouter les cartes" : "Ajouter \(parsed.count) carte\(parsed.count > 1 ? "s" : "")",
                          systemImage: "plus.circle.fill")
                }
                .disabled(parsed.isEmpty || deck == nil)
            }
        }
        .navigationTitle("Ajout rapide")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if deck == nil { deck = initialDeck ?? decks.first } }
    }

    private func importCards() {
        guard let deck else { return }
        let now = Date.now
        for (index, item) in parsed.enumerated() {
            // Décalage d'une milliseconde pour garder l'ordre du texte.
            let card = Card(front: item.front, back: item.back, createdAt: now.addingTimeInterval(Double(index) / 1000))
            context.insert(card)
            card.deck = deck
        }
        try? context.save()
        dismiss()
    }

    static func parse(_ text: String) -> [(front: String, back: String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            for separator in ["\t", "::", ";"] {
                guard let range = line.range(of: separator) else { continue }
                let front = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let back = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                return front.isEmpty || back.isEmpty ? nil : (front, back)
            }
            return nil
        }
    }
}
