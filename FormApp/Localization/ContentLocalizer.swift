import Foundation

public struct ExerciseLocaleData: Codable {
    public var name: String?
    public var cues: [String]?
    public var avoid: [String]?
}

public struct WorkoutLocaleData: Codable {
    public var title: String?
    public var focus: String?
}

public struct ProgramLocaleData: Codable {
    public var name: String?
    public var description: String?
    public var guidelines: [String]?
    public var workouts: [String: WorkoutLocaleData]?
}

public final class ContentLocalizer {
    public static let shared = ContentLocalizer()

    private var exercisesCache: [String: [String: ExerciseLocaleData]] = [:]
    private var programsCache: [String: [String: ProgramLocaleData]] = [:]

    private init() {}

    private var activeLanguage: String {
        LanguageManager.shared.currentLanguage
    }

    private func loadFileData(filename: String, lang: String) -> Data? {
        let bundles = [Bundle.main, Bundle(for: ContentLocalizer.self)] + Bundle.allBundles
        let resourceName = "\(filename)"
        let subPath = "Locales/\(lang)"
        
        for b in bundles {
            if let url = b.url(forResource: resourceName, withExtension: "json", subdirectory: subPath) ??
                         b.url(forResource: resourceName, withExtension: "json", subdirectory: "Resources/\(subPath)") {
                if let data = try? Data(contentsOf: url) {
                    return data
                }
            }
            let direct = (b.bundlePath as NSString).appendingPathComponent("Locales/\(lang)/\(filename).json")
            if FileManager.default.fileExists(atPath: direct),
               let data = try? Data(contentsOf: URL(fileURLWithPath: direct)) {
                return data
            }
            let directRes = (b.bundlePath as NSString).appendingPathComponent("Resources/Locales/\(lang)/\(filename).json")
            if FileManager.default.fileExists(atPath: directRes),
               let data = try? Data(contentsOf: URL(fileURLWithPath: directRes)) {
                return data
            }
        }

        // Relative path fallbacks for test targets
        let possiblePaths = [
            "FormApp/Resources/Locales/\(lang)/\(filename).json",
            "../FormApp/Resources/Locales/\(lang)/\(filename).json",
            "../../FormApp/Resources/Locales/\(lang)/\(filename).json"
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                return data
            }
        }
        return nil
    }

    public func loadExercises(lang: String) -> [String: ExerciseLocaleData] {
        if let cached = exercisesCache[lang] { return cached }
        guard let data = loadFileData(filename: "exercises", lang: lang),
              let dict = try? JSONDecoder().decode([String: ExerciseLocaleData].self, from: data) else {
            return [:]
        }
        exercisesCache[lang] = dict
        return dict
    }

    public func loadPrograms(lang: String) -> [String: ProgramLocaleData] {
        if let cached = programsCache[lang] { return cached }
        guard let data = loadFileData(filename: "programs", lang: lang),
              let dict = try? JSONDecoder().decode([String: ProgramLocaleData].self, from: data) else {
            return [:]
        }
        programsCache[lang] = dict
        return dict
    }

    public func exerciseName(exerciseId: String?, fallback: String, lang: String? = nil) -> String {
        let currentLang = lang ?? activeLanguage
        guard let key = resolveExerciseKey(exerciseId: exerciseId, name: fallback) else { return fallback }
        if let name = loadExercises(lang: currentLang)[key]?.name, !name.isEmpty {
            return name
        }
        if currentLang != "en", let name = loadExercises(lang: "en")[key]?.name, !name.isEmpty {
            return name
        }
        return fallback
    }

    public func exerciseCues(exerciseId: String?, fallback: [String], lang: String? = nil) -> [String] {
        let currentLang = lang ?? activeLanguage
        guard let key = resolveExerciseKey(exerciseId: exerciseId, name: nil) else { return fallback }
        if let cues = loadExercises(lang: currentLang)[key]?.cues, !cues.isEmpty {
            return cues
        }
        if currentLang != "en", let cues = loadExercises(lang: "en")[key]?.cues, !cues.isEmpty {
            return cues
        }
        return fallback
    }

    public func exerciseAvoid(exerciseId: String?, fallback: [String], lang: String? = nil) -> [String] {
        let currentLang = lang ?? activeLanguage
        guard let key = resolveExerciseKey(exerciseId: exerciseId, name: nil) else { return fallback }
        if let avoid = loadExercises(lang: currentLang)[key]?.avoid, !avoid.isEmpty {
            return avoid
        }
        if currentLang != "en", let avoid = loadExercises(lang: "en")[key]?.avoid, !avoid.isEmpty {
            return avoid
        }
        return fallback
    }

    public func workoutTitle(programId: String?, workoutId: String?, fallback: String, lang: String? = nil) -> String {
        let currentLang = lang ?? activeLanguage
        if let pid = programId, let wid = workoutId {
            if let title = loadPrograms(lang: currentLang)[pid]?.workouts?[wid]?.title, !title.isEmpty {
                return title
            }
            if currentLang != "en", let title = loadPrograms(lang: "en")[pid]?.workouts?[wid]?.title, !title.isEmpty {
                return title
            }
        }
        return fallback
    }

    public func workoutFocus(programId: String?, workoutId: String?, fallback: String, lang: String? = nil) -> String {
        let currentLang = lang ?? activeLanguage
        if let pid = programId, let wid = workoutId {
            if let focus = loadPrograms(lang: currentLang)[pid]?.workouts?[wid]?.focus, !focus.isEmpty {
                return focus
            }
            if currentLang != "en", let focus = loadPrograms(lang: "en")[pid]?.workouts?[wid]?.focus, !focus.isEmpty {
                return focus
            }
        }
        return fallback
    }

    public func programName(programId: String?, fallback: String, lang: String? = nil) -> String {
        let currentLang = lang ?? activeLanguage
        if let pid = programId {
            if let name = loadPrograms(lang: currentLang)[pid]?.name, !name.isEmpty {
                return name
            }
            if currentLang != "en", let name = loadPrograms(lang: "en")[pid]?.name, !name.isEmpty {
                return name
            }
        }
        return fallback
    }

    public func programDescription(programId: String?, fallback: String, lang: String? = nil) -> String {
        let currentLang = lang ?? activeLanguage
        if let pid = programId {
            if let desc = loadPrograms(lang: currentLang)[pid]?.description, !desc.isEmpty {
                return desc
            }
            if currentLang != "en", let desc = loadPrograms(lang: "en")[pid]?.description, !desc.isEmpty {
                return desc
            }
        }
        return fallback
    }

    public func programGuidelines(programId: String?, fallback: [String], lang: String? = nil) -> [String] {
        let currentLang = lang ?? activeLanguage
        if let pid = programId {
            if let guidelines = loadPrograms(lang: currentLang)[pid]?.guidelines, !guidelines.isEmpty {
                return guidelines
            }
            if currentLang != "en", let guidelines = loadPrograms(lang: "en")[pid]?.guidelines, !guidelines.isEmpty {
                return guidelines
            }
        }
        return fallback
    }

    private func resolveExerciseKey(exerciseId: String?, name: String?) -> String? {
        if let exId = exerciseId, !exId.isEmpty {
            return exId
        }
        if let name = name, !name.isEmpty {
            let def = ExerciseCatalog.canonicalExercises.values.first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame ||
                $0.id.caseInsensitiveCompare(name) == .orderedSame
            }
            if let d = def { return d.id }
        }
        return nil
    }
}

