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

    public func formatWeight(_ weightKg: Double) -> String {
        guard weightKg > 0.0 else { return "0" }
        let display = toDisplay(weightKg)
        switch self {
        case .lbs:
            let rounded = display.rounded()
            if abs(display - rounded) < 0.05 || display >= 10.0 {
                return "\(Int(rounded))"
            } else {
                let oneDec = (display * 10.0).rounded() / 10.0
                if oneDec.truncatingRemainder(dividingBy: 1.0) == 0 {
                    return "\(Int(oneDec))"
                } else {
                    return String(format: "%.1f", oneDec)
                }
            }
        case .kg:
            let rounded = display.rounded()
            if abs(display - rounded) < 0.001 {
                return "\(Int(rounded))"
            } else {
                let oneDec = (display * 10.0).rounded() / 10.0
                if oneDec.truncatingRemainder(dividingBy: 1.0) == 0 {
                    return "\(Int(oneDec))"
                } else {
                    return String(format: "%.1f", oneDec)
                }
            }
        }
    }

    public func formatWeightWithUnit(_ weightKg: Double) -> String {
        return "\(formatWeight(weightKg)) \(label)"
    }

    public func formatVolume(_ volumeKg: Double) -> String {
        let display = toDisplay(volumeKg)
        let rounded = Int(display.rounded())
        let formatter = NumberFormatter()
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
