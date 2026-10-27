import Foundation
import SwiftData

/// Cartes intégrées à l'app : une carte par problème résolu, dans le paquet « Patterns ».
/// Recto : l'énoncé en une phrase. Verso : le pattern, puis l'idée clé. Jamais de code.
///
/// Pour ajouter un problème, ajoutez une entrée avec un nouvel identifiant : au prochain
/// lancement, seules les cartes jamais importées sont ajoutées (les autres ne sont pas
/// dupliquées, et une carte supprimée dans l'app ne revient pas).
enum StarterDeck {
    struct Entry {
        let id: String
        let front: String
        let back: String
    }

    static let deckName = "Patterns"
    static let deckID = UUID(uuidString: "5A7E2B10-7A77-4E2B-9C1D-0D0A70E5C0DE")!

    static let entries: [Entry] = [
        // Arrays & Hashing
        Entry(id: "contains-duplicate",
              front: "Un tableau d'entiers : est-ce qu'une valeur apparaît au moins deux fois ?",
              back: "Arrays & Hashing.\nUn Set des valeurs déjà vues : si le nombre courant y est déjà, c'est un doublon."),
        Entry(id: "valid-anagram",
              front: "Deux chaînes : est-ce que l'une est une anagramme de l'autre ?",
              back: "Arrays & Hashing.\nUn tableau de 26 compteurs : +1 pour chaque lettre de s, −1 pour chaque lettre de t, et tout doit revenir à 0."),
        Entry(id: "two-sum",
              front: "Un tableau et une cible : trouver les indices des deux nombres dont la somme vaut la cible.",
              back: "Arrays & Hashing.\nUne map valeur → indice : pour chaque nombre, chercher si « cible − nombre » a déjà été vu."),
        Entry(id: "group-anagrams",
              front: "Une liste de mots : regrouper ensemble ceux qui sont des anagrammes.",
              back: "Arrays & Hashing.\nUne map signature → groupe, où la signature est les 26 compteurs de lettres du mot (ou le mot trié)."),
        Entry(id: "top-k-frequent-elements",
              front: "Un tableau et k : renvoyer les k valeurs les plus fréquentes.",
              back: "Arrays & Hashing (bucket sort).\nCompter les fréquences, puis un tableau de seaux où l'indice = la fréquence ; parcourir les seaux de la fin jusqu'à en avoir k."),
        Entry(id: "encode-decode-strings",
              front: "Encoder une liste de chaînes en une seule chaîne, puis la décoder sans rien perdre.",
              back: "Arrays & Hashing.\nPréfixer chaque chaîne par « longueur + # » : au décodage, lire la longueur jusqu'au #, puis prendre exactement ce nombre de caractères."),
        Entry(id: "product-of-array-except-self",
              front: "Pour chaque case d'un tableau, le produit de toutes les autres cases, sans division.",
              back: "Arrays & Hashing (préfixe / suffixe).\nComme une somme préfixe mais avec des produits : produit de tout ce qui est à gauche × produit de tout ce qui est à droite."),
        Entry(id: "valid-sudoku",
              front: "Une grille de Sudoku 9×9 partiellement remplie : est-elle valide ?",
              back: "Arrays & Hashing.\nUn Set par ligne, par colonne et par box 3×3 (box = ligne/3, colonne/3) : un chiffre déjà présent dans l'un d'eux = invalide."),
        Entry(id: "longest-consecutive-sequence",
              front: "Un tableau non trié : la longueur de la plus longue suite d'entiers consécutifs, en O(n).",
              back: "Arrays & Hashing (Set).\nTout mettre dans un Set ; ne compter qu'à partir d'un début de suite (n − 1 absent), puis avancer n + 1, n + 2… tant qu'ils existent."),

        // Two Pointers
        Entry(id: "valid-palindrome",
              front: "Une phrase : est-ce un palindrome, en ignorant la casse et tout ce qui n'est pas lettre ou chiffre ?",
              back: "Two Pointers.\nUn pointeur au début, un à la fin : sauter les caractères non alphanumériques, comparer en minuscules, puis se rapprocher."),
    ]

    private static let importedKey = "starterDeck.importedIDs"
    private static let removedSampleKey = "starterDeck.removedSampleDeck"
    /// Paquet d'exemple des premières versions de l'app, supprimé une seule fois.
    private static let legacySampleDeckName = "Exemple — Capitales"

    @MainActor
    static func install(into context: ModelContext) {
        let defaults = UserDefaults.standard

        if !defaults.bool(forKey: removedSampleKey) {
            let name = legacySampleDeckName
            let samples = (try? context.fetch(FetchDescriptor<Deck>(predicate: #Predicate { $0.name == name }))) ?? []
            samples.forEach(context.delete)
            defaults.set(true, forKey: removedSampleKey)
        }

        var imported = Set(defaults.stringArray(forKey: importedKey) ?? [])
        let missing = entries.filter { !imported.contains($0.id) }
        guard !missing.isEmpty else {
            try? context.save()
            return
        }

        let deck = patternsDeck(in: context)
        let now = Date.now
        for (index, entry) in missing.enumerated() {
            // Décalage d'une milliseconde pour garder l'ordre de la liste.
            let card = Card(front: entry.front, back: entry.back, createdAt: now.addingTimeInterval(Double(index) / 1000))
            context.insert(card)
            card.deck = deck
        }
        imported.formUnion(missing.map(\.id))
        defaults.set(Array(imported).sorted(), forKey: importedKey)
        try? context.save()
    }

    /// Le paquet « Patterns » existant (créé par l'app ou à la main), ou un nouveau.
    @MainActor
    private static func patternsDeck(in context: ModelContext) -> Deck {
        let id = deckID
        if let deck = try? context.fetch(FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id })).first {
            return deck
        }
        let name = deckName
        if let deck = try? context.fetch(FetchDescriptor<Deck>(predicate: #Predicate { $0.name == name })).first {
            return deck
        }
        let deck = Deck(name: deckName)
        deck.id = deckID
        context.insert(deck)
        return deck
    }
}
