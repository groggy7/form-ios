import XCTest
import SwiftUI
import StoreKit
import StoreKitTest
@testable import FormApp

@MainActor
final class LifetimePaywallTests: XCTestCase {
    func testLifetimePaywallCopyIsTranslated() {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            let paywall = ["badge", "headline", "subtitle", "benefit1", "benefit1_desc", "benefit2", "benefit2_desc",
                           "benefit3", "benefit3_desc", "plan", "planSubtitle", "cta", "platformNote"].map { "lifetime.\($0)" }
            for key in paywall {
                XCTAssertNotEqual(LanguageManager.t(key), key, "\(language) lacks \(key)")
            }
        }
    }

    func testEveryProPurchaseUnlocksTheSameFeaturesAndResetClearsAccess() {
        let access = ProAccessManager()
        for subscription in [true, false] {
            access.updateEntitlements(subscription: subscription, lifetime: !subscription)
            XCTAssertTrue(access.isProSubscribed)
            XCTAssertTrue(access.isFeatureUnlocked(.customThemes))
            XCTAssertEqual(access.hasLifetimeAccess, !subscription)
            access.resetOverrides()
            XCTAssertFalse(access.isProSubscribed)
            XCTAssertFalse(access.hasLifetimeAccess)
        }
    }

    func testLifetimePaywallRendersInEveryLanguage() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/lifetime-paywall-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for (width, size) in [(CGFloat(393), ContentSizeCategory.large), (320, .extraExtraExtraLarge)] {
                for canPurchase in [true, false] {
                    let paywall = render(paywall(price: canPurchase ? "$79.99" : nil),
                                         width: width, height: size == .large ? 900 : 1500, size: size)
                    XCTAssertEqual(paywall.size.width, width)
                    try XCTUnwrap(paywall.pngData()).write(to: outputDir.appendingPathComponent(
                        "lifetime-paywall-\(language)-\(Int(width))\(canPurchase ? "" : "-unavailable").png"))
                }
            }
        }
    }

    func testLifetimeReviewScreenshotUsesTheStorePriceAndPortraitBounds() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FORCED_REP_STOREKIT_TESTS"] == "1", "Use the local StoreKit scheme")
        // Every plan card shows the price configured in ForcedRep.storekit, not a sample, because this capture is uploaded
        // for App Review. Prices are read from the file rather than fetched: on a freshly erased simulator, StoreKit answers
        // with App Store Connect's sandbox prices before a test session can take over, and caches them for the process.
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ForcedRep", withExtension: "storekit"))
        let prices = try fixturePrices(url)
        func price(_ id: String) throws -> String {
            try XCTUnwrap(prices[id]).formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
        }
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("en")
        let bounds = CGRect(x: 0, y: 0, width: 440, height: 956)
        let image = render(paywall(price: try price(StoreKitSubscriptionManager.lifetimeProductId),
                                   annualPrice: try price(StoreKitSubscriptionManager.annualProductId),
                                   monthlyPrice: try price(StoreKitSubscriptionManager.monthlyProductId)),
                           width: bounds.width, height: bounds.height, size: .large)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/lifetime-review").standardized
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent("lifetime-pro-iphone.png"))
        try XCTUnwrap(image.jpegData(compressionQuality: 0.95)).write(to: output.appendingPathComponent("lifetime-pro-iphone.jpg"))
    }

    /// Product ID → configured price for every in-app purchase and subscription in a StoreKit configuration file.
    private func fixturePrices(_ url: URL) throws -> [String: Decimal] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let products = root["products"] as? [[String: Any]] ?? []
        let groups = root["subscriptionGroups"] as? [[String: Any]] ?? []
        let entries = products + groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        var prices: [String: Decimal] = [:]
        for entry in entries {
            let id = try XCTUnwrap(entry["productID"] as? String)
            prices[id] = try XCTUnwrap((entry["displayPrice"] as? String).flatMap { Decimal(string: $0) })
        }
        return prices
    }

    private func paywall(price: String?, plan: PaywallPlan = .lifetime, subscriber: Bool = false,
                         annualPrice: String = "$29.99", monthlyPrice: String = "$4.99") -> some View {
        SessionFeaturePaywallContent(
            annual: SessionPaywallOffer(price: annualPrice, hasTrial: true),
            monthly: SessionPaywallOffer(price: monthlyPrice), selectedPlan: plan,
            isPurchasing: false, isRestoring: false, purchaseError: nil, restoreMessage: nil, isRestoreError: false,
            onSelectPlan: { _ in }, onPurchase: {}, onRestore: {}, onRetryPrices: {}, onTerms: {}, onPrivacy: {}, onClose: {},
            feature: nil, lifetime: SessionPaywallOffer(price: price), hasActiveSubscription: subscriber)
    }

    func testAllPlanStatesRenderInBothAppearances() throws {
        let previous = ThemeManager.shared.currentTheme
        defer { ThemeManager.shared.setThemeId(previous.id) }
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/integrated-paywall-review").standardized
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for theme in [AppThemes.default, AppThemes.oat] {
            ThemeManager.shared.setThemeId(theme.id)
            for plan in PaywallPlan.allCases {
                for plans in [false, true] {
                    let image = render(paywall(price: "$79.99", plan: plan), width: 393, height: 900, size: .large, plans: plans)
                    try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent("\(theme.id)-\(plan.rawValue)-\(plans ? "plans" : "top").png"))
                }
            }
        }
    }

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, size: ContentSizeCategory, plans: Bool = false) -> UIImage {
        // A fixed child canvas avoids foldable window-region offsets; UIKit-backed controls still render natively.
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let controller = UIHostingController(rootView: view
            .frame(width: width, height: height, alignment: .top)
            .background(AppColors.background)
            .environment(\.sizeCategory, size)
            .ignoresSafeArea())
        let container = UIViewController()
        let window = UIWindow(frame: bounds)
        window.rootViewController = container
        container.addChild(controller)
        container.view.addSubview(controller.view)
        controller.didMove(toParent: container)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.autoresizingMask = []
        controller.view.frame = bounds
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if plans {
            func scrollView(_ view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView { return scroll }
                return view.subviews.lazy.compactMap { scrollView($0) }.first
            }
            if let scroll = scrollView(controller.view) {
                scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
        }
        controller.view.frame = bounds
        controller.view.layoutIfNeeded()
        return UIGraphicsImageRenderer(size: bounds.size).image { _ in
            controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

}

@MainActor
final class LifetimeBillingTests: XCTestCase {
    func testOnlyTheConfiguredLifetimeProductGrantsPermanentAccess() {
        let current = StoreKitSubscriptionManager.entitlements(for: [StoreKitSubscriptionManager.lifetimeProductId])
        XCTAssertEqual(StoreKitSubscriptionManager.lifetimeProductId, "com.perseverancesoftware.forcedrep.lifetime")
        XCTAssertEqual(StoreKitSubscriptionManager.productIds.filter { $0.hasSuffix(".lifetime") }.count, 1)
        XCTAssertTrue(current.hasPro); XCTAssertTrue(current.lifetime); XCTAssertFalse(current.subscription)
        XCTAssertFalse(StoreKitSubscriptionManager.entitlements(for: ["unrelated.lifetime"]).hasPro)
    }

    func testOfflineCachePreservesLifetimeAndExpiresWithoutInventingOwnership() throws {
        let name = "LifetimeBillingTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        defaults.set(true, forKey: "form_cached_pro_entitlement")
        defaults.set(now.timeIntervalSince1970, forKey: "form_cached_pro_entitlement_last_verified")
        let legacy = StoreKitSubscriptionManager.entitlements(for: StoreKitSubscriptionManager.cachedProductIDs(defaults: defaults, now: now))
        XCTAssertTrue(legacy.subscription); XCTAssertFalse(legacy.lifetime)
        defaults.set([StoreKitSubscriptionManager.lifetimeProductId], forKey: StoreKitSubscriptionManager.keyCachedProductIds)
        XCTAssertTrue(StoreKitSubscriptionManager.entitlements(for: StoreKitSubscriptionManager.cachedProductIDs(defaults: defaults, now: now)).lifetime)
        XCTAssertTrue(StoreKitSubscriptionManager.cachedProductIDs(defaults: defaults, now: now.addingTimeInterval(8 * 86400)).isEmpty)
        XCTAssertTrue(StoreKitSubscriptionManager.cachedProductIDs(defaults: defaults, now: now.addingTimeInterval(-3600)).isEmpty)
    }

    private func testSession() async throws -> SKTestSession {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FORCED_REP_STOREKIT_TESTS"] == "1", "Use FormApp-LocalStoreKit")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ForcedRep", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.timeRate = .realTime
        session.disableDialogs = true
        session.clearTransactions()
        // Never invoke native checkout unless StoreKit is actually serving the local test environment.
        _ = try await session.buyProduct(identifier: StoreKitSubscriptionManager.monthlyProductId)
        var localTransaction: StoreKit.Transaction?
        for _ in 0..<50 {
            if let result = await StoreKit.Transaction.latest(for: StoreKitSubscriptionManager.monthlyProductId),
               case .verified(let transaction) = result {
                localTransaction = transaction
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let transaction = try XCTUnwrap(localTransaction, "Local StoreKit configuration is not active")
        guard transaction.environment == .xcode else {
            XCTFail("Expected the Xcode StoreKit environment before checkout")
            throw NSError(domain: "LifetimeBillingTests", code: 1)
        }
        session.clearTransactions()
        try await settle { StoreKitSubscriptionManager.shared.purchasedProductIds.isEmpty }
        return session
    }

    private func settle(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            await StoreKitSubscriptionManager.shared.updatePurchasedProducts()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("StoreKit entitlements did not settle: \(StoreKitSubscriptionManager.shared.purchasedProductIds)", file: file, line: line)
        throw NSError(domain: "LifetimeBillingTests", code: 2)
    }

    func testPurchaseRestoreRefundAndSubscriptionCoexistence() async throws {
        let session = try await testSession()
        defer { session.clearTransactions(); ProAccessManager.shared.resetOverrides() }
        let manager = StoreKitSubscriptionManager.shared
        let access = ProAccessManager.shared
        await manager.requestProducts()
        await manager.updatePurchasedProducts()
        _ = try XCTUnwrap(manager.lifetimeProduct)
        XCTAssertFalse(manager.hasFreeTrial(for: .lifetime))
        XCTAssertEqual(manager.products.filter { $0.type == .nonConsumable }.count, 1)
        _ = try await session.buyProduct(identifier: StoreKitSubscriptionManager.monthlyProductId)
        try await settle { access.hasActiveSubscription && !access.hasLifetimeAccess }
        _ = try await manager.purchase(plan: .lifetime)
        try await settle { access.hasLifetimeAccess && access.hasActiveSubscription }
        XCTAssertTrue(access.isFeatureUnlocked(.customThemes))
        access.resetOverrides()
        _ = try await manager.restorePurchases()
        try await settle { access.hasLifetimeAccess && access.isProSubscribed }
        let monthly = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == StoreKitSubscriptionManager.monthlyProductId })
        try session.disableAutoRenewForTransaction(identifier: monthly.identifier)
        try session.expireSubscription(productIdentifier: StoreKitSubscriptionManager.monthlyProductId)
        try await settle { !access.hasActiveSubscription && access.hasLifetimeAccess }
        let lifetime = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == StoreKitSubscriptionManager.lifetimeProductId })
        try session.refundTransaction(identifier: lifetime.identifier)
        try await settle { !access.isProSubscribed && !access.hasLifetimeAccess }
    }

    func testPendingPurchaseGrantsNothingUntilApproved() async throws {
        let session = try await testSession()
        defer { session.askToBuyEnabled = false; session.clearTransactions(); ProAccessManager.shared.resetOverrides() }
        let manager = StoreKitSubscriptionManager.shared
        let access = ProAccessManager.shared
        await manager.updatePurchasedProducts()
        await manager.requestProducts()
        _ = try XCTUnwrap(manager.lifetimeProduct)
        session.askToBuyEnabled = true
        let status = try await manager.purchaseLifetime()
        if case .pending = status {} else { XCTFail("Expected pending approval") }
        await manager.updatePurchasedProducts()
        XCTAssertFalse(access.hasLifetimeAccess); XCTAssertFalse(access.isProSubscribed)
        let pending = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == StoreKitSubscriptionManager.lifetimeProductId })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        try await settle { access.hasLifetimeAccess && access.isProSubscribed }
    }

    func testLifetimeRefundKeepsAnActiveSubscription() async throws {
        let session = try await testSession()
        defer { session.clearTransactions(); ProAccessManager.shared.resetOverrides() }
        let manager = StoreKitSubscriptionManager.shared
        let access = ProAccessManager.shared
        _ = try await session.buyProduct(identifier: StoreKitSubscriptionManager.monthlyProductId)
        _ = try await manager.purchaseLifetime()
        try await settle { access.hasActiveSubscription && access.hasLifetimeAccess }
        let lifetime = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == StoreKitSubscriptionManager.lifetimeProductId })
        try session.refundTransaction(identifier: lifetime.identifier)
        try await settle { !access.hasLifetimeAccess && access.hasActiveSubscription && access.isProSubscribed }
    }
}
