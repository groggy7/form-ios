import XCTest
import SwiftUI
@testable import FormApp

@MainActor
final class AppIconTests: XCTestCase {
    private final class FakeHost: AlternateIconHost {
        var supportsAlternateIcons = true
        var alternateIconName: String?
        var failure: Error?
        var requests: [String?] = []

        init(alternateIconName: String? = nil) { self.alternateIconName = alternateIconName }

        func setAlternateIconName(_ alternateIconName: String?) async throws {
            requests.append(alternateIconName)
            if let failure { throw failure }
            self.alternateIconName = alternateIconName
        }
    }

    private let founder = AppIconOption(id: "founder", alternateIconName: "AppIcon-Founder", nameKey: "settings.appIcon")
    private var icons: [AppIconOption] { [AppIcons.standard, founder] }

    func testCatalogStartsWithThePrimaryIconAndEveryAlternateIsBuilt() throws {
        XCTAssertEqual(AppIcons.all.first, AppIcons.standard)
        XCTAssertNil(AppIcons.standard.alternateIconName)
        XCTAssertEqual(Set(AppIcons.all.map(\.id)).count, AppIcons.all.count)
        let alternates = AppIcons.all.dropFirst().map(\.alternateIconName)
        XCTAssertFalse(alternates.contains(nil), "Only the first icon is the primary AppIcon")
        XCTAssertEqual(Set(alternates).count, alternates.count)
        let built = (Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])?["CFBundleAlternateIcons"] as? [String: Any] ?? [:]
        for case let name? in alternates {
            XCTAssertNotNil(built[name], "\(name) needs an app icon set in Assets.xcassets")
        }
    }

    func testEveryIconPreviewLoadsFromTheBuiltApp() {
        for option in AppIcons.all {
            XCTAssertNotNil(AppIconManager.previewImage(for: option), option.id)
        }
    }

    func testIconNamesAndPaywallCopyAreTranslated() {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            let paywall = ["badge", "headline", "subtitle", "benefit1", "benefit1_desc", "benefit2", "benefit2_desc",
                           "benefit3", "benefit3_desc", "plan", "planSubtitle", "cta", "notOnSale", "platformNote"].map { "founders.\($0)" }
            for key in AppIcons.all.map(\.nameKey) + ["settings.appIcon", "settings.appIconSubtitle", "settings.appIconFailed"] + paywall {
                XCTAssertNotEqual(LanguageManager.t(key), key, "\(language) lacks \(key)")
            }
        }
    }

    func testCurrentFollowsTheSystemIconAndAnUnlistedSetFallsBackToTheDefault() {
        XCTAssertEqual(AppIconManager(host: FakeHost(), icons: icons).current, AppIcons.standard)
        XCTAssertEqual(AppIconManager(host: FakeHost(alternateIconName: "AppIcon-Founder"), icons: icons).current, founder)
        XCTAssertEqual(AppIconManager(host: FakeHost(alternateIconName: "AppIcon-Removed"), icons: icons).current, AppIcons.standard)
    }

    func testChoosingAnIconPassesItsSetNameAndTheDefaultPassesNil() async {
        let host = FakeHost()
        let manager = AppIconManager(host: host, icons: icons)
        let chose = await manager.select(founder)
        XCTAssertTrue(chose)
        XCTAssertEqual(manager.current, founder)
        let again = await manager.select(founder)
        XCTAssertTrue(again)
        let restored = await manager.select(AppIcons.standard)
        XCTAssertTrue(restored)
        XCTAssertEqual(manager.current, AppIcons.standard)
        XCTAssertEqual(host.requests, ["AppIcon-Founder", nil], "Choosing the current icon asks iOS nothing")
    }

    func testARefusedOrUnsupportedChangeKeepsTheCurrentIcon() async {
        let host = FakeHost()
        host.failure = CocoaError(.fileNoSuchFile)
        let manager = AppIconManager(host: host, icons: icons)
        let refused = await manager.select(founder)
        XCTAssertFalse(refused)
        XCTAssertEqual(manager.current, AppIcons.standard)

        host.failure = nil
        host.supportsAlternateIcons = false
        let unsupported = await manager.select(founder)
        XCTAssertFalse(unsupported)
        XCTAssertEqual(manager.current, AppIcons.standard)
        XCTAssertEqual(host.requests, ["AppIcon-Founder"])
    }

    func testFounderStatusIsSeparateFromPremiumAndClearedByReset() {
        let access = ProAccessManager()
        access.updateSubscriptionStatus(active: true)
        XCTAssertFalse(access.isFounder, "A subscription is not a Founders Pass")
        access.updateFounderStatus(active: true)
        XCTAssertTrue(access.isFounder)
        access.resetOverrides()
        XCTAssertFalse(access.isFounder)
    }

    /// Captures for review under forcedrep-ios/build/app-icon-review/: Settings with founder status off and on,
    /// and the row, picker and Founders Pass paywall in every language at 393pt and at 320pt with the largest standard text.
    func testRowPickerAndPaywallRenderInEveryLanguage() throws {
        let previous = LanguageManager.shared.languagePreference
        let wasFounder = ProAccessManager.shared.isFounder
        defer {
            LanguageManager.setLanguage(previous)
            ProAccessManager.shared.updateFounderStatus(active: wasFounder)
        }
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/app-icon-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let manager = AppIconManager(host: FakeHost(), icons: icons)

        LanguageManager.setLanguage("en")
        for isFounder in [false, true] {
            ProAccessManager.shared.updateFounderStatus(active: isFounder)
            let image = render(SettingsView(store: AppStore.shared, onDismiss: {}),
                               width: 393, height: 1500, size: .large)
            try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("settings-\(isFounder ? "founder" : "member").png"))
        }

        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for (width, size) in [(CGFloat(393), ContentSizeCategory.large), (320, .extraExtraExtraLarge)] {
                let content = VStack(spacing: 16) {
                    SettingsAppIconRow(current: AppIcons.standard, action: {})
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    AppIconSelectionSheet(manager: manager, onDismiss: {})
                        .frame(height: size == .large ? 320 : 520)
                }
                let image = render(content, width: width, height: size == .large ? 600 : 900, size: size)
                XCTAssertEqual(image.size.width, width)
                try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("app-icon-\(language)-\(Int(width)).png"))
                for canPurchase in [true, false] {
                    let paywall = render(FoundersPassPaywallContent(canPurchase: canPurchase, onPurchase: {}, onTerms: {}, onPrivacy: {}, onClose: {}),
                                         width: width, height: size == .large ? 900 : 1500, size: size)
                    XCTAssertEqual(paywall.size.width, width)
                    try XCTUnwrap(paywall.pngData()).write(to: outputDir.appendingPathComponent(
                        "founders-paywall-\(language)-\(Int(width))\(canPurchase ? "" : "-release").png"))
                }
            }
        }
    }

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, size: ContentSizeCategory) -> UIImage {
        let controller = UIHostingController(rootView: view
            .frame(width: width).frame(maxHeight: .infinity, alignment: .top)
            .background(AppColors.background)
            .environment(\.sizeCategory, size))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
