import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Sauvegarde complète au format JSON (export / import depuis les réglages).
struct Backup: Codable {
    struct CardData: Codable {
        var id: UUID
        var front: String
        var back: String
        var createdAt: Date
        var state: String
        var due: Date
        var interval: Int
        var ease: Double
        var step: Int
        var reps: Int
        var lapses: Int
        var lastReview: Date?
    }

    struct DeckData: Codable {
        var id: UUID
        var name: String
        var createdAt: Date
        var cards: [CardData]
    }

    struct LogData: Codable {
        var date: Date
        var deckID: UUID
        var cardID: UUID
        var rating: Int
        var wasNew: Bool
    }

    var version = 1
    var exportedAt: Date
    var decks: [DeckData]
    var logs: [LogData]

    var cardCount: Int { decks.reduce(0) { $0 + $1.cards.count } }

    // MARK: - Encodage

    static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Backup.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: - Base de données

    @MainActor
    static func make(from context: ModelContext) throws -> Backup {
        let decks = try context.fetch(FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)]))
        let logs = try context.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.date)]))
        return Backup(
            exportedAt: .now,
            decks: decks.map { deck in
                DeckData(id: deck.id, name: deck.name, createdAt: deck.createdAt,
                         cards: deck.allCards.sorted { $0.createdAt < $1.createdAt }.map { card in
                             CardData(id: card.id, front: card.front, back: card.back, createdAt: card.createdAt,
                                      state: card.stateRaw, due: card.due, interval: card.interval, ease: card.ease,
                                      step: card.step, reps: card.reps, lapses: card.lapses, lastReview: card.lastReview)
                         })
            },
            logs: logs.map { LogData(date: $0.date, deckID: $0.deckID, cardID: $0.cardID, rating: $0.rating, wasNew: $0.wasNew) }
        )
    }

    /// Remplace toutes les données par celles de la sauvegarde.
    @MainActor
    func restore(into context: ModelContext) throws {
        try Backup.eraseAll(in: context)
        for deckData in decks {
            let deck = Deck(name: deckData.name, createdAt: deckData.createdAt)
            deck.id = deckData.id
            context.insert(deck)
            for data in deckData.cards {
                let card = Card(front: data.front, back: data.back, createdAt: data.createdAt)
                card.id = data.id
                context.insert(card)
                card.deck = deck
                card.scheduling = SchedulingInfo(state: CardState(rawValue: data.state) ?? .new, due: data.due,
                                                 interval: data.interval, ease: data.ease, step: data.step,
                                                 reps: data.reps, lapses: data.lapses, lastReview: data.lastReview)
            }
        }
        for log in logs {
            context.insert(ReviewLog(date: log.date, deckID: log.deckID, cardID: log.cardID, rating: log.rating, wasNew: log.wasNew))
        }
        try context.save()
    }

    @MainActor
    static func eraseAll(in context: ModelContext) throws {
        for card in try context.fetch(FetchDescriptor<Card>()) { context.delete(card) }
        for deck in try context.fetch(FetchDescriptor<Deck>()) { context.delete(deck) }
        for log in try context.fetch(FetchDescriptor<ReviewLog>()) { context.delete(log) }
        try context.save()
    }
}

struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
