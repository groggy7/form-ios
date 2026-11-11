import Foundation

/// Search tolerance never changes canonical IDs, saved workouts or catalogue deduplication.
enum ExerciseSearch {
    static func normalize(_ text: String) -> String {
        text.decomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\\p{M}+", with: "", options: .regularExpression)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    struct Query {
        let originalPhrase: String
        let phrase: String
        let tokens: [Token]
        let isDiscovery: Bool
        init(_ text: String) {
            originalPhrase = ExerciseSearch.normalize(text)
            var seen = Set<String>()
            let words = originalPhrase.split(separator: " ").map(String.init).filter { seen.insert($0).inserted }
            let useful = words.filter { !ExerciseSearch.fillerWords.contains($0) }
            tokens = (useful.isEmpty ? words : useful).map(Token.init)
            phrase = tokens.map(\.text).joined(separator: " ")
            isDiscovery = tokens.contains { !$0.terms.isDisjoint(with: ExerciseSearch.muscleWords) } &&
                tokens.allSatisfy { !$0.terms.isDisjoint(with: ExerciseSearch.muscleWords.union(ExerciseSearch.equipmentWords)) }
        }
    }

    private static let muscleAliases: [String: Set<String>] = [
        "chest": Set("chest pec pecs pectoral pectorals pectoraux pecho brust gogus pectorales".split(separator: " ").map(String.init)),
        "back": Set("back sirt rucken dos espalda".split(separator: " ").map(String.init)),
        "shoulders": Set("shoulder shoulders delt delts deltoid deltoids omuz omuzlar schultern epaule epaules hombro hombros".split(separator: " ").map(String.init)),
        "biceps": Set("bicep biceps bizeps biseps".split(separator: " ").map(String.init)),
        "triceps": Set("tricep triceps trizeps triseps".split(separator: " ").map(String.init)),
        "forearms": Set("forearm forearms onkol unterarme avantbras antebrazo antebrazos on kol avant bras".split(separator: " ").map(String.init)),
        "quads": Set("quad quads quadriceps quadrizeps cuadriceps on bacak".split(separator: " ").map(String.init)),
        "adductors": Set("adductor adductors adduktoren adducteurs aductores ic bacak".split(separator: " ").map(String.init)),
        "hamstrings": Set("hamstring hamstrings ischios isquiotibiales arka bacak beinbeuger ischio jambiers".split(separator: " ").map(String.init)),
        "glutes": Set("glute glutes gluteus kalca gesass fessiers gluteos gesaß".split(separator: " ").map(String.init)),
        "calves": Set("calf calves baldir waden mollets gemelos pantorrillas".split(separator: " ").map(String.init)),
        "shins": Set("shin shins tibialis schienbein tibial kaval kasi schienbeinmuskel anterieur anterior".split(separator: " ").map(String.init)),
        "core": Set("ab abs abdominal abdominals core karin rumpf abdos abdominaux abdomen abdominales".split(separator: " ").map(String.init)),
        "hip-flexors": Set("hip flexor flexors hipflexor hipflexors iliopsoas psoas kalca fleksorleri kalcafleksoru huftbeuger flechisseurs de hanche flexores cadera".split(separator: " ").map(String.init)),
        "hip-abductors": Set("hip abduction abductor abductors kalca abduktorleri kalcaabduktoru huftabduktoren abduktoren abducteurs de hanche abductores cadera".split(separator: " ").map(String.init)),
        "serratus": Set("serratus anterior serrato vorderer sagemuskel dentele anterieur".split(separator: " ").map(String.init)),
        "rotator-cuff": Set("rotator cuff manset rotatorenmanschette coiffe des rotateurs manguito rotador".split(separator: " ").map(String.init)),
        "neck": Set("neck boyun nacken cou cuello".split(separator: " ").map(String.init)),
        "deep-core": Set("deep core derin merkez kaslari tiefe rumpfmuskeln muscles profonds du tronc musculos profundos del tronco transversus multifidus quadratus deepcore".split(separator: " ").map(String.init)),
        "front-delts": Set("front anterior on omuz vordere schultern epaules anterieures hombros anteriores shoulders deltoides anterieurs".split(separator: " ").map(String.init)),
        "side-delts": Set("side lateral yan omuz seitliche schultern epaules laterales hombros shoulders deltoides lateraux".split(separator: " ").map(String.init)),
        "rear-delts": Set("rear posterior arka omuz hintere schultern epaules posterieures hombros posteriores shoulders deltoides posterieurs".split(separator: " ").map(String.init)),
        "upper-back": Set("upper back traps trapezius rhomboid rhomboids ust sirt oberer rucken haut du dos espalda superior alta".split(separator: " ").map(String.init)),
        "lats": Set("lat lats latissimus kanat kaslari grand dorsal dorsales".split(separator: " ").map(String.init)),
        "lower-back": Set("lower back lumbar erector erectors bel unterer rucken bas du dos espalda baja zona".split(separator: " ").map(String.init)),
        "abs": Set("rectus abdominis abdominals karin kaslari bauchmuskeln abdominaux abdominales".split(separator: " ").map(String.init)),
        "obliques": Set("oblique obliques yan karin seitliche bauchmuskeln oblicuos".split(separator: " ").map(String.init)),
        "cardio": Set("cardio conditioning kondisyon ausdauer endurance acondicionamiento".split(separator: " ").map(String.init))
    ]
    private static let equipmentAliases: [String: Set<String>] = [
        "barbell": Set("bar barbell barbells bb langhantel barre barra".split(separator: " ").map(String.init)),
        "dumbbell": Set("dumbbell dumbbells db dambil kurzhantel kurzhanteln haltere halteres mancuerna mancuernas".split(separator: " ").map(String.init)),
        "kettlebell": Set("kettlebell kettlebells kb".split(separator: " ").map(String.init)),
        "cable": Set("cable cables pulley kablo makara kabel polea poulie".split(separator: " ").map(String.init)),
        "band": Set("band bands resistance direnc resistencia elastique".split(separator: " ").map(String.init)),
        "machine": Set("machine machines makine maschine maquina".split(separator: " ").map(String.init)),
        "plate": Set("plate plates plaka scheibe disque disco".split(separator: " ").map(String.init)),
        "bodyweight": Set("bodyweight body weight".split(separator: " ").map(String.init))
    ]

