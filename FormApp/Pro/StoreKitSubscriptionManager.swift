import Foundation
import StoreKit

@MainActor
public class StoreKitSubscriptionManager: ObservableObject {
    public static let shared = StoreKitSubscriptionManager()

    public static let monthlyProductId = "com.perseverancesoftware.forcedrep.pro.monthly"
    public static let annualProductId = "com.perseverancesoftware.forcedrep.pro.annual"

    public static let productIds: Set<String> = [
        monthlyProductId,
        annualProductId
    ]

    private static let keyCachedEntitlement = "form_cached_pro_entitlement"

    @Published public var products: [Product] = []
    @Published public var purchasedProductIds: Set<String> = []
    @Published public var isPurchasing: Bool = false
    @Published public var errorMessage: String? = nil

    public var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductId }
    }

    public var annualProduct: Product? {
        products.first { $0.id == Self.annualProductId }
    }

    private var transactionListener: Task<Void, Never>? = nil

    public init() {
        // Fast path: restore from local cache first for instant offline readiness
        let cachedActive = UserDefaults.standard.bool(forKey: Self.keyCachedEntitlement)
        if cachedActive {
            ProAccessManager.shared.updateSubscriptionStatus(active: true)
        }

        transactionListener = listenForTransactions()

        Task {
            await requestProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    public func requestProducts() async {
        do {
            let fetched = try await Product.products(for: Self.productIds)
            self.products = fetched.sorted { $0.price < $1.price }
        } catch {
            print("[StoreKit] Failed to fetch products: \(error)")
        }
    }

    public func purchase(plan: PaywallPlan) async throws -> Bool {
        let targetId = (plan == .annual) ? Self.annualProductId : Self.monthlyProductId
        guard let product = products.first(where: { $0.id == targetId }) else {
            // If product details haven't finished loading yet, try fetching again
            let fetched = try await Product.products(for: [targetId])
            guard let fetchedProduct = fetched.first else {
                throw NSError(
                    domain: "StoreKitSubscriptionManager",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Product not available in StoreKit."]
                )
            }
            return try await executePurchase(product: fetchedProduct)
        }
        return try await executePurchase(product: product)
    }

    private func executePurchase(product: Product) async throws -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            return true

        case .userCancelled:
            return false

        case .pending:
            // Family sharing approval or parental ask-to-buy pending
            return false

        @unknown default:
            return false
        }
    }

    public func restorePurchases() async throws {
        errorMessage = nil
        try await StoreKit.AppStore.sync()
        await updatePurchasedProducts()
    }

    public func updatePurchasedProducts() async {
        var purchasedIds: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                purchasedIds.insert(transaction.productID)
            }
        }
        self.purchasedProductIds = purchasedIds
        let isPro = !purchasedIds.isEmpty
        UserDefaults.standard.set(isPro, forKey: Self.keyCachedEntitlement)
        ProAccessManager.shared.updateSubscriptionStatus(active: isPro)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
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
