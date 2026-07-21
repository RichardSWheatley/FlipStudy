import Foundation
import StoreKit

/// FlipStudy Pro: a single one-time (non-consumable) in-app purchase that
/// unlocks the on-device Apple Intelligence features — AI decks from a typed
/// subject, and AI question/answer extraction when scanning a page.
///
/// This is the single source of truth for "is the user Pro?". Entitlement comes
/// straight from StoreKit's on-device receipt (works offline), so there's no
/// account and nothing to store ourselves. Inject one instance at the app root
/// and read it with `@Environment(ProStore.self)`.
@MainActor
@Observable
final class ProStore {
    /// Must match the Product ID of the non-consumable created in App Store
    /// Connect (and in the local `FlipStudy.storekit` config used for testing).
    static let productID = "com.flipstudy.app.pro"

    /// The loaded product, once the store has vended it. Nil until loaded (or if
    /// the product isn't configured yet), which is why the paywall shows a
    /// fallback price and a friendly "try again" if a tap arrives too early.
    private(set) var product: Product?

    /// Whether the user currently owns Pro. Drives every AI gate in the app.
    private(set) var isPro = false

    /// True while the product list is loading, so the paywall can show a spinner
    /// instead of an empty price.
    private(set) var isLoadingProduct = false

    /// The most recent user-facing error (purchase failed, product missing…).
    var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // Keep listening for transactions for the app's lifetime (Ask-to-Buy
        // approvals, purchases made on another device, refunds/revocations).
        updatesTask = listenForTransactions()
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    /// Display price from the store (localized), falling back to the planned
    /// price before the product has loaded.
    var priceText: String {
        product?.displayPrice ?? "$0.99"
    }

    // MARK: - Loading

    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Recompute `isPro` from StoreKit's current entitlements. A verified,
    /// non-revoked transaction for our product means the user owns Pro.
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                owned = true
            }
        }
        isPro = owned
    }

    // MARK: - Purchase / restore

    /// Start the system purchase flow. Apple handles payment and authentication
    /// (Face ID / password / Ask to Buy) — we only react to the result. Returns
    /// true once Pro is unlocked.
    @discardableResult
    func purchase() async -> Bool {
        lastError = nil
        if product == nil { await loadProduct() }
        guard let product else {
            lastError = "The upgrade isn't available right now. Please try again in a moment."
            return false
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Couldn't verify that purchase. Please try again."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return isPro
            case .userCancelled:
                return false
            case .pending:
                lastError = "Your purchase needs approval before it can finish."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Restore a previous purchase on a new device or after a reinstall.
    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    // MARK: - Transaction updates

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }
}