    private static let muscleWords = Set(muscleAliases.values.flatMap { $0 })
    private static let equipmentWords = Set(equipmentAliases.values.flatMap { $0 })
    private static let fillerWords: Set<String> = ["exercise", "exercises", "workout", "workouts", "training", "routine", "routines",
        "egzersiz", "egzersizler", "hareket", "hareketler", "antrenman", "ubung", "ubungen",
        "exercice", "exercices", "entrainement", "ejercicio", "ejercicios", "entrenamiento"]
    private static let keywords: [String: Set<String>] = ExerciseCatalog.canonicalExercises.mapValues {
        Set($0.searchKeywords.flatMap { normalize($0).split(separator: " ").map(String.init) })
    }
    private static let vocabulary: Set<String> = Set(keywords.values.flatMap { $0 } +
        ExerciseCatalog.canonicalExercises.values.flatMap { normalize($0.name).split(separator: " ").map(String.init) })
        .union(muscleWords).union(equipmentWords)

    struct Token {
        let text: String
        let terms: Set<String>
        private let singular: [String]
        private let corrections: [String]
        private let allowFuzzy: Bool
        init(_ text: String) {
            self.text = text
            var roots = Set<String>()
            if text.count > 3 && text.hasSuffix("s") && !text.hasSuffix("ss") { roots.insert(String(text.dropLast())) }
            if text.count > 4 && text.hasSuffix("es") { roots.insert(String(text.dropLast(2))) }
            if text.count > 4 && text.hasSuffix("ies") { roots.insert(String(text.dropLast(3)) + "y") }
            singular = roots.filter { ExerciseSearch.vocabulary.contains($0) }
            allowFuzzy = text.count >= 4 && singular.isEmpty && !ExerciseSearch.vocabulary.contains { $0.hasPrefix(text) }
            if allowFuzzy {
                let nearby = ExerciseSearch.vocabulary.compactMap { word -> (String, Int)? in
                    ExerciseSearch.distance(text, word).map { (word, $0) }
                }
                let best = nearby.map { $0.1 }.min()
                corrections = nearby.filter { $0.1 == best }.map { $0.0 }
            } else { corrections = [] }
            terms = Set([text] + singular + corrections)
        }
        fileprivate func cost(_ words: [String], custom: Bool = false) -> Int? {
            if words.contains(where: { $0.hasPrefix(text) }) { return 0 }
            if singular.contains(where: { root in words.contains { $0.hasPrefix(root) } }) { return 1 }
            if corrections.contains(where: { corrected in words.contains { $0.hasPrefix(corrected) } }) { return 2 }
            return custom && allowFuzzy && words.contains(where: { ExerciseSearch.distance(text, $0) != nil }) ? 2 : nil
        }
    }

