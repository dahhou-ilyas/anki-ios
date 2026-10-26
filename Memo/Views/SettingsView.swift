import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.Key.newPerDay) private var newPerDay = AppSettings.defaultNewPerDay
    @AppStorage(AppSettings.Key.learningSteps) private var learningSteps = AppSettings.defaultLearningSteps
    @AppStorage(AppSettings.Key.relearningSteps) private var relearningSteps = AppSettings.defaultRelearningSteps
    @AppStorage(AppSettings.Key.remindersEnabled) private var remindersEnabled = false
    @AppStorage(AppSettings.Key.reminderHour) private var reminderHour = 9
    @AppStorage(AppSettings.Key.reminderMinute) private var reminderMinute = 0
    @AppStorage(AppSettings.Key.eveningReminderEnabled) private var eveningReminderEnabled = true
    @AppStorage(AppSettings.Key.eveningHour) private var eveningHour = 20
    @AppStorage(AppSettings.Key.eveningMinute) private var eveningMinute = 0

    @State private var showingDeniedAlert = false
    @State private var exportDocument: BackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImport: Backup?
    @State private var confirmErase = false
    @State private var message: String?

    /// Relie un sélecteur d'heure à une heure et une minute enregistrées séparément.
    private func time(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: .now) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            hour.wrappedValue = components.hour ?? 0
            minute.wrappedValue = components.minute ?? 0
        }
    }

    var body: some View {
        NavigationStack {
            withDialogs(withHandlers(form))
                .navigationTitle("Réglages")
        }
    }

    private var form: some View {
        Form {
            Section {
                Toggle("Rappels", isOn: $remindersEnabled)
                if remindersEnabled {
                    DatePicker("Rappel du matin", selection: time(hour: $reminderHour, minute: $reminderMinute),
                               displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Chaque matin à cette heure, Mémo vous dit combien de cartes vous attendent. Vous êtes aussi prévenu quand une carte en cours d'apprentissage doit être revue.")
            }

            if remindersEnabled {
                Section {
                    Toggle("Rappel du soir", isOn: $eveningReminderEnabled)
                    if eveningReminderEnabled {
                        DatePicker("Heure", selection: time(hour: $eveningHour, minute: $eveningMinute),
                                   displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Seulement les jours où vous n'avez pas encore révisé, pour ne pas casser votre série 🔥. Si vous avez déjà révisé, vous ne recevez rien.")
                }
            }

            Section {
                Stepper(value: $newPerDay, in: 0...200, step: 5) {
                    LabeledContent("Nouvelles cartes par jour", value: "\(newPerDay)")
                }
            } header: {
                Text("Rythme")
            } footer: {
                Text("Par paquet. 10 à 20 nouvelles cartes par jour est un bon rythme : chaque nouvelle carte entraîne des révisions les jours suivants.")
            }

            Section {
                LabeledContent("Apprentissage") {
                    TextField(AppSettings.defaultLearningSteps, text: $learningSteps)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                }
                LabeledContent("Après un oubli") {
                    TextField(AppSettings.defaultRelearningSteps, text: $relearningSteps)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                }
            } header: {
                Text("Étapes (en minutes)")
            } footer: {
                Text("Délais de répétition le jour même, séparés par des espaces. Par défaut : « 1 10 » pour une nouvelle carte et « 10 » pour une carte oubliée.")
            }

            Section {
                Button("Exporter une sauvegarde", systemImage: "square.and.arrow.up", action: export)
                Button("Restaurer une sauvegarde", systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }
                Button("Tout effacer", systemImage: "trash", role: .destructive) {
                    confirmErase = true
                }
            } header: {
                Text("Données")
            } footer: {
                Text("La sauvegarde est un fichier JSON avec vos paquets, vos cartes et votre progression. Restaurer remplace toutes les données actuelles.")
            }

            Section("Comment ça marche ?") {
                HowItWorksRow(icon: "1.circle.fill", text: "Une nouvelle carte est revue après 1 min puis 10 min pour l'ancrer.")
                HowItWorksRow(icon: "2.circle.fill", text: "Ensuite elle revient dans 1 jour, puis 3, 8, 20 jours… L'écart grandit à chaque bonne réponse.")
                HowItWorksRow(icon: "3.circle.fill", text: "« Oublié » la fait revenir tout de suite ; « Facile » l'éloigne davantage.")
                HowItWorksRow(icon: "4.circle.fill", text: "Ainsi vous révisez chaque carte juste avant de l'oublier : un minimum d'effort pour un maximum de mémoire.")
            }
        }
    }

    private func withHandlers(_ content: some View) -> some View {
        content
            .onChange(of: remindersEnabled) { _, enabled in
                Task {
                    if enabled, !(await Reminders.requestAuthorization()) {
                        remindersEnabled = false
                        showingDeniedAlert = true
                    }
                    await Reminders.refresh(context: context)
                }
            }
            .onChange(of: reminderHour) { refreshReminders() }
            .onChange(of: reminderMinute) { refreshReminders() }
            .onChange(of: eveningReminderEnabled) { refreshReminders() }
            .onChange(of: eveningHour) { refreshReminders() }
            .onChange(of: eveningMinute) { refreshReminders() }
            .onChange(of: newPerDay) { refreshReminders() }
            .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json,
                          defaultFilename: "memo-sauvegarde-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
                if case .failure(let error) = result { message = "Export impossible : \(error.localizedDescription)" }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                readBackup(result)
            }
    }

    private func withDialogs(_ content: some View) -> some View {
        content
            .confirmationDialog(
                "Remplacer toutes les données ?",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                titleVisibility: .visible,
                presenting: pendingImport
            ) { backup in
                Button("Restaurer \(backup.decks.count) paquets et \(backup.cardCount) cartes", role: .destructive) {
                    restore(backup)
                }
            } message: { _ in
                Text("Les paquets et cartes actuels seront remplacés par ceux de la sauvegarde.")
            }
            .confirmationDialog("Effacer toutes les données ?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) {
                    try? Backup.eraseAll(in: context)
                    refreshReminders()
                }
            } message: {
                Text("Tous les paquets, cartes et statistiques seront supprimés. Pensez à exporter une sauvegarde avant.")
            }
            .alert("Notifications désactivées", isPresented: $showingDeniedAlert) {
                Button("Ouvrir les Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Autorisez les notifications pour Mémo dans les Réglages de l'iPhone pour recevoir les rappels.")
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
    }

    private func refreshReminders() {
        Task { await Reminders.refresh(context: context) }
    }

    private func export() {
        do {
            exportDocument = BackupDocument(data: try Backup.make(from: context).encoded())
            showingExporter = true
        } catch {
            message = "Export impossible : \(error.localizedDescription)"
        }
    }

    private func readBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            pendingImport = try Backup.decode(Data(contentsOf: url))
        } catch {
            message = "Ce fichier n'est pas une sauvegarde Mémo valide."
        }
    }

    private func restore(_ backup: Backup) {
        do {
            try backup.restore(into: context)
            message = "Sauvegarde restaurée : \(backup.cardCount) cartes."
            refreshReminders()
        } catch {
            message = "Restauration impossible : \(error.localizedDescription)"
        }
    }
}

private struct HowItWorksRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
    }
}
