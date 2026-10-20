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
