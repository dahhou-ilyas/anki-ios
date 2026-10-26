import Foundation

/*
 Planificateur de répétition espacée — variante de SM-2, proche de celle d'Anki.

 Une carte passe par les états :
   new → learning (étapes courtes en minutes) → review (intervalles en jours)
   review --(oubli)--> relearning → review
*/

enum CardState: String, Codable, CaseIterable {
    case new, learning, relearning, review

    var label: String {
        switch self {
        case .new: "Nouvelle"
        case .learning: "Apprentissage"
        case .relearning: "Réapprentissage"
        case .review: "Révision"
        }
    }

    var isLearning: Bool { self == .learning || self == .relearning }
}

enum Rating: Int, CaseIterable, Identifiable {
    case again = 1, hard, good, easy

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .again: "Oublié"
        case .hard: "Difficile"
        case .good: "Bien"
        case .easy: "Facile"
        }
    }
}

/// Progression d'une carte, indépendante du stockage.
struct SchedulingInfo: Equatable {
    var state: CardState = .new
    var due: Date = .now
    var interval: Int = 0       // jours
    var ease: Double = 2.5
    var step: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var lastReview: Date? = nil
}

struct SchedulerConfig {
    var learningSteps: [Double] = [1, 10]   // minutes
    var relearningSteps: [Double] = [10]    // minutes
    var graduatingInterval = 1              // jours, après la dernière étape d'apprentissage
    var easyInterval = 4                    // jours, si « Facile » pendant l'apprentissage
    var startingEase = 2.5
    var minEase = 1.3
    var easyBonus = 1.3
    var hardFactor = 1.2
    var lapseFactor = 0.0                   // fraction de l'intervalle conservée après un oubli (min. 1 jour)
    var maxInterval = 36_500                // jours
}

enum Scheduler {
    static let minute: TimeInterval = 60
    static let day: TimeInterval = 86_400

    /// Renvoie la progression de la carte après une réponse.
    static func schedule(_ info: SchedulingInfo, rating: Rating, now: Date = .now, config: SchedulerConfig = .init()) -> SchedulingInfo {
        var card = info
        card.reps += 1
        card.lastReview = now

        if card.state == .new {
            card.state = .learning
            card.step = 0
        }
        if card.state.isLearning {
            return scheduleLearning(card, rating, now, config)
        }
        return scheduleReview(card, rating, now, config)
    }

    /// Délai (en secondes) jusqu'à la prochaine révision pour chacune des 4 réponses.
    static func preview(_ info: SchedulingInfo, now: Date = .now, config: SchedulerConfig = .init()) -> [Rating: TimeInterval] {
        Dictionary(uniqueKeysWithValues: Rating.allCases.map { rating in
            (rating, schedule(info, rating: rating, now: now, config: config).due.timeIntervalSince(now))
        })
    }

    /// Formate un délai en texte court : « 10 min », « 3 j », « 2,5 mois »…
    static func formatDelay(_ seconds: TimeInterval) -> String {
        let minutes = seconds / minute
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded())) h" }
        let days = seconds / day
        if days < 30 { return "\(Int(days.rounded())) j" }
        if days < 365 { return trimmed(days / 30) + " mois" }
        let years = days / 365
        return trimmed(years) + (years < 2 ? " an" : " ans")
    }

    // MARK: - Détails

    private static func scheduleLearning(_ info: SchedulingInfo, _ rating: Rating, _ now: Date, _ cfg: SchedulerConfig) -> SchedulingInfo {
        var card = info
        let relearning = card.state == .relearning
        let steps = relearning ? cfg.relearningSteps : cfg.learningSteps
        let graduateDays = relearning ? max(1, card.interval) : cfg.graduatingInterval
        let easyDays = relearning ? max(1, card.interval) + 1 : cfg.easyInterval

        guard !steps.isEmpty else {
            return graduate(card, days: rating == .easy ? easyDays : graduateDays, now: now, cfg: cfg)
        }

        let step = min(card.step, steps.count - 1)

        switch rating {
        case .again:
            card.step = 0
            card.due = now + steps[0] * minute
        case .hard:
            // Première étape : moyenne des deux premières ; sinon on répète l'étape actuelle.
            var minutes = steps[step]
            if step == 0 && steps.count > 1 {
                minutes = (steps[0] + steps[1]) / 2
            } else if steps.count == 1 {
                minutes = min(steps[0] * 1.5, steps[0] + 24 * 60)
            }
            card.step = step
            card.due = now + minutes * minute
        case .good:
            guard step + 1 < steps.count else {
                return graduate(card, days: graduateDays, now: now, cfg: cfg)
            }
            card.step = step + 1
            card.due = now + steps[card.step] * minute
        case .easy:
            return graduate(card, days: easyDays, now: now, cfg: cfg)
        }
        return card
    }

    private static func scheduleReview(_ info: SchedulingInfo, _ rating: Rating, _ now: Date, _ cfg: SchedulerConfig) -> SchedulingInfo {
        var card = info
        let interval = Double(max(1, card.interval))
        let daysLate = max(0, now.timeIntervalSince(card.due) / day)

        if rating == .again {
            card.lapses += 1
            card.ease = max(cfg.minEase, card.ease - 0.2)
            card.interval = max(1, Int((interval * cfg.lapseFactor).rounded()))
            if let firstStep = cfg.relearningSteps.first {
                card.state = .relearning
                card.step = 0
                card.due = now + firstStep * minute
            } else {
                card.due = now + Double(card.interval) * day
            }
            return card
        }

        // Chaque bouton donne toujours un intervalle strictement plus long que le précédent.
        let hard = max(interval + 1, ((interval + daysLate / 4) * cfg.hardFactor).rounded())
        let good = max(hard + 1, ((interval + daysLate / 2) * card.ease).rounded())
        let easy = max(good + 1, ((interval + daysLate) * card.ease * cfg.easyBonus).rounded())

        let next: Double
        switch rating {
        case .hard:
            card.ease = max(cfg.minEase, card.ease - 0.15)
            next = hard
        case .good:
            next = good
        case .easy:
            card.ease += 0.15
            next = easy
        case .again:
            next = 1 // traité plus haut
        }

        card.interval = min(cfg.maxInterval, Int(next))
        card.due = now + Double(card.interval) * day
        return card
    }

    private static func graduate(_ info: SchedulingInfo, days: Int, now: Date, cfg: SchedulerConfig) -> SchedulingInfo {
        var card = info
        card.state = .review
        card.step = 0
        card.interval = min(cfg.maxInterval, max(1, days))
        card.due = now + Double(card.interval) * day
        return card
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))" }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}
