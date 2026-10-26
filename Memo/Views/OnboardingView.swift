import SwiftData
import SwiftUI

/// Écran d'accueil au premier lancement : explique la méthode et propose les rappels.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.Key.hasOnboarded) private var hasOnboarded = false
    @AppStorage(AppSettings.Key.remindersEnabled) private var remindersEnabled = false
    @State private var addSample = true

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Bienvenue dans Mémo")
                    .font(.largeTitle.bold())
                Text("Retenez durablement ce que vous apprenez, en quelques minutes par jour.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 20) {
                Point(icon: "questionmark.bubble", color: .blue,
                      title: "Cherchez la réponse de tête",
                      text: "Faire l'effort de se souvenir est ce qui fixe la mémoire.")
                Point(icon: "hand.tap", color: .orange,
                      title: "Soyez honnête",
                      text: "Dites si c'était oublié, difficile, bien ou facile.")
                Point(icon: "calendar.badge.clock", color: .green,
                      title: "Mémo s'occupe du calendrier",
                      text: "Chaque carte revient juste avant que vous l'oubliiez, de plus en plus espacée.")
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Toggle("Ajouter un paquet d'exemple", isOn: $addSample)
                    .padding(.horizontal, 4)

                Button {
                    Task { await finish(enableReminders: true) }
                } label: {
                    Text("Activer les rappels et commencer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Plus tard") {
                    Task { await finish(enableReminders: false) }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private func finish(enableReminders: Bool) async {
        if addSample {
            let existing = (try? context.fetchCount(FetchDescriptor<Deck>())) ?? 0
            if existing == 0 { SampleData.insert(into: context) }
        }
        if enableReminders {
            remindersEnabled = await Reminders.requestAuthorization()
        }
        await Reminders.refresh(context: context)
        hasOnboarded = true
        dismiss()
    }
}

private struct Point: View {
    let icon: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
