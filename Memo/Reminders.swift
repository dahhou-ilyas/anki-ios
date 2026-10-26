import Foundation
import SwiftData
import UserNotifications

/// Notifications locales : rappel du matin avec le nombre de cartes, rappel du soir si l'on
/// n'a pas encore révisé, alerte quand une carte en apprentissage est prête, et badge sur l'icône.
@MainActor
enum Reminders {
    /// Nombre de jours programmés à l'avance pour chaque rappel
    /// (2 × 30 + 1 reste sous la limite de 64 notifications en attente imposée par iOS).
    private static let daysAhead = 30

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func refresh(context: ModelContext) async {
        // Le widget est mis à jour aux mêmes moments que les rappels, même si ceux-ci sont désactivés.
        WidgetSync.update(context: context)

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let enabled = UserDefaults.standard.bool(forKey: AppSettings.Key.remindersEnabled)
        let status = await center.notificationSettings().authorizationStatus
        let authorized = status == .authorized || status == .provisional
        guard enabled, authorized else {
            if authorized { try? await center.setBadgeCount(0) }
            return
        }

        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        let now = Date.now
        let calendar = Calendar.current
        let newLeftToday = StudyQueue.newLeft(for: decks, context: context, now: now)
        let fullNewLimit = Dictionary(uniqueKeysWithValues: decks.map { ($0.id, AppSettings.newPerDay) })

        func dueCount(dayOffset: Int) -> Int {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            let newLeft = dayOffset == 0 ? newLeftToday : fullNewLimit
            return StudyQueue.counts(for: decks, newLeft: newLeft, until: StudyQueue.endOfDay(day)).total
        }

        func fireDate(dayOffset: Int, time: (hour: Int, minute: Int)) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
                  date > now else { return nil }
            return date
        }

        try? await center.setBadgeCount(dueCount(dayOffset: 0))

        // Rappel du matin, à l'heure choisie.
        for offset in 0..<daysAhead {
            guard let date = fireDate(dayOffset: offset, time: AppSettings.reminderTime) else { continue }
            let count = dueCount(dayOffset: offset)
            guard count > 0 else { continue }
            await schedule("daily-\(offset)", at: date, badge: count,
                           title: "C'est l'heure de réviser",
                           body: count == 1
                               ? "1 carte vous attend (\(StudyQueue.estimatedDuration(cards: 1)))."
                               : "\(count) cartes vous attendent (\(StudyQueue.estimatedDuration(cards: count))).")
        }

        // Rappel du soir, seulement les jours sans révision. Réviser dans la journée met à jour
        // les rappels en quittant l'app, ce qui supprime celui du soir.
        if AppSettings.eveningReminderEnabled {
            let reviewDays = StudyQueue.reviewDays(context: context, now: now)
            let reviewedToday = reviewDays.contains(calendar.startOfDay(for: now))
            let streak = StudyQueue.streak(days: reviewDays, now: now)

            for offset in 0..<daysAhead {
                if offset == 0 && reviewedToday { continue }
                guard let date = fireDate(dayOffset: offset, time: AppSettings.eveningTime) else { continue }
                let count = dueCount(dayOffset: offset)
                guard count > 0 else { continue }
                let cards = count == 1 ? "1 carte vous attend" : "\(count) cartes vous attendent"
                // La série en jeu n'est connue que pour aujourd'hui.
                let body = offset == 0 && streak > 0
                    ? "\(cards) : \(StudyQueue.estimatedDuration(cards: count)) pour garder votre série de \(streak) jour\(streak > 1 ? "s" : "") 🔥"
                    : "\(cards). Quelques minutes suffisent pour garder le rythme 🔥"
                await schedule("evening-\(offset)", at: date, badge: count,
                               title: "Vous n'avez pas encore révisé aujourd'hui", body: body)
            }
        }

        // Carte en apprentissage : prévenir au moment exact où elle doit être revue.
        if let nextLearning = StudyQueue.nextLearningDue(in: decks, now: now) {
            let content = UNMutableNotificationContent()
            content.title = "Une carte est prête"
            content.body = "C'est le bon moment pour la revoir et bien la retenir."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, nextLearning.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "learning", content: content, trigger: trigger))
        }
    }

    private static func schedule(_ identifier: String, at date: Date, badge: Int, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: badge)

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
