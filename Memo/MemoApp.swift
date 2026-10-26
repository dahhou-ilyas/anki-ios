import SwiftData
import SwiftUI

@main
struct MemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Deck.self, Card.self, ReviewLog.self])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.Key.hasOnboarded) private var hasOnboarded = false
    @State private var tab = Tab.home
    @State private var homePath: [StudyRoute] = []

    private enum Tab { case home, cards, settings }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(path: $homePath)
                .tabItem { Label("Réviser", systemImage: "brain.head.profile") }
                .tag(Tab.home)
            BrowseView()
                .tabItem { Label("Cartes", systemImage: "rectangle.on.rectangle") }
                .tag(Tab.cards)
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onOpenURL { url in
            // Lien ouvert depuis le widget : memo://review lance une séance sur tous les paquets.
            guard url.scheme == "memo", url.host == "review", hasOnboarded else { return }
            tab = .home
            homePath = [.all]
        }
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { if !$0 { hasOnboarded = true } })) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .task { await Reminders.refresh(context: context) }
        .onChange(of: scenePhase) { _, phase in
            // Met à jour le badge et les rappels en quittant / en revenant dans l'app.
            if phase != .inactive {
                Task { await Reminders.refresh(context: context) }
            }
        }
    }
}
