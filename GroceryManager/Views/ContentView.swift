import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                InventoryDashboardView()
            }
            .tabItem {
                Label("Inventory", systemImage: "cart")
            }

            NavigationStack {
                LocationListView()
            }
            .tabItem {
                Label("Storage", systemImage: "archivebox")
            }

            NavigationStack {
                RecipeListView()
            }
            .tabItem {
                Label("Recipes", systemImage: "book")
            }
        }
    }
}

#Preview {
    ContentView()
}
