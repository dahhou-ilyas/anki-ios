import Foundation
import SwiftData

struct DueCounts {
    var new = 0
    var learning = 0
    var review = 0

    var total: Int { new + learning + review }

    static func + (lhs: DueCounts, rhs: DueCounts) -> DueCounts {
        DueCounts(new: lhs.new + rhs.new, learning: lhs.learning + rhs.learning, review: lhs.review + rhs.review)
    }
}

/// Choix des cartes à réviser et comptage de ce qui reste à faire.
enum StudyQueue {
    /// Les cartes en apprentissage dues dans ce délai peuvent être montrées en avance s'il ne reste rien d'autre.
    static let learnAhead: TimeInterval = 20 * 60
    /// Temps moyen estimé par carte, pour afficher une durée de séance.
    static let secondsPerCard: TimeInterval = 10

    static func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
    }

    // MARK: - Nouvelles cartes du jour

    static func newSeenToday(deckID: UUID, context: ModelContext, now: Date = .now) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<ReviewLog>(predicate: #Predicate {
            $0.wasNew == true && $0.deckID == deckID && $0.date >= start
        })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Nombre de nouvelles cartes encore autorisées aujourd'hui, par paquet.
    static func newLeft(for decks: [Deck], context: ModelContext, extra: Int = 0, now: Date = .now) -> [UUID: Int] {
        let limit = AppSettings.newPerDay + extra
        var result: [UUID: Int] = [:]
        for deck in decks {
            result[deck.id] = max(0, limit - newSeenToday(deckID: deck.id, context: context, now: now))
        }
        return result
    }

    // MARK: - Comptage

    static func counts(for deck: Deck, newLeft: Int, until limit: Date) -> DueCounts {
        var counts = DueCounts()
        var newTotal = 0
        for card in deck.allCards {
            switch card.state {
            case .new: newTotal += 1
            case .review: if card.due <= limit { counts.review += 1 }
            case .learning, .relearning: if card.due <= limit { counts.learning += 1 }
            }
        }
        counts.new = min(newTotal, newLeft)
        return counts
    }

    static func counts(for decks: [Deck], newLeft: [UUID: Int], until limit: Date) -> DueCounts {
        decks.reduce(DueCounts()) { $0 + counts(for: $1, newLeft: newLeft[$1.id] ?? 0, until: limit) }
    }

    /// Cartes nouvelles qui dépassent la limite du jour.
    static func newBeyondLimit(in decks: [Deck], newLeft: [UUID: Int]) -> Int {
        decks.reduce(0) { sum, deck in
            let newCount = deck.allCards.filter { $0.state == .new }.count
            return sum + max(0, newCount - (newLeft[deck.id] ?? 0))
        }
    }

    // MARK: - Prochaine carte

    /// Ordre : apprentissage dû, révisions du jour, nouvelles cartes, puis apprentissage en avance.
    static func nextCard(in decks: [Deck], newLeft: [UUID: Int], now: Date = .now) -> Card? {
        let cards = decks.flatMap(\.allCards)
        let endOfToday = endOfDay(now)

        let learning = cards.filter { $0.state.isLearning }.min { $0.due < $1.due }
        if let learning, learning.due <= now { return learning }

        let review = cards.filter { $0.state == .review && $0.due <= endOfToday }.min { $0.due < $1.due }
        if let review { return review }

        let newCard = cards
            .filter { $0.state == .new && (newLeft[$0.deck?.id ?? UUID()] ?? 0) > 0 }
            .min { $0.createdAt < $1.createdAt }
        if let newCard { return newCard }

        if let learning, learning.due <= now + learnAhead { return learning }
        return nil
    }

    static func nextLearningDue(in decks: [Deck], now: Date = .now) -> Date? {
        decks.flatMap(\.allCards)
            .filter { $0.state.isLearning && $0.due > now }
            .map(\.due)
            .min()
    }

    // MARK: - Affichage

    static func describeDue(_ card: Card, now: Date = .now) -> String {
        switch card.state {
        case .new:
            return "Pas encore étudiée"
        case .learning, .relearning:
            let delay = card.due.timeIntervalSince(now)
            return delay <= 0 ? "Maintenant" : "Dans " + Scheduler.formatDelay(delay)
        case .review:
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                               to: calendar.startOfDay(for: card.due)).day ?? 0
            switch days {
            case ...0: return "Aujourd'hui"
            case 1: return "Demain"
            default: return "Dans " + Scheduler.formatDelay(Double(days) * Scheduler.day)
            }
        }
    }

    static func estimatedDuration(cards: Int) -> String {
        let minutes = max(1, Int((Double(cards) * secondsPerCard / 60).rounded()))
        return "≈ \(minutes) min"
    }

    /// Jours (début de journée) où au moins une carte a été révisée, sur la dernière année.
    static func reviewDays(context: ModelContext, now: Date = .now) -> Set<Date> {
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -400, to: calendar.startOfDay(for: now))!
        let logs = (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.date >= since }))) ?? []
        return Set(logs.map { calendar.startOfDay(for: $0.date) })
    }

    /// Nombre de jours consécutifs avec au moins une révision (aujourd'hui ou hier inclus).
    static func streak(days: Set<Date>, now: Date = .now) -> Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}
