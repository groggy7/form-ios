import SwiftUI

public enum ProFeature: String, CaseIterable, Identifiable {
    case volumeMatrix = "volume_matrix"
    case autoProgression = "auto_progression"
    case warmupCalculator = "warmup_calculator"
    case formLab = "form_lab"
    case cloudBackup = "cloud_backup"
    case customThemes = "custom_themes"
    case exerciseSwaps = "exercise_swaps"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .volumeMatrix: return "pro.volume_matrix.title"
        case .autoProgression: return "pro.auto_progression.title"
        case .warmupCalculator: return "pro.warmup_calculator.title"
        case .formLab: return "pro.form_lab.title"
        case .cloudBackup: return "pro.cloud_backup.title"
        case .customThemes: return "pro.custom_themes.title"
        case .exerciseSwaps: return "pro.exercise_swaps.title"
        }
    }

    public var descriptionKey: String {
        switch self {
        case .volumeMatrix: return "pro.volume_matrix.description"
        case .autoProgression: return "pro.auto_progression.description"
        case .warmupCalculator: return "pro.warmup_calculator.description"
        case .formLab: return "pro.form_lab.description"
        case .cloudBackup: return "pro.cloud_backup.description"
        case .customThemes: return "pro.custom_themes.description"
        case .exerciseSwaps: return "pro.exercise_swaps.description"
        }
    }

    public var teaserKey: String {
        switch self {
        case .volumeMatrix: return "pro.volume_matrix.teaser"
        case .autoProgression: return "pro.auto_progression.teaser"
        case .warmupCalculator: return "pro.warmup_calculator.teaser"
        case .formLab: return "pro.form_lab.teaser"
        case .cloudBackup: return "pro.cloud_backup.teaser"
        case .customThemes: return "pro.custom_themes.teaser"
        case .exerciseSwaps: return "pro.exercise_swaps.teaser"
        }
    }
}

public final class ProAccessManager: ObservableObject {
    public static let shared = ProAccessManager()

    @Published public private(set) var isProSubscribed: Bool = false
    private let entitlementLock = NSLock()
    private var subscribedSnapshot = false
    private var featureOverrides: [ProFeature: Bool] = [:]

    public init() {}

    /// Background cloud authorization reads this snapshot, never Published state.
    public func isFeatureUnlocked(_ feature: ProFeature) -> Bool {
        entitlementLock.lock()
        defer { entitlementLock.unlock() }
        return featureOverrides[feature] ?? subscribedSnapshot
    }

    public func setFeatureOverride(_ feature: ProFeature, unlocked: Bool?) {
        dispatchPrecondition(condition: .onQueue(.main))
        objectWillChange.send()
        entitlementLock.lock()
        featureOverrides[feature] = unlocked
        entitlementLock.unlock()
    }

    public func resetOverrides() {
        dispatchPrecondition(condition: .onQueue(.main))
        entitlementLock.lock()
        featureOverrides.removeAll()
        subscribedSnapshot = false
        entitlementLock.unlock()
        isProSubscribed = false
    }

    @discardableResult
    public func toggleSubscriptionStatus() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        let next = !isProSubscribed
        updateSubscriptionStatus(active: next)
        return next
    }

    public func updateSubscriptionStatus(active: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        entitlementLock.lock()
        subscribedSnapshot = active
        entitlementLock.unlock()
        // Publish after releasing the lock so subscribers can read the snapshot.
        isProSubscribed = active
    }
}

public struct ProBadge: View {
    @ObservedObject var themeManager = ThemeManager.shared
    public var text: String = "PREMIUM"
    @ScaledMetric(relativeTo: .caption2) private var fontSize = 8.5

    public init(text: String = "PREMIUM") {
        self.text = text
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .tracking(0.2)
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(AppColors.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppColors.purpleBg)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppColors.purple.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

public enum LegalUrls {
    public static let termsOfService = "https://perseverance-software.github.io/forcedrep/terms/"
    public static let privacyPolicy = "https://perseverance-software.github.io/forcedrep/privacy/"
    public static let support = "https://perseverance-software.github.io/forcedrep/support/"
    public static let manageSubscriptions = "https://apps.apple.com/account/subscriptions"
}
