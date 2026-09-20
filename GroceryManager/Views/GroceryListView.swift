//
//  GroceryListView.swift
//  GroceryManager
//
//  Created by Ahmed Keshta on 9/15/26.
//

import SwiftData
import SwiftUI

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryItem.name) private var groceries: [GroceryItem]
    @State private var showingAddGrocery = false

    private var viewModel: GroceryViewModel { GroceryViewModel(modelContext: modelContext) }

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Total items", value: "\(groceries.count)")
            }

            Section("Grocery List") {
                if groceries.isEmpty {
                    ContentUnavailableView("No groceries yet", systemImage: "cart.badge.plus", description: Text("Add groceries from a storage location."))
                } else {
                    ForEach(groceries) { grocery in
                        NavigationLink {
                            GroceryFormView(groceries: grocery)
                        }
                        label: {
                            GroceryRow(grocery: grocery)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { groceries[$0] }.forEach(viewModel.delete)
                    }
                }
            }
        }
        .navigationTitle("Groceries")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddGrocery = true
                } label: {
                    Label("Add grocery", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddGrocery) {
            GroceryFormView()
        }
        
    }

}

private struct GroceryRow: View {
    let grocery: GroceryItem
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
//                .fill(state.color)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(grocery.name)
                    .font(.headline)
                Text("\(grocery.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(grocery.unit) · \(grocery.category)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
    
    
}
