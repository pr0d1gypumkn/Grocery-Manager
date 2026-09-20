import SwiftData
import SwiftUI

struct InventoryDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ingredient.expiryDate) private var ingredients: [Ingredient]
    @State private var notificationMessage: String?

    private var viewModel: InventoryViewModel { InventoryViewModel(modelContext: modelContext) }

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Total items", value: "\(ingredients.count)")
                LabeledContent("Expiring within 3 days", value: "\(expiringSoonCount)")
            }

            Section("Expiry watch") {
                if ingredients.isEmpty {
                    ContentUnavailableView("No inventory yet", systemImage: "cart.badge.plus", description: Text("Add groceries from a storage location."))
                } else {
                    ForEach(ingredients) { ingredient in
                        NavigationLink {
                            IngredientFormView(ingredient: ingredient, defaultLocation: ingredient.location)
                        } label: {
                            IngredientRow(ingredient: ingredient, state: viewModel.expiryState(for: ingredient.expiryDate))
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { ingredients[$0] }.forEach(viewModel.delete)
                    }
                }
            }
        }
        .navigationTitle("Inventory")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        do {
                            let manager = NotificationManager.shared
                            guard try await manager.requestAuthorization() else {
                                notificationMessage = "Notifications are disabled in Settings."
                                return
                            }
                            try await manager.scheduleExpiryNotifications(for: ingredients)
                            notificationMessage = "Expiry alerts are scheduled."
                        } catch {
                            notificationMessage = "Could not schedule expiry alerts."
                        }
                    }
                } label: {
                    Label("Enable expiry alerts", systemImage: "bell.badge")
                }
            }
        }
        .alert("Expiry Alerts", isPresented: Binding(
            get: { notificationMessage != nil },
            set: { if !$0 { notificationMessage = nil } }
        )) {
            Button("OK") { notificationMessage = nil }
        } message: {
            Text(notificationMessage ?? "")
        }
    }

    private var expiringSoonCount: Int {
        ingredients.filter { viewModel.expiryState(for: $0.expiryDate) != .fresh }.count
    }
}

private struct IngredientRow: View {
    let ingredient: Ingredient
    let state: InventoryViewModel.ExpiryState

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(state.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.headline)
                Text("\(ingredient.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit) · \(ingredient.category)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: remainingProgress)
                    .tint(replenishmentColor)
                Text(usageLabel)
                    .font(.caption)
                    .foregroundStyle(replenishmentColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(ingredient.expiryDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                Text(state.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.color)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var baselineQuantity: Double {
        max(ingredient.initialQuantity, ingredient.quantity, 0.0001)
    }

    private var remainingProgress: Double {
        min(max(ingredient.quantity / baselineQuantity, 0), 1)
    }

    private var usedQuantity: Double {
        max(baselineQuantity - ingredient.quantity, 0)
    }

    private var shouldReplenish: Bool {
        let threshold = ingredient.reorderThreshold > 0
            ? ingredient.reorderThreshold
            : baselineQuantity * 0.2
        return ingredient.quantity <= threshold
    }

    private var replenishmentColor: Color {
        shouldReplenish ? .orange : .secondary
    }

    private var usageLabel: String {
        let used = usedQuantity.formatted(.number.precision(.fractionLength(0...2)))
        let starting = baselineQuantity.formatted(.number.precision(.fractionLength(0...2)))
        return shouldReplenish
            ? "Used \(used) \(ingredient.unit) of \(starting) · Replenish soon"
            : "Used \(used) \(ingredient.unit) of \(starting)"
    }
}

private extension InventoryViewModel.ExpiryState {
    var color: Color {
        switch self {
        case .fresh: .green
        case .soon: .yellow
        case .expired: .red
        }
    }
}