    /// Bounded Damerau-Levenshtein: transpositions count once; never guess short abbreviations.
    private static func distance(_ a: String, _ b: String) -> Int? {
        let left = Array(a.utf16), right = Array(b.utf16)
        let limit = left.count >= 7 ? 2 : 1
        guard right.count >= 4, abs(left.count - right.count) <= limit else { return nil }
        var previous = Array(0...right.count)
        var beforePrevious = previous
        for i in 1...left.count {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = i
            for j in 1...right.count {
                current[j] = min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1))
                if i > 1 && j > 1 && left[i - 1] == right[j - 2] && left[i - 2] == right[j - 1] {
                    current[j] = min(current[j], beforePrevious[j - 2] + 1)
                }
            }
            if current.min()! > limit { return nil }
            beforePrevious = previous
            previous = current
        }
        return previous[right.count] <= limit ? previous[right.count] : nil
    }

    struct Candidate {
        let names: [String]
        let nameWords: [[String]]
        let words: [String]
        let discoveryWords: [String]
        let supportingWords: [String]
        let custom: Bool
        init(exercise: Exercise, localizedName: String? = nil, category: String = "") {
            names = [exercise.name, localizedName ?? exercise.name].map(ExerciseSearch.normalize)
            nameWords = names.map { $0.split(separator: " ").map(String.init) }
            var muscles = (ExerciseMuscleCatalog.shared?.profile(exercise.exerciseId)?.primary ?? []).flatMap { key -> [String] in
                let broad: String
                switch key {
                case "lats", "upper-back", "lower-back": broad = "back"
                case "front-delts", "side-delts", "rear-delts": broad = "shoulders"
                case "abs", "obliques": broad = "core"
                case "tibialis": broad = "shins"
                default: broad = key
                }
                return [key, broad]
            }
            if muscles.isEmpty {
                muscles = [ExerciseMetadata.resolveMuscleKey(exerciseId: exercise.exerciseId, name: exercise.name,
                    movementType: exercise.resolvedMovement).replacingOccurrences(of: "exercise.muscle.", with: "")]
            }
            if ExerciseMetadata.matchesMuscle(exercise: exercise, muscleKey: "cardio") { muscles.append("cardio") }
            let equipment = ExerciseMetadata.resolveEquipmentKey(exerciseId: exercise.exerciseId, name: exercise.name,
                searchKeywords: exercise.exerciseId.flatMap { ExerciseCatalog.canonicalExercises[$0]?.searchKeywords } ?? [])
                .replacingOccurrences(of: "exercise.equipment.", with: "")
            discoveryWords = muscles.flatMap { Array(ExerciseSearch.muscleAliases[$0] ?? []) } + Array(ExerciseSearch.equipmentAliases[equipment] ?? [])
            supportingWords = (ExerciseMuscleCatalog.shared?.profile(exercise.exerciseId)?.secondary ?? []).flatMap { key -> [String] in
                let broad: String
                switch key {
                case "lats", "upper-back", "lower-back": broad = "back"
                case "front-delts", "side-delts", "rear-delts": broad = "shoulders"
                case "abs", "obliques": broad = "core"
                case "tibialis": broad = "shins"
                default: broad = key
                }
                return Array(ExerciseSearch.muscleAliases[key] ?? []) + Array(ExerciseSearch.muscleAliases[broad] ?? [])
            }
            words = Array(Set(nameWords.flatMap { $0 } + Array(exercise.exerciseId.flatMap { ExerciseSearch.keywords[$0] } ?? []) +
                ExerciseSearch.normalize(category).split(separator: " ").map(String.init) + discoveryWords + supportingWords))
            custom = exercise.exerciseId.flatMap { ExerciseCatalog.canonicalExercises[$0] } == nil
        }
    }

    /// Literal matches precede plurals and typos. Every meaningful query word must match.
    static func score(_ query: Query, exercise: Exercise, localizedName: String? = nil, category: String = "") -> Int? {
        if query.tokens.isEmpty { return 0 }
        return score(query, candidate: Candidate(exercise: exercise, localizedName: localizedName, category: category))
    }
    static func score(_ query: Query, candidate: Candidate) -> Int? {
        if query.tokens.isEmpty { return 0 }
        func cost(_ words: [String]) -> Int? {
            var total = 0
            for token in query.tokens {
                if query.isDiscovery && ["lat", "lats"].contains(token.text) && !words.contains("lat") && !words.contains("lats") { return nil }
                guard let value = token.cost(words, custom: candidate.custom) else { return nil }
                total += value
            }
            return total
        }
        if candidate.names.contains(query.originalPhrase) || candidate.names.contains(query.phrase) { return 0 }
        if query.isDiscovery {
            return [cost(candidate.discoveryWords).map { 10 + 100 * $0 },
                    cost(candidate.discoveryWords + candidate.supportingWords).map { 60 + 100 * $0 }].compactMap { $0 }.min()
        }
        if candidate.names.contains(where: { (" " + $0).contains(" " + query.phrase) }) { return 20 }
        let nameCost = candidate.nameWords.compactMap(cost).min()
        let allCost = cost(candidate.words)
        return [nameCost.map { 30 + 100 * $0 }, allCost.map { 40 + 100 * $0 }].compactMap { $0 }.min()
    }
}

