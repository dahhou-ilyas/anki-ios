import SwiftUI
import WidgetKit

private let brand = Color(red: 0.33, green: 0.40, blue: 0.95)
private let reviewURL = URL(string: "memo://review")!

// MARK: - Données

struct MemoEntry: TimelineEntry {
    let date: Date
    let due: Int
    let done: Int
    let streak: Int
    let tomorrow: Int
    let hasCards: Bool

    var progress: Double { due == 0 ? 1 : Double(done) / Double(done + due) }

    static let sample = MemoEntry(date: .now, due: 12, done: 8, streak: 5, tomorrow: 9, hasCards: true)

    static func make(date: Date, snapshot: WidgetSnapshot?) -> MemoEntry {
        guard let snapshot else {
            return MemoEntry(date: date, due: 0, done: 0, streak: 0, tomorrow: 0, hasCards: false)
        }
        return MemoEntry(date: date,
                         due: snapshot.dueCount(on: date),
                         done: snapshot.doneCount(on: date),
                         streak: snapshot.streak(on: date),
                         tomorrow: snapshot.tomorrowCount(after: date),
                         hasCards: snapshot.hasCards)
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MemoEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (MemoEntry) -> Void) {
        completion(context.isPreview ? .sample : .make(date: .now, snapshot: WidgetSnapshot.load()))
    }

    /// Une entrée maintenant puis une à chaque minuit : le compte du jour change sans ouvrir l'app.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dates = [Date.now] + (1...7).map { calendar.date(byAdding: .day, value: $0, to: today)! }
        completion(Timeline(entries: dates.map { .make(date: $0, snapshot: snapshot) }, policy: .atEnd))
    }
}

// MARK: - Widget

@main
struct MemoWidgetBundle: WidgetBundle {
    var body: some Widget {
        MemoWidget()
    }
}

struct MemoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MemoWidget", provider: Provider()) { entry in
            MemoWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(reviewURL)
        }
        .configurationDisplayName("Révisions du jour")
        .description("Les cartes à réviser aujourd'hui et votre série. Touchez pour réviser.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct MemoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MemoEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumView(entry: entry)
        case .accessoryCircular: CircularView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

// MARK: - Écran d'accueil

private struct SmallView: View {
    let entry: MemoEntry

    private var footer: String {
        if entry.streak > 0 { return "\(entry.streak) jour\(entry.streak > 1 ? "s" : "") de suite" }
        if entry.due == 0 && entry.tomorrow > 0 { return "Demain : \(entry.tomorrow)" }
        return "Lancez votre série"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Mémo", systemImage: "brain.head.profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(brand)

            Spacer(minLength: 0)

            if !entry.hasCards {
                Text("Ajoutez vos premières cartes")
                    .font(.headline)
            } else if entry.due > 0 {
                Text("\(entry.due)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(entry.due == 1 ? "carte à réviser" : "cartes à réviser")
                    .font(.subheadline.weight(.medium))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
                Text("Tout est à jour")
                    .font(.headline)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            Label {
                Text(footer)
            } icon: {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let entry: MemoEntry

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(brand.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0.001, entry.progress))
                    .stroke(entry.due == 0 ? Color.green : brand, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if entry.due > 0 {
                    VStack(spacing: 0) {
                        Text("\(entry.due)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("à réviser")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                } else {
                    Image(systemName: "checkmark")
                        .font(.title.bold())
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 7) {
                Text(!entry.hasCards ? "Ajoutez des cartes" : entry.due > 0 ? "Révisions du jour" : "Tout est à jour !")
                    .font(.headline)
                StatRow(icon: "flame.fill", color: .orange,
                        text: "\(entry.streak) jour\(entry.streak > 1 ? "s" : "") de suite")
                StatRow(icon: "checkmark.circle.fill", color: .green,
                        text: "\(entry.done) révisée\(entry.done > 1 ? "s" : "") aujourd'hui")
                StatRow(icon: "calendar", color: brand,
                        text: "\(entry.tomorrow) prévue\(entry.tomorrow > 1 ? "s" : "") demain")
            }
            Spacer(minLength: 0)
        }
    }
}

private struct StatRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Écran verrouillé

private struct CircularView: View {
    let entry: MemoEntry

    var body: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "brain.head.profile")
        } currentValueLabel: {
            if entry.due > 0 {
                Text("\(entry.due)")
            } else {
                Image(systemName: "checkmark")
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

private struct RectangularView: View {
    let entry: MemoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Mémo", systemImage: "brain.head.profile")
                .font(.headline)
                .widgetAccentable()
            Text(entry.due > 0 ? "\(entry.due) carte\(entry.due > 1 ? "s" : "") à réviser" : "Tout est à jour")
            if entry.streak > 0 {
                Label("\(entry.streak) jour\(entry.streak > 1 ? "s" : "") de suite", systemImage: "flame.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
