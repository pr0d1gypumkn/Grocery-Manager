import StoreKit
import SwiftUI

/// A gentle upgrade sheet: explains what the feature does, lists the plan, and offers the
/// two subscriptions. Dismissing it never blocks anything the free tier includes.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = SubscriptionStore.shared
    @State private var entitlements = EntitlementService.shared
    @State private var isPurchasing = false
    @State private var showingPrivacy = false

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
            .sheet(isPresented: $showingPrivacy) { PrivacyPolicyView() }
            .onChange(of: entitlements.isPlus) { _, isPlus in
                if isPlus { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(symbol: feature?.symbol ?? "sparkles", tint: .purple, size: 52)
            Text(feature?.summary ?? "A week planned for you, new recipe ideas, social and photo import, and more.")
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
            ForEach(Feature.available) { item in
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
                Text(store.purchaseError ?? "Check your connection and try again.")
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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.displayName.isEmpty ? (product.id.hasSuffix("yearly") ? "Yearly" : "Monthly") : product.displayName)
                        .font(.headline)
                        .foregroundStyle(prominent ? .white : .primary)
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(prominent ? .white.opacity(0.85) : .secondary)
                    if let trial = Self.trialText(product) {
                        Text(trial)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(prominent ? .white : .purple)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(product.displayPrice)\(Self.periodSuffix(product))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(prominent ? .white : .primary)
                    if let badge {
                        StatusBadge(text: badge, tint: prominent ? .white : .green)
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .buttonStyle(.glass(prominent ? .regular.tint(.purple).interactive() : .regular.interactive()))
        // Rounded corners like the cards above; a capsule pinches two-line text at the ends.
        .buttonBorderShape(.roundedRectangle(radius: 22))
        .disabled(isPurchasing)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.purchaseError, !store.products.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button("Restore purchases") { Task { await store.restore() } }
                .font(.footnote)
            Text("Payment is charged to your Apple Account when you confirm. The subscription renews automatically at the same price for each period unless you cancel at least 24 hours before it ends. You can manage or cancel it in your Apple Account settings. If it lapses, nothing is deleted; only Plus features pause.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: LegalLinks.termsOfUse)
                Button("Privacy Policy") { showingPrivacy = true }
            }
            .font(.caption)
        }
    }

    /// " / month", " / year", " / 3 months".
    static func periodSuffix(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        return " / " + periodText(period)
    }

    static func periodText(_ period: Product.SubscriptionPeriod) -> String {
        let unit: String = switch period.unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    /// "1 week free, then billed" style intro offer text, when the plan has one.
    static func trialText(_ product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer else { return nil }
        let length = periodText(offer.period)
        switch offer.paymentMode {
        case .freeTrial: return "Free for \(offer.periodCount > 1 ? "\(offer.periodCount) \(length)s" : "1 \(length)"), then \(product.displayPrice)\(periodSuffix(product))"
        default: return "Intro price \(offer.displayPrice) / \(length)"
        }
    }
}

/// Links required on every subscription screen (App Review Guideline 3.1.2).
enum LegalLinks {
    /// Apple's standard EULA. Swap for your own terms URL if you publish one.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// The privacy policy, shown in-app. Keep in sync with PRIVACY.md, which is the public copy
/// you host and enter as the Privacy Policy URL in App Store Connect.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Last updated November 21, 2026").font(.caption).foregroundStyle(.secondary)
                    section("The short version", "Mealy works without an account. Your recipes, meal plans, grocery lists and pantry stay on your device and in your own iCloud. We don't sell your data, show ads, or track you across apps or websites.")
                    section("Data on your device and in iCloud", "Everything you add is stored on your device. If iCloud is on, Apple syncs it through your private iCloud database so it appears on your other devices. We can't read your iCloud data.")
                    section("Photos", "When you import a recipe from a photo, the text is read on your device. The photo isn't uploaded or kept.")
                    section("Recipe links", "When you import a recipe from a web, TikTok, Instagram or YouTube link, the app downloads that page to read the recipe from it.")
                    section("Your Apple ID and household sharing", "Some Plus features, such as household sharing, use our server. There's no separate Mealy account: if you subscribe, your App Store purchase identifies you, and if you join someone's household you use Sign in with Apple. We store an anonymous Apple user ID, your subscription status, your email only if you choose to share it with Sign in with Apple, and the household data you share, only to provide those features. You can delete this at any time in Settings ▸ Account.")
                    section("Requests to our server", "While you're signed in, a few Plus features ask our server for help: recipe ideas send the names of your saved recipes, pantry items and diet preferences, and social import sends the post's link. These are used only to answer that request and aren't stored.")
                    section("Purchases", "Subscriptions are handled by Apple. We receive a signed confirmation of your subscription from Apple, never your payment details.")
                    section("Notifications", "Expiry reminders are scheduled on your device. Nothing about them is sent to us.")
                    section("Children", "Mealy isn't directed at children under 13, and we don't knowingly collect their personal information.")
                    section("Changes and contact", "If this policy changes, we'll update the date above. Questions? Use the support link on the App Store page.")
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .close) { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// A card that explains a Plus feature and offers the upgrade, for places where the free
/// experience simply continues without it.
struct LockedFeatureCard: View {
    let feature: Feature
    @State private var showingPaywall = false

    var body: some View {
        if feature.isAvailable { card }
    }

    private var card: some View {
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