// MARK: - Model Extensions

extension Exercise {
    public var displayName: String {
        ContentLocalizer.shared.exerciseName(exerciseId: exerciseId, fallback: name)
    }

    public var displayCues: String {
        let raw = cues.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let localized = ContentLocalizer.shared.exerciseCues(exerciseId: exerciseId, fallback: raw)
        return localized.isEmpty ? cues : localized.joined(separator: "\n")
    }

    public var displayAvoid: String {
        let raw = avoid.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let localized = ContentLocalizer.shared.exerciseAvoid(exerciseId: exerciseId, fallback: raw)
        return localized.isEmpty ? avoid : localized.joined(separator: "\n")
    }
}

extension ExerciseDefinition {
    public var displayName: String {
        ContentLocalizer.shared.exerciseName(exerciseId: id, fallback: name)
    }

    public var displayCues: [String] {
        ContentLocalizer.shared.exerciseCues(exerciseId: id, fallback: cues)
    }

    public var displayAvoid: [String] {
        ContentLocalizer.shared.exerciseAvoid(exerciseId: id, fallback: avoid)
    }
}

extension Workout {
    public func displayTitle(programId: String? = nil) -> String {
        ContentLocalizer.shared.workoutTitle(programId: programId, workoutId: id, fallback: title)
    }

    public func displayFocus(programId: String? = nil) -> String {
        ContentLocalizer.shared.workoutFocus(programId: programId, workoutId: id, fallback: focus)
    }
}

extension Program {
    public var displayName: String {
        ContentLocalizer.shared.programName(programId: id, fallback: name)
    }

    public var displayDescription: String {
        ContentLocalizer.shared.programDescription(programId: id, fallback: description)
    }

    public var displayGuidelines: [String] {
        ContentLocalizer.shared.programGuidelines(programId: id, fallback: guidelines)
    }
}
