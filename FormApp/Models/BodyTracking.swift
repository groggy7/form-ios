import Foundation

// Joint-stress ratings and the body log (docs/design/body-and-joint-journal.md).

/// The user's own joint-stress report for one exercise in one session. Raw values are shared with Android and backups.
public enum JointStress: String, CaseIterable, Codable {
    /// Named `noStress` so it never reads as `Optional.none`.
    case noStress = "none"
    case mild, high

    public var labelKey: String { "joint.\(rawValue)" }
}

/// Local calendar days as `yyyy-MM-dd`, compared by day number so time zones and DST never shift a gap.
public enum BodyDay {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    public static func number(_ date: String?) -> Int? {
        guard let date, date.count == 10, let parsed = formatter.date(from: date) else { return nil }
        return Int((parsed.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    public static func string(_ number: Int) -> String {
        formatter.string(from: Date(timeIntervalSince1970: Double(number) * 86_400))
    }

    public static func today(_ now: Date = Date(), timeZone: TimeZone = .current) -> String {
        WorkoutCalendar.formatDate(now, timeZone: timeZone)
    }
}

/// One day's body log in canonical kilograms and centimetres. At least one value is set.
public struct BodyEntry: Codable, Hashable, Identifiable {
    public var date: String
    public var bodyweightKg: Double?
    public var waistCm: Double?
    public var chestCm: Double?
    public var armCm: Double?
    public var thighCm: Double?

    public var id: String { date }

    public init(date: String, bodyweightKg: Double? = nil, waistCm: Double? = nil, chestCm: Double? = nil, armCm: Double? = nil, thighCm: Double? = nil) {
        self.date = date
        self.bodyweightKg = bodyweightKg
        self.waistCm = waistCm
        self.chestCm = chestCm
        self.armCm = armCm
        self.thighCm = thighCm
    }

    public func value(_ metric: BodyMetric) -> Double? {
        switch metric {
        case .bodyweight: return bodyweightKg
        case .waist: return waistCm
        case .chest: return chestCm
        case .arm: return armCm
        case .thigh: return thighCm
        }
    }

    public func with(_ metric: BodyMetric, _ value: Double?) -> BodyEntry {
        var copy = self
        switch metric {
        case .bodyweight: copy.bodyweightKg = value
        case .waist: copy.waistCm = value
        case .chest: copy.chestCm = value
        case .arm: copy.armCm = value
        case .thigh: copy.thighCm = value
        }
        return copy
    }

    public var hasValue: Bool { BodyMetric.allCases.contains { value($0) != nil } }
}

public enum BodyMetric: String, CaseIterable {
    case bodyweight, waist, chest, arm, thigh

    public var labelKey: String { "body.\(rawValue)" }
    public var isLength: Bool { self != .bodyweight }
    /// Valid canonical values: kilograms for bodyweight, centimetres for measurements.
    public var canonicalRange: ClosedRange<Double> { isLength ? 10...300 : 20...400 }
    public static let measurements: [BodyMetric] = [.waist, .chest, .arm, .thigh]
}

/// Display units follow the weight unit: kg with cm, lb with in.
public enum BodyUnits {
    public static let cmPerInch = 2.54

    public static func lengthLabelKey(_ unit: WeightUnit) -> String { unit == .lbs ? "body.unit.in" : "body.unit.cm" }

    public static func toDisplay(_ metric: BodyMetric, _ canonical: Double, unit: WeightUnit) -> Double {
        if !metric.isLength { return unit.toDisplay(canonical) }
        return unit == .lbs ? canonical / cmPerInch : canonical
    }

    public static func toCanonical(_ metric: BodyMetric, _ display: Double, unit: WeightUnit) -> Double {
        if !metric.isLength { return unit.toCanonicalKg(display) }
        return unit == .lbs ? display * cmPerInch : display
    }

    /// One decimal place, without a trailing ".0", in the app language's number format (80,5 in German).
    public static func format(_ display: Double, locale: Locale = LanguageManager.numberLocale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 1
        let rounded = WeightUnit.roundHalfAwayFromZero(display, decimals: 1)
        return formatter.string(from: NSNumber(value: rounded)) ?? String(rounded)
    }

    public static func formatCanonical(_ metric: BodyMetric, _ canonical: Double, unit: WeightUnit) -> String {
        format(toDisplay(metric, canonical, unit: unit))
    }

    /// Accepts a comma or a point and at most one decimal place; blank or malformed text is nil.
    public static func parse(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard text.range(of: #"^\d{1,4}(\.\d)?$"#, options: .regularExpression) != nil else { return nil }
        return Double(text)
    }

    /// The display range for validation messages, rounded inward so every shown value is valid.
    public static func displayRange(_ metric: BodyMetric, unit: WeightUnit) -> (String, String) {
        let range = metric.canonicalRange
        let low = (toDisplay(metric, range.lowerBound, unit: unit) * 10).rounded(.up) / 10
        let high = (toDisplay(metric, range.upperBound, unit: unit) * 10).rounded(.down) / 10
        return (format(low), format(high))
    }
}

public enum BodyLog {
    public static let maxEntries = 10_000

    /// Restore rules: a valid date no more than one day ahead, in-range values only (a bad value is dropped,
    /// the rest kept), one entry per date (the last wins), at most `maxEntries`, sorted by date.
    public static func sanitize(_ entries: [BodyEntry]?, today: String) -> [BodyEntry] {
        guard let todayNumber = BodyDay.number(today) else { return [] }
        var byDate: [String: BodyEntry] = [:]
        for entry in entries ?? [] {
            guard let day = BodyDay.number(entry.date), day <= todayNumber + 1 else { continue }
            var clean = BodyEntry(date: BodyDay.string(day))
            for metric in BodyMetric.allCases {
                if let value = entry.value(metric), value.isFinite, metric.canonicalRange.contains(value) {
                    clean = clean.with(metric, value)
                }
            }
            if clean.hasValue { byDate[clean.date] = clean }
        }
        return Array(byDate.values.sorted { $0.date < $1.date }.suffix(maxEntries))
    }

    /// Adds or replaces the entry for its date.
    public static func upsert(_ entries: [BodyEntry], _ entry: BodyEntry) -> [BodyEntry] {
        Array((entries.filter { $0.date != entry.date } + [entry]).sorted { $0.date < $1.date }.suffix(maxEntries))
    }

    public static func remove(_ entries: [BodyEntry], date: String) -> [BodyEntry] {
        entries.filter { $0.date != date }
    }
}

// MARK: Health weigh-ins (docs/design/body-and-joint-journal.md#health-weigh-ins)

/// One bodyweight sample read from Apple Health: its local date, instant and kilograms.
public struct HealthWeighIn: Hashable {
    public var date: String
    public var time: Date
    public var kg: Double

    public init(date: String, time: Date, kg: Double) {
        self.date = date
        self.time = time
        self.kg = kg
    }
}

public enum HealthWeighIns {
    /// The last 365 days, counting today.
    public static let windowDays = 365

    /// Each local day's earliest valid weigh-in in the window ending today. Out-of-range and future weigh-ins are skipped.
    public static func daily(_ samples: [HealthWeighIn], today: String) -> [String: Double] {
        guard let todayNumber = BodyDay.number(today) else { return [:] }
        var earliest: [String: HealthWeighIn] = [:]
        for sample in samples where sample.kg.isFinite && BodyMetric.bodyweight.canonicalRange.contains(sample.kg) {
            guard let day = BodyDay.number(sample.date), day <= todayNumber, day > todayNumber - windowDays else { continue }
            if let current = earliest[sample.date], current.time <= sample.time { continue }
            earliest[sample.date] = sample
        }
        return earliest.mapValues(\.kg)
    }
}

/// The body log as shown: typed entries joined with the Health weigh-ins that are not hidden.
public struct ShownBodyLog: Equatable {
    public var entries: [BodyEntry]
    /// Dates whose shown bodyweight is a Health weigh-in.
    public var healthDates: Set<String>
    /// Health weigh-ins by date, without hidden dates, including dates where a typed weight wins.
    public var health: [String: Double]

    public static let empty = ShownBodyLog(entries: [], healthDates: [], health: [:])
}

/// What the Log card's Save does with its fields.
public enum BodyFormOutcome: Equatable {
    case invalid(BodyMetric)
    case empty
    /// `stored` replaces the date's typed entry (nil removes it); `hideHealth` hides the date's Health weigh-in.
    case save(stored: BodyEntry?, hideHealth: Bool)
}

extension BodyLog {
    public static let maxHiddenDates = 10_000

    /// A typed bodyweight wins; otherwise the date shows its Health weigh-in unless hidden. Measurements are only typed.
    public static func merge(_ stored: [BodyEntry], health: [String: Double], hidden: Set<String>) -> ShownBodyLog {
        let visible = health.filter { !hidden.contains($0.key) }
        var byDate = Dictionary(stored.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        var healthDates = Set<String>()
        for (date, kg) in visible where byDate[date]?.bodyweightKg == nil {
            byDate[date] = (byDate[date] ?? BodyEntry(date: date)).with(.bodyweight, kg)
            healthDates.insert(date)
        }
        return ShownBodyLog(entries: byDate.values.sorted { $0.date < $1.date }, healthDates: healthDates, health: visible)
    }

    /// Resolves the Log card for `date`. An untouched field keeps its stored value, and an untouched Health weight stays
    /// Health's (shown, never stored). A blank weight on a date with a Health weigh-in hides it.
    public static func resolveForm(date: String, inputs: [BodyMetric: String], stored: BodyEntry?, healthKg: Double?,
                                   unit: WeightUnit) -> BodyFormOutcome {
        var entry = BodyEntry(date: date)
        var keepsHealthWeight = false
        for metric in BodyMetric.allCases {
            let text = (inputs[metric] ?? "").trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if let original = stored?.value(metric), text == BodyUnits.formatCanonical(metric, original, unit: unit) {
                entry = entry.with(metric, original)
                continue
            }
            if metric == .bodyweight, stored?.bodyweightKg == nil, let healthKg,
               text == BodyUnits.formatCanonical(metric, healthKg, unit: unit) {
                keepsHealthWeight = true
                continue
            }
            guard let canonical = BodyUnits.parse(text).map({ BodyUnits.toCanonical(metric, $0, unit: unit) }),
                  metric.canonicalRange.contains(canonical) else { return .invalid(metric) }
            entry = entry.with(metric, canonical)
        }
        let hideHealth = healthKg != nil && (inputs[.bodyweight] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        if !entry.hasValue && !keepsHealthWeight && !hideHealth { return .empty }
        return .save(stored: entry.hasValue ? entry : nil, hideHealth: hideHealth)
    }

    /// Replaces or removes the date's typed entry and, when asked, hides its Health weigh-in.
    public static func applyEdit(_ entries: [BodyEntry], hidden: [String], date: String, stored: BodyEntry?,
                                 hideHealth: Bool) -> (entries: [BodyEntry], hidden: [String]) {
        let nextEntries = stored.map { upsert(entries, $0) } ?? remove(entries, date: date)
        let nextHidden = hideHealth && !hidden.contains(date)
            ? Array((hidden + [date]).sorted().suffix(maxHiddenDates)) : hidden
        return (nextEntries, nextHidden)
    }

    /// Restore rules for hidden dates: valid, no more than one day ahead, unique, sorted, at most `maxHiddenDates`.
    public static func sanitizeHidden(_ dates: [String]?, today: String) -> [String] {
        guard let todayNumber = BodyDay.number(today) else { return [] }
        let valid = Set((dates ?? []).compactMap { date -> String? in
            guard let day = BodyDay.number(date), day <= todayNumber + 1 else { return nil }
            return BodyDay.string(day)
        })
        return Array(valid.sorted().suffix(maxHiddenDates))
    }
}
