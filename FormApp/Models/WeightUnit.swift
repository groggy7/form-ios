import Foundation

public enum WeightUnit: String, Codable, CaseIterable {
    case kg = "kg"
    case lbs = "lbs"

    public static let kgToLbs = 2.20462262185
    public static let lbsToKg = 0.45359237

    public var label: String {
        switch self {
        case .kg: return "kg"
        case .lbs: return "lbs"
        }
    }

    public var uppercaseLabel: String {
        switch self {
        case .kg: return "KG"
        case .lbs: return "LBS"
        }
    }

    public static func fromCode(_ code: String?) -> WeightUnit {
        guard let clean = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return .kg
        }
        if clean == "lbs" || clean == "lb" || clean == "pound" || clean == "pounds" {
            return .lbs
        }
        return .kg
    }

    // Gym-load defaults, not bodyweight/stone or road-distance conventions.
    // Keep in sync with Android and docs/weight-units-and-backups.md.
    private static let poundRegions: Set<String> = [
        "AG", "AI", "AS", "BB", "BM", "BS", "BZ", "CA", "DM", "GD",
        "GU", "GY", "JM", "KN", "KY", "LC", "LR", "MM", "MP", "MS",
        "PR", "TC", "TT", "UM", "US", "VC", "VG", "VI"
    ]

    public static func defaultForLocale(_ locale: Locale = .current) -> WeightUnit {
        let components = Locale.Components(locale: locale)
        if let system = components.measurementSystem {
            if system == .us { return .lbs }
            if system == .metric || system == .uk { return .kg }
        }
        // Locale.current can carry a Settings override outside its identifier.
        if locale.measurementSystem != Locale(identifier: locale.identifier).measurementSystem {
            return locale.measurementSystem == .us ? .lbs : .kg
        }
        let region = (components.region ?? components.languageComponents.region)?.identifier.uppercased() ?? ""
        return poundRegions.contains(region) || region == "USA" ? .lbs : .kg
    }

    public func toDisplay(_ weightKg: Double) -> Double {
        switch self {
        case .kg: return weightKg
        case .lbs: return weightKg * Self.kgToLbs
        }
    }

    public func toCanonicalKg(_ displayWeight: Double) -> Double {
        switch self {
        case .kg: return displayWeight
        case .lbs: return displayWeight * Self.lbsToKg
        }
    }

    public static func toCanonicalKg(_ displayWeight: Double, unit: WeightUnit) -> Double {
        return unit.toCanonicalKg(displayWeight)
    }

    /// The rounding rule both apps share: halves round away from zero (20.25 -> 20.3).
    /// Keep the arithmetic identical to Android WeightUnit.roundHalfAwayFromZero.
    public static func roundHalfAwayFromZero(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10.0, Double(decimals))
        let scaled = abs(value) * factor
        let whole = scaled.rounded(.down)
        let rounded = scaled - whole >= 0.5 ? whole + 1.0 : whole
        return (value < 0 ? -rounded : rounded) / factor
    }

    /// Whole display units for labels. `Int(_:)` traps outside Int's range, and restored or corrupt
    /// values must still render, so non-finite values show 0 and the rest saturate.
    public static func displayInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value, -maxDisplayMagnitude), maxDisplayMagnitude))
    }

    private static let maxDisplayMagnitude = 1e15

    public func formatWeight(_ weightKg: Double) -> String {
        guard weightKg != 0.0 else { return "0" }
        let isNegative = weightKg < 0.0
        let absWeight = abs(weightKg)
        let display = toDisplay(absWeight)
        let formatted: String
        switch self {
        case .lbs:
            let rounded = Self.roundHalfAwayFromZero(display, decimals: 0)
            if abs(display - rounded) < 0.05 || display >= 10.0 {
                formatted = "\(Self.displayInt(rounded))"
            } else {
                let oneDec = Self.roundHalfAwayFromZero(display, decimals: 1)
                if oneDec.truncatingRemainder(dividingBy: 1.0) == 0 {
                    formatted = "\(Self.displayInt(oneDec))"
                } else {
                    formatted = String(format: "%.1f", oneDec)
                }
            }
        case .kg:
            let rounded = Self.roundHalfAwayFromZero(display, decimals: 0)
            if abs(display - rounded) < 0.001 {
                formatted = "\(Self.displayInt(rounded))"
            } else {
                let oneDec = Self.roundHalfAwayFromZero(display, decimals: 1)
                if oneDec.truncatingRemainder(dividingBy: 1.0) == 0 {
                    formatted = "\(Self.displayInt(oneDec))"
                } else {
                    formatted = String(format: "%.1f", oneDec)
                }
            }
        }
        return isNegative ? "-\(formatted)" : formatted
    }

    /// Lossless input text at the logger's two-decimal precision ("102.5", "220.46").
    /// Progression targets use it so the card shows exactly what Apply Target writes.
    public func formatExactWeight(_ weightKg: Double) -> String {
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Self.roundHalfAwayFromZero(toDisplay(weightKg), decimals: 2))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// Plate-friendly step for loads converted from the other unit: a pair of the smallest common plates.
    public var conversionStep: Double { self == .lbs ? 5.0 : 2.5 }

    /// A load logged in this unit reads back on the logger's two-decimal grid; one converted from the
    /// other unit does not (100 kg is 220.462… lbs). Keep the tolerance identical to Android.
    public func isNativeLoad(_ weightKg: Double) -> Bool {
        let display = toDisplay(weightKg)
        return display.isFinite && abs(display - Self.roundHalfAwayFromZero(display, decimals: 2)) < 1e-6
    }

    /// The canonical load a set or target receives in this unit. Loads logged in this unit stay exact.
    /// A converted barbell load takes the easiest standard plate setup within 2.5% (100 kg becomes 225 lbs);
    /// other converted loads round to the nearest `conversionStep` (a 22.5 kg dumbbell becomes 50 lbs).
    /// A positive load too small for the step keeps one decimal rather than becoming zero.
    public func loadableKg(_ weightKg: Double, barbell: Bool = false) -> Double {
        guard weightKg.isFinite, weightKg > 0, !isNativeLoad(weightKg) else { return weightKg }
        let display = toDisplay(weightKg)
        let stepped = (barbell ? easiestBarbellLoad(near: display) : nil)
            ?? Self.roundHalfAwayFromZero(display / conversionStep, decimals: 0) * conversionStep
        let loadable = stepped > 0 ? stepped : Self.roundHalfAwayFromZero(display, decimals: 1)
        return loadable > 0 ? toCanonicalKg(loadable) : weightKg
    }

    /// Input text for `loadableKg`: "102.5" stays "102.5" in lbs, while a 100 kg barbell load reads "225".
    public func formatLoadableWeight(_ weightKg: Double, barbell: Bool = false) -> String {
        formatExactWeight(loadableKg(weightKg, barbell: barbell))
    }

    /// The standard bar and per-side plates an easy barbell setup is built from. Gyms treat a 20 kg plate
    /// as a 45 lb plate, so 60/100/140/180 kg and 135/225/315/405 lbs convert to each other.
    private var standardBar: Double { self == .lbs ? 45 : 20 }
    private var standardPlates: [Double] { self == .lbs ? [45, 35, 25, 10, 5, 2.5] : [25, 20, 15, 10, 5, 2.5, 1.25] }

    /// Within 2.5% of `display`, the load needing the fewest standard plates per side; ties go to the
    /// closer, then the lighter, load. Keep the arithmetic identical to Android.
    private func easiestBarbellLoad(near display: Double) -> Double? {
        let first = Int((display * 0.975 / conversionStep).rounded(.up))
        let last = Int((display * 1.025 / conversionStep).rounded(.down))
        guard first <= last else { return nil }
        var best: (Int, Double, Double)?
        for multiple in first...last {
            let load = Double(multiple) * conversionStep
            guard let plates = platesPerSide(load) else { continue }
            let candidate = (plates, abs(load - display), load)
            if best.map({ candidate < $0 }) ?? true { best = candidate }
        }
        return best?.2
    }

    /// The fewest standard plates per side that build `load` on the standard bar, or nil below the bar.
    private func platesPerSide(_ load: Double) -> Int? {
        let smallest = standardPlates.last!
        let units = Int(((load - standardBar) / 2 / smallest).rounded())
        guard units >= 0 else { return nil }
        let sizes = standardPlates.map { Int(($0 / smallest).rounded()) }
        var fewest = [0] + Array(repeating: Int.max, count: units)
        for total in stride(from: 1, through: units, by: 1) {
            fewest[total] = sizes.filter { $0 <= total }.map { fewest[total - $0] }.min()! + 1
        }
        return fewest[units]
    }

    /// Localized `formatLoadableWeight` for the coach card, which shows what Apply writes.
    public func formatLoadableDisplayWeight(_ weightKg: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LanguageManager.numberLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        let text = formatLoadableWeight(weightKg)
        return formatter.string(from: NSNumber(value: Double(text) ?? 0)) ?? text
    }

    public func formatWeightWithUnit(_ weightKg: Double) -> String {
        return "\(formatDisplayWeight(weightKg)) \(label)"
    }

    // Keep formatWeight stable for input drafts, and localize only presentation.
    public func formatDisplayWeight(_ weightKg: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LanguageManager.numberLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: Double(formatWeight(weightKg)) ?? 0)) ?? formatWeight(weightKg)
    }

    public func formatVolume(_ volumeKg: Double) -> String {
        let display = toDisplay(volumeKg)
        let rounded = Self.displayInt(display.rounded())
        let formatter = NumberFormatter()
        formatter.locale = LanguageManager.numberLocale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }
}
