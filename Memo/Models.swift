import Foundation
import SwiftData

@Model
final class Deck {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card]? = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }

    var allCards: [Card] { cards ?? [] }
}

@Model
final class Card {
    var id: UUID = UUID()
    var front: String = ""
    var back: String = ""
    var createdAt: Date = Date.now
    var stateRaw: String = CardState.new.rawValue
    var due: Date = Date.now
    var interval: Int = 0
    var ease: Double = 2.5
    var step: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var lastReview: Date?
    var deck: Deck?

    init(front: String, back: String, createdAt: Date = .now) {
        self.front = front
        self.back = back
        self.createdAt = createdAt
        self.due = createdAt
    }

    var state: CardState {
        get { CardState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    var scheduling: SchedulingInfo {
        get {
            SchedulingInfo(state: state, due: due, interval: interval, ease: ease,
                           step: step, reps: reps, lapses: lapses, lastReview: lastReview)
        }
        set {
            state = newValue.state
            due = newValue.due
            interval = newValue.interval
            ease = newValue.ease
            step = newValue.step
            reps = newValue.reps
            lapses = newValue.lapses
            lastReview = newValue.lastReview
        }
    }

    func resetProgress() {
        scheduling = SchedulingInfo(due: .now, ease: SchedulerConfig().startingEase)
    }
}

extension Card {
    /// À partir de ce nombre d'oublis, une carte est signalée comme difficile :
    /// elle est souvent mal formulée et gagne à être réécrite ou découpée.
    static let difficultThreshold = 4

    var isDifficult: Bool { lapses >= Card.difficultThreshold }
}

/// Une réponse donnée pendant une révision (sert aux statistiques et aux limites quotidiennes).
@Model
final class ReviewLog {
    var date: Date = Date.now
    var deckID: UUID = UUID()
    var cardID: UUID = UUID()
    var rating: Int = 3
    var wasNew: Bool = false

    init(date: Date, deckID: UUID, cardID: UUID, rating: Int, wasNew: Bool) {
        self.date = date
        self.deckID = deckID
        self.cardID = cardID
        self.rating = rating
        self.wasNew = wasNew
    }
}
