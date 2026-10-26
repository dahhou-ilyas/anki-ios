import Foundation

/// Résumé des révisions écrit par l'app et lu par le widget, partagé via l'App Group.
struct WidgetSnapshot: Codable {
    static let appGroup = "group.com.ilyasdahhou.memo"
    private static let storageKey = "widgetSnapshot"

    var updatedAt: Date
    /// Dates de révision des cartes déjà étudiées (apprentissage et révision).
    var dueDates: [Date]
    /// Nouvelles cartes encore possibles le jour de `updatedAt`.
    var newToday: Int
    /// Nouvelles cartes possibles les jours suivants.
    var newPerDay: Int
    var doneToday: Int
    var streak: Int
    var lastReviewDay: Date?
    var hasCards: Bool

    // MARK: - Lecture à une date donnée

    func dueCount(on date: Date) -> Int {
        let end = Self.endOfDay(date)
        let reviews = dueDates.filter { $0 <= end }.count
        let new = Calendar.current.isDate(date, inSameDayAs: updatedAt) ? newToday : newPerDay
        return reviews + new
    }

    /// Révisions prévues le lendemain de `date` (hors nouvelles cartes).
    func tomorrowCount(after date: Date) -> Int {
        let endOfToday = Self.endOfDay(date)
        let endOfTomorrow = Self.endOfDay(endOfToday.addingTimeInterval(60))
        return dueDates.filter { $0 > endOfToday && $0 <= endOfTomorrow }.count
    }

    func doneCount(on date: Date) -> Int {
        Calendar.current.isDate(date, inSameDayAs: updatedAt) ? doneToday : 0
    }

    /// La série reste valable tant que la dernière révision date d'aujourd'hui ou d'hier.
    func streak(on date: Date) -> Int {
        guard let lastReviewDay else { return 0 }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastReviewDay),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return days <= 1 ? streak : 0
    }

    static func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
    }

    // MARK: - Stockage partagé

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.storageKey)
    }
}
