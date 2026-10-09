// Generated API compatibility facade. Edit data/localization instead.
public enum Translations {
    public static let languages: [(code: String, name: String)] = [("en", "English"), ("tr", "Türkçe"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español")]
    public static let en: [String: String] = ContentLocalizer.shared.loadUI(lang: "en")
    public static let tr: [String: String] = ContentLocalizer.shared.loadUI(lang: "tr")
    public static let de: [String: String] = ContentLocalizer.shared.loadUI(lang: "de")
    public static let fr: [String: String] = ContentLocalizer.shared.loadUI(lang: "fr")
    public static let es: [String: String] = ContentLocalizer.shared.loadUI(lang: "es")

    public static let quantityParameters: [String: String] = ["history.multipleWorkouts": "count", "history.setsProgress": "total", "history.setsDoneCount": "count", "history.setsRemainingCount": "count", "history.setsFraction": "total", "history.moreExercisesInBreakdown": "count", "warmup.active_desc": "count", "warmup.insert_sets_cta": "count", "form_lab.sessions_tracked": "count", "library.resultCount": "count", "exercise.history.viewAll": "count", "exercise.history.setsCount": "count", "weekly.exerciseCount": "count", "builder.dayCount": "count", "builder.exerciseCount": "count", "builder.incompleteDays": "count", "summary.setsDone": "count", "onboarding.schedule.subtitle": "count", "onboarding.schedule.daysSelected": "total", "counts.setsLeft": "count", "counts.otherExercises": "count", "counts.uncompletedExercises": "count", "counts.completedExercises": "count", "counts.setsFraction": "count", "counts.setsCompleted": "count", "matrix.unmapped": "count", "form_lab.balance.unclassified": "count", "today.workoutMeta": "exercises", "table.allSetsDone": "total", "programs.workoutQuantity": "count", "programs.exerciseQuantity": "count"]

    public static func forLanguage(_ lang: String) -> [String: String] {
        switch lang {
        case "en": return en
        case "tr": return tr
        case "de": return de
        case "fr": return fr
        case "es": return es
        default: return en
        }
    }
}
