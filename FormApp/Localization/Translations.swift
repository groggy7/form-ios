import Foundation
import Combine

public final class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()
    public static let system = "system"
    public static var supportedLanguages: [(code: String, name: String)] { Translations.languages }
    private static let userDefaultsKey = "app_language"
    private let languageLock = NSLock()
    private var workerLanguage = "en"
    @Published public private(set) var currentLanguage: String {
        didSet {
            languageLock.lock(); workerLanguage = currentLanguage; languageLock.unlock()
        }
    }
    // Workers use this snapshot instead of reading a UI-owned Published value.
    var translationLanguage: String {
        languageLock.lock(); defer { languageLock.unlock() }
        return workerLanguage
    }
    @Published public var languagePreference: String {
        didSet {
            let preference = Self.normalizePreference(languagePreference)
            if preference != languagePreference { languagePreference = preference; return }
            UserDefaults.standard.set(preference, forKey: Self.userDefaultsKey)
            currentLanguage = preference == Self.system ? Self.resolveLanguage(Locale.preferredLanguages) : preference
        }
    }
    // All supported bundles are fixed for this app build; reads never mutate a cache.
    private let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: Translations.languages.map { language in
        (language.code, Bundle.main.path(forResource: language.code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main)
    })

    init() {
        let saved = Self.normalizePreference(UserDefaults.standard.string(forKey: Self.userDefaultsKey))
        languagePreference = saved
        currentLanguage = saved == Self.system ? Self.resolveLanguage(Locale.preferredLanguages) : saved
        workerLanguage = currentLanguage
    }

    public static func normalizePreference(_ tag: String?) -> String {
        guard let tag, tag != system else { return system }
        return resolveLanguage([tag])
    }
    public static func resolveLanguage(_ tags: [String]) -> String {
        for tag in tags {
            let base = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if supportedLanguages.contains(where: { $0.code == base }) { return base }
        }
        return "en"
    }
    public static var locale: Locale {
        let region = Locale.current.region?.identifier ?? "US"
        return Locale(identifier: "\(shared.translationLanguage)_\(region)")
    }
    public static var numberLocale: Locale { Locale(identifier: shared.translationLanguage) }
    public func refreshDeviceLanguage() {
        if languagePreference == Self.system { currentLanguage = Self.resolveLanguage(Locale.preferredLanguages) }
    }
    public static func setLanguage(_ lang: String) { shared.languagePreference = normalizePreference(lang) }
    public static func flagImageName(for code: String) -> String {
        switch code {
        case "en", "tr", "de", "fr", "es": return "ic_flag_\(code)"
        default: return "ic_flag_en"
        }
    }
    public static var workoutDays: [String] {
        let formatter = DateFormatter(); formatter.locale = locale
        let names = formatter.weekdaySymbols!
        return [1,2,3,4,5,6,0].map { names[$0] }
    }
    public static var dayLabels: [String] {
        if shared.translationLanguage == "tr" { return ["PZT","SAL","ÇAR","PER","CUM","CTS","PAZ"] }
        let formatter = DateFormatter(); formatter.locale = locale
        let names = formatter.shortWeekdaySymbols!
        return [1,2,3,4,5,6,0].map { names[$0].trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased(with: locale) }
    }
    public static func t(_ key: String, _ params: [String: Any] = [:]) -> String { shared.translate(key, params: params) }
    public static func content(_ text: String) -> String { ContentDictionary.localize(text, lang: shared.translationLanguage) }
    public static func restMotivationQuote(for index: Int) -> String { t("today.restMotivation.\(index.magnitude % 7)") }

    public static func turkishPossessiveNumber(_ n: Int) -> String {
        if n == 0 { return "0'ı" }
        let lastTwo = n % 100
        let lastOne = n % 10
        if lastTwo >= 10 && lastTwo <= 19 {
            let suffixes: [Int: String] = [
                0: "'u", 1: "'i", 2: "'si", 3: "'ü", 4: "'ü",
                5: "'i", 6: "'sı", 7: "'si", 8: "'i", 9: "'u"
            ]
            return "\(n)\(suffixes[lastOne] ?? "'i")"
        }
        if lastOne == 0 {
            let tens: [Int: String] = [
                20: "'si", 30: "'u", 40: "'ı", 50: "'si",
                60: "'ı", 70: "'i", 80: "'i", 90: "'ı"
            ]
            return "\(n)\(tens[lastTwo] ?? "'ü")"
        }
        let ones: [Int: String] = [
            1: "'i", 2: "'si", 3: "'ü", 4: "'ü",
            5: "'i", 6: "'sı", 7: "'si", 8: "'i", 9: "'u"
        ]
        return "\(n)\(ones[lastOne] ?? "'i")"
    }

    public static func formatSetsProgress(done: Int, total: Int) -> String { t("history.setsProgress", ["done":done,"total":total]) }
    public static func formatPercent(_ percent: Int) -> String {
        let formatter = NumberFormatter(); formatter.locale = numberLocale; formatter.numberStyle = .percent
        return formatter.string(from: NSNumber(value: Double(percent)/100)) ?? "\(percent)%"
    }
    public static func formatSetsLeft(_ count: Int) -> String { shared.plural("counts.setsLeft", count) }
    public static func formatOtherExercises(_ count: Int) -> String { shared.plural("counts.otherExercises", count) }
    public static func formatUncompletedExercisesCount(_ count: Int) -> String { shared.plural("counts.uncompletedExercises", count) }
    public static func formatCompletedExercisesCount(_ count: Int) -> String { shared.plural("counts.completedExercises", count) }
    public static func formatAllExercisesCount(_ count: Int) -> String { formatUncompletedExercisesCount(count) }
    public static func formatSetsFraction(completed: Int, total: Int) -> String { shared.plural("counts.setsFraction", total, ["done":completed]) }
    public static func formatExerciseSetsCompleted(completed: Int, planned: Int) -> String { shared.plural("counts.setsCompleted", planned, ["done":completed]) }

    private func languageBundle(_ lang: String) -> Bundle {
        bundles[lang] ?? Bundle.main
    }
    public func plural(_ key: String, _ count: Int, _ params: [String: Any] = [:], language: String? = nil) -> String {
        let effective = language ?? translationLanguage
        let native = languageBundle(effective).localizedString(forKey: key, value: nil, table: nil)
        var values = params; values[Translations.quantityParameters[key] ?? "count"] = count
        if native != key {
            let raw = String(format: native, locale: Locale(identifier:effective), arguments: [Int64(count)])
            return interpolate(key, raw, values, language:effective)
        }
        let quantity = count == 1 || (effective == "fr" && count == 0) ? "one" : "other"
        return translate("\(key).\(quantity)", params: values, language:effective)
    }
    public func translate(_ key: String, params: [String: Any] = [:], language: String? = nil) -> String {
        let effective = language.map { Self.resolveLanguage([$0]) } ?? translationLanguage
        if key == "programs.counts", let w = params["workouts"], let e = params["exercises"],
           let workouts = Int("\(w)"), let exercises = Int("\(e)") {
            return translate("programs.countParts", params:[
                "workouts":plural("programs.workoutQuantity",workouts,language:effective),
                "exercises":plural("programs.exerciseQuantity",exercises,language:effective)],language:effective)
        }
        if let parameter = Translations.quantityParameters[key], let value = params[parameter], let count = Int("\(value)") {
            return plural(key, count, params, language:effective)
        }
        let fallback = Translations.forLanguage(effective)[key] ?? Translations.en[key] ?? key
        let raw = Translations.quantityParameters[key] == nil ? languageBundle(effective).localizedString(forKey: key, value: fallback, table: nil) : fallback
        return interpolate(key, raw, params, language:effective)
    }
    private static let placeholderRegex = try! NSRegularExpression(pattern: "\\{(\\w+)\\}")

    private func interpolate(_ key: String, _ raw: String, _ params: [String: Any], language: String? = nil) -> String {
        // Replace only source placeholders; never interpret braces inside user-provided values.
        let regex = Self.placeholderRegex
        var result = raw
        for match in regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).reversed() {
            guard let keyRange = Range(match.range(at:1), in: raw), let range = Range(match.range, in: result) else { continue }
            let name = String(raw[keyRange]); guard let value = params[name] else { continue }
            let text: String
            if (language ?? translationLanguage) == "tr", key == "history.setsProgress", name == "done", let count = value as? Int {
                text = Self.turkishPossessiveNumber(count)
            } else {
                text = "\(value)"
            }
            result.replaceSubrange(range, with: text)
        }
        return result
    }
}

