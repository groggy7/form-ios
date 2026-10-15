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

    public static func defaultForLocale(_ locale: Locale = .current) -> WeightUnit {
        let region = locale.region?.identifier.uppercased() ?? (locale as NSLocale).countryCode?.uppercased() ?? ""
        if region == "US" || region == "USA" {
            return .lbs
        }
        return .kg
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
                formatted = "\(Int(rounded))"
            } else {
                let oneDec = Self.roundHalfAwayFromZero(display, decimals: 1)
                if oneDec.truncatingRemainder(dividingBy: 1.0) == 0 {
                    formatted = "\(Int(oneDec))"
                } else {
                    formatted = String(format: "%.1f", oneDec)
                }
            }
        case .kg:
            let rounded = Self.roundHalfAwayFromZero(display, decimals: 0)
            if abs(display - rounded) < 0.001 {
                formatted = "\(Int(rounded))"
            } else {
                let oneDec = Self.roundHalfAwayFromZero(display, decimals: 1)
                if oneDec.truncatingRemainder(dividingBy: 1.0) == 0 {
                    formatted = "\(Int(oneDec))"
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

    public func formatExactDisplayWeight(_ weightKg: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LanguageManager.numberLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        let exact = formatExactWeight(weightKg)
        return formatter.string(from: NSNumber(value: Double(exact) ?? 0)) ?? exact
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
        let rounded = Int(display.rounded())
        let formatter = NumberFormatter()
        formatter.locale = LanguageManager.numberLocale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }

    public var defaultStepperStep: Double {
        switch self {
        case .kg: return 2.5
        case .lbs: return 5.0
        }
    }
}
