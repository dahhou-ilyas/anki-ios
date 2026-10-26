import Foundation
import SwiftData
import WidgetKit

/// Met à jour le résumé lu par le widget, puis lui demande de se redessiner.
@MainActor
enum WidgetSync {
    static func update(context: ModelContext) {
        let now = Date.now
        let calendar = Calendar.current
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        let cards = decks.flatMap(\.allCards)
        let newLeft = StudyQueue.newLeft(for: decks, context: context, now: now)

        var newToday = 0
        var newPerDay = 0
        for deck in decks {
            let newCount = deck.allCards.filter { $0.state == .new }.count
            newToday += min(newCount, newLeft[deck.id] ?? 0)
            newPerDay += min(newCount, AppSettings.newPerDay)
        }

        let since = calendar.date(byAdding: .day, value: -400, to: calendar.startOfDay(for: now))!
        let logs = (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.date >= since }))) ?? []
        let reviewDays = Set(logs.map { calendar.startOfDay(for: $0.date) })
        let startOfToday = calendar.startOfDay(for: now)

        WidgetSnapshot(
            updatedAt: now,
            dueDates: cards.filter { $0.state != .new }.map(\.due),
            newToday: newToday,
            newPerDay: newPerDay,
            doneToday: logs.filter { $0.date >= startOfToday }.count,
            streak: StudyQueue.streak(days: reviewDays, now: now),
            lastReviewDay: reviewDays.max(),
            hasCards: !cards.isEmpty
        ).save()

        WidgetCenter.shared.reloadAllTimelines()
    }
}