public enum ContentDictionary {
    private static let mapLock = NSLock()
    private static var canonicalMaps: [String: [String: String]] = [:]

    public static var canonicalMap: [String: String] { canonicalMap(for: LanguageManager.shared.translationLanguage) }
    private static func canonicalMap(for lang: String) -> [String: String] {
        mapLock.lock(); defer { mapLock.unlock() }
        if let cached = canonicalMaps[lang] { return cached }
        var map: [String: String] = [:]
        let enDict = ContentLocalizer.shared.loadExercises(lang: "en")
        let trDict = ContentLocalizer.shared.loadExercises(lang: lang)
        for (id, trDef) in trDict {
            guard let enDef = enDict[id] else { continue }
            for (en, tr) in zip(enDef.cues ?? [], trDef.cues ?? []) {
                let e = en.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let t = tr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !e.isEmpty && !t.isEmpty {
                    map[e] = t
                }
            }
            for (en, tr) in zip(enDef.avoid ?? [], trDef.avoid ?? []) {
                let e = en.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let t = tr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !e.isEmpty && !t.isEmpty {
                    map[e] = t
                }
            }
            let cuesEn = (enDef.cues ?? []).joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let cuesTr = (trDef.cues ?? []).joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !cuesEn.isEmpty && !cuesTr.isEmpty {
                map[cuesEn] = cuesTr
            }
            let avoidEn = (enDef.avoid ?? []).joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let avoidTr = (trDef.avoid ?? []).joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !avoidEn.isEmpty && !avoidTr.isEmpty {
                map[avoidEn] = avoidTr
            }
        }
        canonicalMaps[lang] = map
        return map
    }

    public static func localize(_ text: String?, lang: String) -> String {
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        if lang == "en" {
            return text
        }
        let canonicalMap = canonicalMap(for: lang)
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let direct = canonicalMap[trimmed] {
            return direct
        }
        if trimmed.hasPrefix("- ") {
            let clean = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if let tr = canonicalMap[clean] {
                return "- \(tr)"
            }
        }
        if text.contains("\n") {
            let lines = text.components(separatedBy: .newlines)
            let translated = lines.map { line -> String in
                let lTrim = line.trimmingCharacters(in: .whitespaces)
                if lTrim.isEmpty { return "" }
                let isDash = lTrim.hasPrefix("- ")
                let clean = isDash ? String(lTrim.dropFirst(2)).trimmingCharacters(in: .whitespaces) : lTrim
                let tr = canonicalMap[clean] ?? clean
                return isDash ? "- \(tr)" : tr
            }
            return translated.joined(separator: "\n")
        }
        return text
    }
}
