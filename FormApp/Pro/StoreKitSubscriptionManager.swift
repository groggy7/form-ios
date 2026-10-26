import Foundation
import StoreKit

@MainActor
public class StoreKitSubscriptionManager: ObservableObject {
    public static let shared = StoreKitSubscriptionManager()

    public static let monthlyProductId = "com.perseverancesoftware.forcedrep.premium.monthly"
    public static let annualProductId = "com.perseverancesoftware.forcedrep.premium.annual"
    // Retain the original store ID: the product is now sold as Lifetime Pro.
    public static let lifetimeProductId = "com.perseverancesoftware.forcedrep.founders"
    public static let legacyLifetimeProductId = "com.perseverancesoftware.forcedrep.lifetime"

    // Backward compatibility with legacy Pro IDs
    public static let legacyMonthlyProductId = "com.perseverancesoftware.forcedrep.pro.monthly"
    public static let legacyAnnualProductId = "com.perseverancesoftware.forcedrep.pro.annual"

    public static let productIds: Set<String> = [
        monthlyProductId,
        annualProductId,
        legacyMonthlyProductId,
        legacyAnnualProductId,
        lifetimeProductId,
        legacyLifetimeProductId
    ]

    public static func isProProductId(_ productId: String) -> Bool {
        productIds.contains(productId)
    }

    private static let keyCachedEntitlement = "form_cached_pro_entitlement"
    private static let keyCachedEntitlementLastVerified = "form_cached_pro_entitlement_last_verified"
    static let keyCachedProductIds = "form_cached_product_ids"
    static let offlineGracePeriodSeconds: TimeInterval = 7 * 24 * 60 * 60

    struct Entitlements: Equatable {
        let subscription: Bool
        let lifetime: Bool
        var hasPro: Bool { subscription || lifetime }
    }

    static func entitlements(for productIDs: Set<String>) -> Entitlements {
        Entitlements(subscription: !productIDs.intersection([monthlyProductId, annualProductId, legacyMonthlyProductId, legacyAnnualProductId]).isEmpty,
                     lifetime: !productIDs.intersection([lifetimeProductId, legacyLifetimeProductId]).isEmpty)
    }

    static func cachedProductIDs(defaults: UserDefaults, now: Date = Date()) -> Set<String> {
        let checked = defaults.double(forKey: keyCachedEntitlementLastVerified)
        let age = now.timeIntervalSince1970 - checked
        guard defaults.bool(forKey: keyCachedEntitlement), checked > 0,
              age >= -300, age <= offlineGracePeriodSeconds else { return [] }
        // Caches without product IDs came from subscriptions; never infer lifetime access from that flag.
        return Set(defaults.stringArray(forKey: keyCachedProductIds) ?? [monthlyProductId]).intersection(productIds)
    }

    @Published public var products: [Product] = []
    @Published public private(set) var eligibleFreeTrialProductIds: Set<String> = []
    @Published public var purchasedProductIds: Set<String> = []
    @Published public var isPurchasing: Bool = false
    @Published public var errorMessage: String? = nil

