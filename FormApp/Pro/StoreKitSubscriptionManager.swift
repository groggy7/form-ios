import Foundation
import StoreKit

@MainActor
public class StoreKitSubscriptionManager: ObservableObject {
    public static let shared = StoreKitSubscriptionManager()

    public static let monthlyProductId = "com.perseverancesoftware.forcedrep.premium.monthly"
    public static let annualProductId = "com.perseverancesoftware.forcedrep.premium.annual"

    // Backward compatibility with legacy Pro IDs
    public static let legacyMonthlyProductId = "com.perseverancesoftware.forcedrep.pro.monthly"
    public static let legacyAnnualProductId = "com.perseverancesoftware.forcedrep.pro.annual"

    public static let productIds: Set<String> = [
        monthlyProductId,
        annualProductId,
        legacyMonthlyProductId,
        legacyAnnualProductId
    ]

    public static func isProProductId(_ productId: String) -> Bool {
        productIds.contains(productId)
    }

    private static let keyCachedEntitlement = "form_cached_pro_entitlement"
    private static let keyCachedEntitlementLastVerified = "form_cached_pro_entitlement_last_verified"
    private static let offlineGracePeriodSeconds: TimeInterval = 7 * 24 * 60 * 60 // 7 days

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

    public init() {
        // Fast path: restore from local cache first for instant offline readiness if within grace period
        let cachedActive = UserDefaults.standard.bool(forKey: Self.keyCachedEntitlement)
        let lastVerified = UserDefaults.standard.double(forKey: Self.keyCachedEntitlementLastVerified)
        let now = Date().timeIntervalSince1970
        let isWithinGrace = cachedActive && lastVerified > 0 && (now - lastVerified) <= Self.offlineGracePeriodSeconds && (lastVerified - now) <= 300
        if isWithinGrace {
            ProAccessManager.shared.updateSubscriptionStatus(active: true)
            CloudMirrorManager.shared.retryPendingSyncIfAny()
        } else if cachedActive && (now - lastVerified) > Self.offlineGracePeriodSeconds {
            UserDefaults.standard.set(false, forKey: Self.keyCachedEntitlement)
            ProAccessManager.shared.updateSubscriptionStatus(active: false)
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
            let fetched = try await Product.products(for: Self.productIds)
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
        let productToPurchase = (plan == .annual) ? annualProduct : monthlyProduct
        let targetId = productToPurchase?.id ?? ((plan == .annual) ? Self.annualProductId : Self.monthlyProductId)
        guard let product = productToPurchase ?? products.first(where: { $0.id == targetId }) else {
            // If product details haven't finished loading yet, try fetching again
            let fetched = try await Product.products(for: [targetId])
            guard let fetchedProduct = fetched.first else {
                throw NSError(
                    domain: "StoreKitSubscriptionManager",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: LanguageManager.t("paywall.purchase_failed")]
                )
            }
            return try await executePurchase(product: fetchedProduct)
        }
        return try await executePurchase(product: product)
    }

    private func executePurchase(product: Product) async throws -> PurchaseStatus {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            guard Self.isProProductId(transaction.productID) else {
                throw NSError(domain: "StoreKitSubscriptionManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Unexpected product in Premium purchase"])
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
        var purchasedIds: Set<String> = []
        let now = Date()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.isProProductId(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= now {
                continue
            }
            purchasedIds.insert(transaction.productID)
        }
        self.purchasedProductIds = purchasedIds
        let isPro = !purchasedIds.isEmpty
        if isPro {
            eligibleFreeTrialProductIds = []
            UserDefaults.standard.set(true, forKey: Self.keyCachedEntitlement)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.keyCachedEntitlementLastVerified)
            ProAccessManager.shared.updateSubscriptionStatus(active: true)
            CloudMirrorManager.shared.retryPendingSyncIfAny()
        } else {
            // Authoritative store query returned zero active entitlements.
            // Revoke Premium immediately and clear the cached verification timestamp.
            UserDefaults.standard.set(false, forKey: Self.keyCachedEntitlement)
            UserDefaults.standard.set(0.0, forKey: Self.keyCachedEntitlementLastVerified)
            ProAccessManager.shared.updateSubscriptionStatus(active: false)
        }
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
