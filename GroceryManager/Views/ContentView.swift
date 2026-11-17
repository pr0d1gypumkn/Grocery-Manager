import SwiftData
import SwiftUI

struct ContentView: View {
    enum AppTab: Hashable {
        case plan, stock, storage, recipes, groceries
    }

    @State private var selection: AppTab = .plan
    @Query(filter: #Predicate<GroceryItem> { !$0.isChecked }) private var pendingGroceries: [GroceryItem]

    var body: some View {
        TabView(selection: $selection) {
            Tab("Plan", systemImage: "calendar", value: .plan) {
                NavigationStack { MealPlanView() }
            }

            Tab("Stock", systemImage: "chart.bar.fill", value: .stock) {
                NavigationStack { InventoryDashboardView() }
            }

            Tab("Storage", systemImage: "refrigerator.fill", value: .storage) {
                NavigationStack { LocationListView() }
            }

            Tab("Recipes", systemImage: "book.pages.fill", value: .recipes) {
                NavigationStack { RecipeListView() }
            }

            Tab("Groceries", systemImage: "cart.fill", value: .groceries) {
                NavigationStack { GroceryListView() }
            }
            .badge(pendingGroceries.count)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [MealPlanEntry.self, Recipe.self, Ingredient.self, GroceryItem.self, StorageLocation.self], inMemory: true)
}
