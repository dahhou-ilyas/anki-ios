import Foundation

enum AppSettings {
    enum Key {
        static let newPerDay = "newPerDay"
        static let learningSteps = "learningSteps"
        static let relearningSteps = "relearningSteps"
        static let remindersEnabled = "remindersEnabled"
        static let reminderHour = "reminderHour"
        static let reminderMinute = "reminderMinute"
        static let eveningReminderEnabled = "eveningReminderEnabled"
        static let eveningHour = "eveningHour"
        static let eveningMinute = "eveningMinute"
        static let hasOnboarded = "hasOnboarded"
    }

    static let defaultNewPerDay = 20
    static let defaultLearningSteps = "1 10"
    static let defaultRelearningSteps = "10"

    private static var defaults: UserDefaults { .standard }

    static var newPerDay: Int {
        defaults.object(forKey: Key.newPerDay) as? Int ?? defaultNewPerDay
    }

    static var reminderTime: (hour: Int, minute: Int) {
        (defaults.object(forKey: Key.reminderHour) as? Int ?? 9,
         defaults.object(forKey: Key.reminderMinute) as? Int ?? 0)
    }

    static var eveningReminderEnabled: Bool {
        defaults.object(forKey: Key.eveningReminderEnabled) as? Bool ?? true
    }

    static var eveningTime: (hour: Int, minute: Int) {
        (defaults.object(forKey: Key.eveningHour) as? Int ?? 20,
         defaults.object(forKey: Key.eveningMinute) as? Int ?? 0)
    }

    static var schedulerConfig: SchedulerConfig {
        var config = SchedulerConfig()
        config.learningSteps = parseSteps(defaults.string(forKey: Key.learningSteps) ?? defaultLearningSteps)
        config.relearningSteps = parseSteps(defaults.string(forKey: Key.relearningSteps) ?? defaultRelearningSteps)
        return config
    }

    /// « 1 10 » → [1, 10] (minutes)
    static func parseSteps(_ text: String) -> [Double] {
        text.split(whereSeparator: { " ,;".contains($0) })
            .compactMap { Double($0) }
            .filter { $0 > 0 }
    }
}