/// UI-thread cache retained by AppStore across Library tab mounts. Keeps one filter result.
final class LibraryExerciseResults {
    private var source: [ExerciseCatalogEntry]?
    private var language: String?
    private var ordered: [ExerciseCatalogEntry] = []
    private var prepared: [(entry: ExerciseCatalogEntry, candidate: ExerciseSearch.Candidate)]?
    private struct Filter: Equatable {
        let query: String
        let equipment: String?
        let muscle: String?
    }
    private var lastFilter: Filter?
    private var lastResult: [ExerciseCatalogEntry] = []

    func entries(catalogue: [ExerciseCatalogEntry], query: String = "",
                 equipmentKey: String? = nil, muscleKey: String? = nil) -> [ExerciseCatalogEntry] {
        let currentLanguage = LanguageManager.shared.currentLanguage
        if source != catalogue || language != currentLanguage {
            source = catalogue
            language = currentLanguage
            // Custom exercise ties must follow the current localized names.
            ordered = catalogue.sorted { ExercisePriority.compare($0.exercise, $1.exercise) }
            lastFilter = nil
            prepared = nil
        }
        let filter = Filter(query: query, equipment: equipmentKey, muscle: muscleKey)
        if lastFilter == filter { return lastResult }
        let search = ExerciseSearch.Query(query)
        // Muscle rank: 0 when the filter names a primary target, 1 for supporting work.
        var ranks: [String: Int]? = nil
        if equipmentKey != nil || muscleKey != nil {
            var matched: [String: Int] = [:]
            for entry in ordered {
                guard equipmentKey == nil || EquipmentCatalog.shared.matches(entry.exercise.exerciseId, selected: equipmentKey) else { continue }
                if let muscleKey {
                    guard let rank = ExerciseMetadata.muscleMatchRank(exercise: entry.exercise, muscleKey: muscleKey) else { continue }
                    matched[entry.key] = rank
                } else {
                    matched[entry.key] = 0
                }
            }
            ranks = matched
        }
        if search.tokens.isEmpty {
            if let ranks {
                // Stable partition keeps exercise priority within primary and supporting matches.
                let matching = ordered.filter { ranks[$0.key] != nil }
                lastResult = matching.filter { ranks[$0.key] == 0 } + matching.filter { ranks[$0.key] != 0 }
            } else {
                lastResult = ordered
            }
        } else {
            // Build once on first search, preserving the empty-library launch path.
            let candidates = prepared ?? ordered.map { entry in
                (entry: entry, candidate: ExerciseSearch.Candidate(exercise: entry.exercise,
                    localizedName: entry.exercise.displayName,
                    category: "\(LanguageManager.t("category.\(entry.exercise.resolvedMovement.rawValue)")) \(entry.exercise.metadataSubtitle)"))
            }
            prepared = candidates
            lastResult = candidates.compactMap { item -> (ExerciseCatalogEntry, Int, Int)? in
                let rank = ranks == nil ? 0 : ranks?[item.entry.key]
                guard let rank, let score = ExerciseSearch.score(search, candidate: item.candidate) else { return nil }
                return (item.entry, score, rank)
            // Swift's stable sort retains the cached priority order for ties; primary targets lead equal scores.
            }.sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map { $0.0 }
        }
        lastFilter = filter
        return lastResult
    }
}