    public var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductId } ?? products.first { $0.id == Self.legacyMonthlyProductId }
    }

    public var annualProduct: Product? {
        products.first { $0.id == Self.annualProductId } ?? products.first { $0.id == Self.legacyAnnualProductId }
    }

    public var lifetimeProduct: Product? { products.first { $0.id == Self.lifetimeProductId && $0.type == .nonConsumable } }

    public var annualPerMonthDisplayPrice: String? {
        guard let product = annualProduct else { return nil }
        let perMonth = product.price / 12
        let formatted = perMonth.formatted(product.priceFormatStyle)
        let suffix = LanguageManager.t("paywall.per_month_suffix")
        return "\(formatted)\(suffix)"
    }

    public static func savingsPercentage(monthly: Decimal, annual: Decimal) -> Int? {
        guard monthly > 0, annual > 0 else { return nil }
        let savings = (1 - annual / (monthly * 12)) * 100
        let rounded = Int((savings as NSDecimalNumber).doubleValue.rounded())
        return rounded > 0 ? rounded : nil
    }

    public var annualSavingsPercentage: Int? {
        guard let monthly = monthlyProduct, let annual = annualProduct else { return nil }
        return Self.savingsPercentage(monthly: monthly.price, annual: annual.price)
    }

    public func hasFreeTrial(for plan: PaywallPlan) -> Bool {
        guard purchasedProductIds.isEmpty else { return false }
        let product = (plan == .annual) ? annualProduct : monthlyProduct
        guard let product else { return false }
        return eligibleFreeTrialProductIds.contains(product.id)
    }

    public enum PurchaseStatus {
        case success
        case userCancelled
        case pending
    }

    private var transactionListener: Task<Void, Never>? = nil
    private var entitlementRevision = 0

    public init() {
        // Fast path: restore from local cache first for instant offline readiness if within grace period
        let cached = Self.cachedProductIDs(defaults: .standard)
        let entitlement = Self.entitlements(for: cached)
        purchasedProductIds = cached
        ProAccessManager.shared.updateEntitlements(subscription: entitlement.subscription, lifetime: entitlement.lifetime)
        if entitlement.hasPro {
            CloudMirrorManager.shared.retryPendingSyncIfAny()
        }

        transactionListener = listenForTransactions()

        // Entitlements must restore even when fetching paywall products is slow or offline.
        Task { await updatePurchasedProducts() }
        Task { await requestProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    public func requestProducts() async {
        eligibleFreeTrialProductIds = []
        do {
            let fetched = try await Product.products(for: Self.productIds.subtracting([Self.legacyLifetimeProductId]))
            var eligibleIds: Set<String> = []
            for product in fetched {
                guard let subscription = product.subscription,
                      subscription.introductoryOffer?.paymentMode == .freeTrial,
                      await subscription.isEligibleForIntroOffer else { continue }
                eligibleIds.insert(product.id)
            }
            self.products = fetched.sorted { $0.price < $1.price }
            self.eligibleFreeTrialProductIds = purchasedProductIds.isEmpty ? eligibleIds : []
        } catch {
            print("[StoreKit] Failed to fetch products: \(error)")
        }
    }

    public func purchase(plan: PaywallPlan) async throws -> PurchaseStatus {
        let product = plan == .annual ? annualProduct : monthlyProduct
        let id = product?.id ?? (plan == .annual ? Self.annualProductId : Self.monthlyProductId)
        return try await purchaseProduct(id: id, type: .autoRenewable)
    }

    public func purchaseLifetime() async throws -> PurchaseStatus {
        guard !ProAccessManager.shared.hasLifetimeAccess else { return .success }
        return try await purchaseProduct(id: Self.lifetimeProductId, type: .nonConsumable)
    }

    private func purchaseProduct(id: String, type: Product.ProductType) async throws -> PurchaseStatus {
        guard !isPurchasing else {
            throw NSError(domain: "StoreKitSubscriptionManager", code: 409,
                          userInfo: [NSLocalizedDescriptionKey: LanguageManager.t("paywall.purchase_failed")])
        }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        // Refresh before checkout, and hold the purchase lock while fetching as well as purchasing.
        guard let product = try await Product.products(for: [id]).first, product.type == type else {
            throw NSError(domain: "StoreKitSubscriptionManager", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: LanguageManager.t("paywall.error_product_unavailable")])
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            guard transaction.productID == product.id,
                  Self.grantsPremium(productID: transaction.productID, revocationDate: transaction.revocationDate, isUpgraded: transaction.isUpgraded) else {
                throw NSError(domain: "StoreKitSubscriptionManager", code: 403, userInfo: [NSLocalizedDescriptionKey: LanguageManager.t("paywall.error_verification_failed")])
            }
            await updatePurchasedProducts()
            await transaction.finish()
            return .success

        case .userCancelled:
            return .userCancelled

        case .pending:
            // Family sharing approval or parental ask-to-buy pending
            return .pending

        @unknown default:
            return .userCancelled
        }
    }

    @discardableResult
    public func restorePurchases() async throws -> Bool {
        errorMessage = nil
        try await StoreKit.AppStore.sync()
        await updatePurchasedProducts()
        return !purchasedProductIds.isEmpty
    }

    public func updatePurchasedProducts() async {
        entitlementRevision += 1
        let revision = entitlementRevision
        var purchasedIds: Set<String> = []
        let now = Date()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.grantsPremium(productID: transaction.productID, revocationDate: transaction.revocationDate,
                                  isUpgraded: transaction.isUpgraded) {
                purchasedIds.insert(transaction.productID)
            }
        }
        guard revision == entitlementRevision else { return }
        self.purchasedProductIds = purchasedIds
        let entitlement = Self.entitlements(for: purchasedIds)
        let isPro = entitlement.hasPro
        UserDefaults.standard.set(Array(purchasedIds), forKey: Self.keyCachedProductIds)
        ProAccessManager.shared.updateEntitlements(subscription: entitlement.subscription, lifetime: entitlement.lifetime)
        if !entitlement.hasPro, AppIconManager.shared.current != AppIcons.standard {
            _ = await AppIconManager.shared.select(AppIcons.standard)
        }
        guard revision == entitlementRevision else { return }
        if isPro {
            eligibleFreeTrialProductIds = []
            UserDefaults.standard.set(true, forKey: Self.keyCachedEntitlement)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.keyCachedEntitlementLastVerified)
            CloudMirrorManager.shared.retryPendingSyncIfAny()
        } else {
            // Authoritative store query returned zero active entitlements.
            // Revoke Premium immediately and clear the cached verification timestamp.
            UserDefaults.standard.set(false, forKey: Self.keyCachedEntitlement)
            UserDefaults.standard.set(0.0, forKey: Self.keyCachedEntitlementLastVerified)
        }
    }

    /// Current entitlements already exclude expired subscriptions and deliberately include those in
    /// Apple's billing grace period, whose expiration date has passed; never re-check that date here.
    static func grantsPremium(productID: String, revocationDate: Date?, isUpgraded: Bool) -> Bool {
        productIds.contains(productID) && revocationDate == nil && !isUpgraded
    }

    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    guard await Self.isProProductId(transaction.productID) else { continue }
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    print("[StoreKit] Transaction verification failed: \(error)")
                }
            }
        }
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
