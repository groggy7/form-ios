import UIKit

/// A Home Screen icon founders can choose. `alternateIconName` names its app icon set in
/// Assets.xcassets, nil for the primary AppIcon; docs/design/launcher-icon.md#alternate-app-icons
/// explains how to add one.
public struct AppIconOption: Identifiable, Equatable {
    public let id: String
    public let alternateIconName: String?
    public let nameKey: String
}

public enum AppIcons {
    public static let standard = AppIconOption(id: "default", alternateIconName: nil, nameKey: "settings.appIconDefault")

    /// Picker order, default first.
    public static let all: [AppIconOption] = [standard]
}

/// The parts of UIApplication that icon switching uses, so tests can stand in for iOS.
@MainActor
protocol AlternateIconHost: AnyObject {
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }
    func setAlternateIconName(_ alternateIconName: String?) async throws
}

extension UIApplication: AlternateIconHost {}

/// iOS keeps the chosen icon itself, across launches and updates, so there is no preference of our own.
@MainActor
public final class AppIconManager: ObservableObject {
    public static let shared = AppIconManager()

    @Published public private(set) var current: AppIconOption
    let icons: [AppIconOption]
    private let host: AlternateIconHost

    init(host: AlternateIconHost = UIApplication.shared, icons: [AppIconOption] = AppIcons.all) {
        self.host = host
        self.icons = icons
        current = Self.option(named: host.alternateIconName, in: icons)
    }

    /// An icon set this build no longer lists falls back to the default rather than showing no selection.
    static func option(named name: String?, in icons: [AppIconOption]) -> AppIconOption {
        icons.first { name != nil && $0.alternateIconName == name } ?? icons[0]
    }

    /// Returns false when iOS refuses the change; the previous icon then stays. iOS confirms a
    /// change with its own alert.
    @discardableResult
    public func select(_ option: AppIconOption) async -> Bool {
        guard option != current else { return true }
        guard host.supportsAlternateIcons else { return false }
        do {
            try await host.setAlternateIconName(option.alternateIconName)
            current = option
            return true
        } catch {
            return false
        }
    }

    /// The primary icon's compiled 60pt file, found through Info.plist. iOS gives apps no image of an
    /// alternate set, so each one ships a `<set name>-Preview` image exported from the same PNG.
    static func previewImage(for option: AppIconOption, bundle: Bundle = .main) -> UIImage? {
        if let name = option.alternateIconName {
            return UIImage(named: "\(name)-Preview", in: bundle, compatibleWith: nil)
        }
        let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        guard let file = (primary?["CFBundleIconFiles"] as? [String])?.last else { return nil }
        return UIImage(named: file, in: bundle, compatibleWith: nil)
    }
}
