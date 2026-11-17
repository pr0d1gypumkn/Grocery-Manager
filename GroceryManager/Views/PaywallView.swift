import StoreKit
import SwiftUI

/// A gentle upgrade sheet: explains what the feature does, lists the plan, and offers the
/// two subscriptions. Dismissing it never blocks anything the free tier includes.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = SubscriptionStore.shared
    @State private var entitlements = EntitlementService.shared
    @State private var isPurchasing = false

    var feature: Feature?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    featureList
                    plans
                    footer
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background { AmbientBackground(tint: .purple) }
            .navigationTitle(feature == nil ? "Mealy Plus" : feature!.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
            .task { await store.loadProducts() }
            .onChange(of: entitlements.isPlus) { _, isPlus in
                if isPlus { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(symbol: feature?.symbol ?? "sparkles", tint: .purple, size: 52)
            Text(feature?.summary ?? "Price-aware shopping, a week planned for you, recipe ideas, social import, household sharing and checkout links.")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Everything you already use stays free, and your data is always yours to export.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Included in Plus")
                .font(.headline)
            ForEach(Feature.allCases) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(item == feature ? Color.purple : Color.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        Text(item.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .glassCard(cornerRadius: 24)
    }

    @ViewBuilder
    private var plans: some View {
        if store.isLoading && store.products.isEmpty {
            ProgressView().frame(maxWidth: .infinity)
        } else if store.products.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Plans aren't available right now.")
                    .font(.subheadline.weight(.semibold))
                Text(store.purchaseError ?? "Check your connection and try again. On a simulator, enable the StoreKit configuration in the scheme.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 22)
        } else {
            VStack(spacing: 12) {
                if let yearly = store.yearly {
                    planButton(yearly, badge: store.yearlySavings.map { "Save \($0)%" }, prominent: true)
                }
                if let monthly = store.monthly {
                    planButton(monthly, badge: nil, prominent: false)
                }
            }
        }
    }

    private func planButton(_ product: Product, badge: String?, prominent: Bool) -> some View {
        Button {
            guard !isPurchasing else { return }
            isPurchasing = true
            Task {
                await store.purchase(product)
                isPurchasing = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName.isEmpty ? (product.id.hasSuffix("yearly") ? "Yearly" : "Monthly") : product.displayName)
                        .font(.headline)
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(prominent ? .white.opacity(0.85) : .secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.headline.monospacedDigit())
                    if let badge {
                        StatusBadge(text: badge, tint: prominent ? .white : .green)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass(prominent ? .regular.tint(.purple).interactive() : .regular.interactive()))
        .disabled(isPurchasing)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.purchaseError, !store.products.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button("Restore purchases") { Task { await store.restore() } }
                .font(.footnote)
            Text("Subscriptions renew automatically until cancelled in your App Store settings. If a subscription lapses, nothing is deleted; only Plus features pause.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// A card that explains a Plus feature and offers the upgrade, for places where the free
/// experience simply continues without it.
struct LockedFeatureCard: View {
    let feature: Feature
    @State private var showingPaywall = false

    var body: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: feature.symbol, tint: .purple, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(feature.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        StatusBadge(text: "Plus", symbol: "sparkles", tint: .purple)
                    }
                    Text(feature.summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 22, tint: .purple)
        .sheet(isPresented: $showingPaywall) { PaywallView(feature: feature) }
    }
}

/// Wraps an action that needs a Plus feature. If the feature is off, the paywall appears
/// instead of the action. The one place UI code checks entitlements.
struct PlusGate<Content: View>: View {
    let feature: Feature
    let action: () -> Void
    @ViewBuilder var label: Content
    @State private var showingPaywall = false
    @State private var entitlements = EntitlementService.shared

    var body: some View {
        Button {
            if entitlements.hasFeature(feature) { action() } else { showingPaywall = true }
        } label: {
            HStack(spacing: 6) {
                label
                if !entitlements.hasFeature(feature) {
                    Image(systemName: "sparkles").font(.caption).foregroundStyle(.purple)
                }
            }
        }
        .sheet(isPresented: $showingPaywall) { PaywallView(feature: feature) }
    }
}
