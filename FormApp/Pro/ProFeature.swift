import SwiftUI

public enum ProFeature: String, CaseIterable, Identifiable {
    case volumeMatrix = "volume_matrix"
    case autoProgression = "auto_progression"
    case warmupCalculator = "warmup_calculator"
    case formLab = "form_lab"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .volumeMatrix: return "pro.volume_matrix.title"
        case .autoProgression: return "pro.auto_progression.title"
        case .warmupCalculator: return "pro.warmup_calculator.title"
        case .formLab: return "pro.form_lab.title"
        }
    }

    public var descriptionKey: String {
        switch self {
        case .volumeMatrix: return "pro.volume_matrix.description"
        case .autoProgression: return "pro.auto_progression.description"
        case .warmupCalculator: return "pro.warmup_calculator.description"
        case .formLab: return "pro.form_lab.description"
        }
    }
}

public class ProAccessManager: ObservableObject {
    public static let shared = ProAccessManager()

    @Published public var isProSubscribed: BooleanLiteralType = true
    private var featureOverrides: [ProFeature: Bool] = [:]

    public init() {}

    public func isFeatureUnlocked(_ feature: ProFeature) -> Bool {
        return featureOverrides[feature] ?? isProSubscribed
    }

    public func setFeatureOverride(_ feature: ProFeature, unlocked: Bool?) {
        if let unlocked = unlocked {
            featureOverrides[feature] = unlocked
        } else {
            featureOverrides.removeValue(forKey: feature)
        }
        objectWillChange.send()
    }

    public func resetOverrides() {
        featureOverrides.removeAll()
        isProSubscribed = true
        objectWillChange.send()
    }
}

public struct ProBadge: View {
    public var text: String = "PRO"

    public init(text: String = "PRO") {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(AppColors.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.purpleBg)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.purple.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(6)
    }
}
