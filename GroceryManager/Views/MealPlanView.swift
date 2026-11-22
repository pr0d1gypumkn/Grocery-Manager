import SwiftData
import SwiftUI

struct MealPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealPlanEntry.date) private var allEntries: [MealPlanEntry]
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @Query private var recipes: [Recipe]
    @Query private var households: [Household]

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var addMealContext: AddMealContext?
    @State private var toast: String?
    @State private var showingPrepIdeas = false
    @State private var showingPrepSession = false
    @State private var showingSettings = false
    @State private var showingAutoPlan = false
    @State private var relocation: Relocation?
    @State private var settings = AppSettings.shared
    @State private var entitlements = EntitlementService.shared
    @Namespace private var dayNamespace

    private var viewModel: MealPlanViewModel { MealPlanViewModel(modelContext: modelContext) }
    private var calendar: Calendar { .current }
    private var week: [Date] { selectedDate.weekDays }

    private var weekEntries: [MealPlanEntry] {
        guard let first = week.first, let last = week.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        return allEntries.filter { $0.date >= first && $0.date < end }
    }

    private var dayEntries: [MealPlanEntry] {
        weekEntries.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var weekShortfalls: [PlannedGroceryLine] {
        GroceryListBuilder().lines(for: weekEntries, inventory: inventory)
    }

    /// Changes whenever anything that affects the grocery list changes.
    private var planSignature: String {
        let plan = weekEntries.map { "\($0.persistentModelID.hashValue):\($0.servings):\($0.isCooked):\($0.batch != nil)" }.joined(separator: ",")
        let stock = inventory.reduce(into: Hasher()) { $0.combine($1.name); $0.combine($1.quantity); $0.combine($1.unit) }.finalize()
        return "\(week.first?.timeIntervalSince1970 ?? 0)|\(plan)|\(stock)|\(settings.autoBuildGroceryList)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                weekStrip
                weekSummary
                if weekEntries.count < 3 && recipes.count >= 3 {
                    autoPlanCard
                }
                if weekEntries.contains(where: { !$0.isCooked && $0.batch == nil }) {
                    prepSessionCard
                } else if recipes.count >= 2 && weekEntries.count < 3 {
                    prepPrompt
                }
                ForEach(MealType.allCases) { mealType in
                    mealSection(mealType)
                }
                dayNutrition
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.smooth, value: selectedDate)
        }
        .scrollIndicators(.hidden)
        .background { AmbientBackground(tint: .indigo) }
        .navigationTitle("Meal Plan")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Previous week", systemImage: "chevron.left") { shiftWeek(by: -1) }
                Button("Next week", systemImage: "chevron.right") { shiftWeek(by: 1) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Today", systemImage: "calendar") {
                        withAnimation(.smooth) { selectedDate = calendar.startOfDay(for: .now) }
                    }
                    Button("Prep ideas", systemImage: "square.stack.3d.up.fill") { showingPrepIdeas = true }
                    PlusGate(feature: .automaticPlanning, action: { showingAutoPlan = true }) {
                        Label("Plan my week for me", systemImage: "wand.and.stars")
                    }
                    Button("Copy last week's plan here", systemImage: "doc.on.doc") { copyLastWeek() }
                    if !settings.autoBuildGroceryList {
                        Button("Add missing to Groceries", systemImage: "cart.badge.plus") {
                            let count = viewModel.addShortfallsToGroceries(for: weekEntries, inventory: inventory)
                            withAnimation { toast = "Added \(count) item\(count == 1 ? "" : "s") to Groceries" }
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Plan a meal", systemImage: "plus") {
                    addMealContext = AddMealContext(date: selectedDate, mealType: .dinner)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .sheet(item: $addMealContext) { context in
            AddMealView(date: context.date, mealType: context.mealType, recipe: context.recipe, weekEntries: weekEntries)
        }
        .sheet(isPresented: $showingPrepIdeas) {
            MealPrepView(startDate: selectedDate)
        }
        .sheet(isPresented: $showingPrepSession) {
            PrepSessionView(weekStart: week.first ?? selectedDate, entries: weekEntries)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingAutoPlan) {
            AutoPlanView(weekStart: week.first ?? selectedDate, existing: weekEntries)
        }
        .sheet(item: $relocation) { relocation in
            RelocateMealView(relocation: relocation) { date, mealType in
                switch relocation.kind {
                case .move: viewModel.move(relocation.entry, to: date, mealType: mealType)
                case .copy: viewModel.copy(relocation.entry, to: date, mealType: mealType)
                }
                withAnimation { toast = relocation.kind == .move ? "Moved" : "Copied" }
            }
        }
        .task(id: planSignature) {
            guard settings.autoBuildGroceryList, let weekStart = week.first else { return }
            GroceryListBuilder().sync(weekStart: weekStart, entries: weekEntries, inventory: inventory, modelContext: modelContext)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.toast = nil }
                    }
            }
        }
        .sensoryFeedback(.success, trigger: toast) { _, new in new != nil }
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(week, id: \.self) { day in
                    dayButton(day)
                }
            }
        }
        .padding(.top, 4)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let mealCount = weekEntries.filter { calendar.isDate($0.date, inSameDayAs: day) }.count

        return Button {
            withAnimation(.bouncy) { selectedDate = day }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.body.weight(isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                HStack(spacing: 2) {
                    ForEach(0..<min(mealCount, 3), id: \.self) { _ in
                        Circle().frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
                .foregroundStyle(isSelected ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 18)
        )
        .glassEffectID(day, in: dayNamespace)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityValue("\(mealCount) meals planned")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first, let entry = allEntries.first(where: { "\($0.persistentModelID.hashValue)" == id }) else { return false }
            viewModel.move(entry, to: day)
            withAnimation { toast = "Moved to \(day.formatted(.dateTime.weekday(.wide)))" }
            return true
        }
    }

    // MARK: - Summary

    private var weekSummary: some View {
        let missing = weekShortfalls
        let planned = weekEntries.count
        let cooked = weekEntries.filter(\.isCooked).count

        return VStack(alignment: .leading, spacing: 14) {
            GlassStatRow {
                GlassStatTile(title: "Planned", value: "\(planned)", symbol: "calendar", tint: .indigo)
                GlassStatTile(title: "Cooked", value: "\(cooked)", symbol: "frying.pan.fill", tint: .orange)
                GlassStatTile(
                    title: "To buy",
                    value: "\(missing.count)",
                    symbol: missing.isEmpty ? "checkmark.seal.fill" : "cart.fill",
                    tint: missing.isEmpty ? .green : .pink
                )
            }

            if planned > 0 {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(missing.isEmpty ? "You're stocked for the week" : "Missing for this week")
                            .font(.subheadline.weight(.semibold))
                        Text(missing.isEmpty
                             ? "Every planned meal can be made from what you have."
                             : missing.prefix(4).map(\.name).joined(separator: ", ")
                                + (missing.count > 4 ? " +\(missing.count - 4) more" : "")
                                + (settings.autoBuildGroceryList ? " · already on your list" : ""))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if !missing.isEmpty, !settings.autoBuildGroceryList {
                        Button {
                            let count = viewModel.addShortfallsToGroceries(for: weekEntries, inventory: inventory)
                            withAnimation { toast = "Added \(count) item\(count == 1 ? "" : "s") to Groceries" }
                        } label: {
                            Label("Add to list", systemImage: "cart.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.pink)
                    }
                }
                .glassCard(cornerRadius: 22)
            }
        }
    }

    // MARK: - Meal prep

    private var prepPrompt: some View {
        Button {
            showingPrepIdeas = true
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: "square.stack.3d.up.fill", tint: .green, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prep a varied week in one go")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Find recipes that share ingredients and steps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 22, tint: .green)
    }

    @ViewBuilder
    private var autoPlanCard: some View {
        if entitlements.hasFeature(.automaticPlanning) {
            Button {
                showingAutoPlan = true
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: "wand.and.stars", tint: .purple, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan this week for me")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("From your recipes, pantry and household. Swap any meal.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassCard(cornerRadius: 22, tint: .purple)
        } else {
            LockedFeatureCard(feature: .automaticPlanning)
        }
    }

    private var prepSessionCard: some View {
        let pending = weekEntries.filter { !$0.isCooked && $0.batch == nil }
        let recipeCount = Set(pending.compactMap { $0.recipe?.name }).count
        return Button {
            showingPrepSession = true
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: "flame.fill", tint: .green, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch-cook this week in one session")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(recipeCount) recipe\(recipeCount == 1 ? "" : "s"), ordered with timers, then portioned into containers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 22, tint: .green)
    }

    // MARK: - Meals

    private func mealSection(_ mealType: MealType) -> some View {
        let entries = dayEntries.filter { $0.mealType == mealType }

        return VStack(alignment: .leading, spacing: 10) {
            Label(mealType.rawValue, systemImage: mealType.symbol)
                .font(.headline)
                .foregroundStyle(mealType.tint)
                .symbolRenderingMode(.hierarchical)

            ForEach(entries) { entry in
                MealCard(
                    entry: entry,
                    inventory: inventory,
                    onCook: { cook(entry) },
                    onUndoCook: { viewModel.markNotCooked(entry) },
                    onMoveToTomorrow: {
                        if let next = calendar.date(byAdding: .day, value: 1, to: entry.date) {
                            viewModel.move(entry, to: next)
                        }
                    },
                    onMove: { relocation = Relocation(entry: entry, kind: .move) },
                    onCopy: { relocation = Relocation(entry: entry, kind: .copy) },
                    onRepeat: {
                        viewModel.repeatWeekly(entry, weeks: 4)
                        withAnimation { toast = "Repeats for the next 4 weeks" }
                    },
                    onDelete: { viewModel.delete(entry) }
                )
                .draggable("\(entry.persistentModelID.hashValue)")
            }

            Button {
                addMealContext = AddMealContext(date: selectedDate, mealType: mealType)
            } label: {
                Label("Add \(mealType.rawValue.lowercased())", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var dayNutrition: some View {
        let facts = dayEntries.compactMap(\.nutrition)
        if !facts.isEmpty {
            let total = facts.reduce(NutritionFacts.zero, +)
            let perPerson = total / max(households.first?.servingsPerMeal ?? Double(dayEntries.first?.servings ?? 1), 1)
            VStack(alignment: .leading, spacing: 8) {
                Label("Nutrition for \(selectedDate.formatted(.dateTime.weekday(.wide)))", systemImage: "chart.pie.fill")
                    .font(.subheadline.weight(.semibold))
                NutritionRow(facts: perPerson)
                Text("Per person, across \(facts.count) planned meal\(facts.count == 1 ? "" : "s"). Estimated where the recipe doesn't declare values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 22)
        }
    }

    private func cook(_ entry: MealPlanEntry) {
        let shortfalls = viewModel.markCooked(entry, inventory: inventory)
        withAnimation {
            toast = entry.batch != nil
                ? "Enjoy the leftovers"
                : (shortfalls.isEmpty
                    ? "Stock updated for \(entry.recipe?.name ?? "meal")"
                    : "Cooked — short on \(shortfalls.joined(separator: ", "))")
        }
    }

    private func shiftWeek(by weeks: Int) {
        if let date = calendar.date(byAdding: .weekOfYear, value: weeks, to: selectedDate) {
            withAnimation(.smooth) { selectedDate = calendar.startOfDay(for: date) }
        }
    }

    private func copyLastWeek() {
        guard let thisWeek = week.first, let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek) else { return }
        let count = viewModel.copyWeek(from: lastWeek, to: thisWeek, allEntries: allEntries)
        withAnimation { toast = count == 0 ? "Nothing new to copy" : "Copied \(count) meal\(count == 1 ? "" : "s")" }
    }
}

struct AddMealContext: Identifiable {
    let id = UUID()
    var date: Date
    var mealType: MealType
    var recipe: Recipe?
}

struct Relocation: Identifiable {
    enum Kind { case move, copy }
    let id = UUID()
    let entry: MealPlanEntry
    let kind: Kind
}

/// Compact calories/macros strip.
struct NutritionRow: View {
    let facts: NutritionFacts

    var body: some View {
        HStack(spacing: 10) {
            metric("kcal", facts.calories, tint: .orange)
            metric("protein", facts.protein, tint: .red, suffix: "g")
            metric("carbs", facts.carbs, tint: .yellow, suffix: "g")
            metric("fat", facts.fat, tint: .blue, suffix: "g")
        }
    }

    private func metric(_ title: String, _ value: Double, tint: Color, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(value.rounded()))\(suffix)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

// MARK: - Meal card

private struct MealCard: View {
    let entry: MealPlanEntry
    let inventory: [Ingredient]
    let onCook: () -> Void
    let onUndoCook: () -> Void
    let onMoveToTomorrow: () -> Void
    let onMove: () -> Void
    let onCopy: () -> Void
    let onRepeat: () -> Void
    let onDelete: () -> Void

    private var missing: [PantryMatch] {
        guard entry.batch == nil else { return [] }
        return PantryMatcher()
            .matches(requirements: MealPlanViewModel.requirements(for: [entry]), inventory: inventory)
            .filter { !$0.isInStock }
    }

    var body: some View {
        HStack(spacing: 14) {
            NavigationLink {
                if let recipe = entry.recipe {
                    RecipeDetailView(recipe: recipe, servings: entry.servings)
                }
            } label: {
                HStack(spacing: 14) {
                    IconTile(symbol: entry.batch != nil ? "takeoutbag.and.cup.and.straw.fill" : entry.mealType.symbol, tint: entry.mealType.tint, size: 42)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.recipe?.name ?? "Deleted recipe")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(entry.isCooked ? .secondary : .primary)
                            .strikethrough(entry.isCooked, color: .secondary)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Label("\(entry.servings)", systemImage: "person.2.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let facts = entry.recipe?.nutritionPerServing {
                                Text("\(Int(facts.calories.rounded())) kcal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            statusBadge
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button {
                entry.isCooked ? onUndoCook() : onCook()
            } label: {
                Image(systemName: entry.isCooked ? "checkmark" : (entry.batch != nil ? "fork.knife" : "frying.pan"))
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .tint(entry.isCooked ? .green : nil)
            .accessibilityLabel(entry.isCooked ? "Mark as not cooked" : "Mark as cooked and use stock")
        }
        .glassCard(cornerRadius: 22)
        .contextMenu {
            if entry.isCooked {
                Button("Mark as not cooked", systemImage: "arrow.uturn.backward", action: onUndoCook)
            } else {
                Button(entry.batch != nil ? "Eat leftovers" : "Cook & use stock", systemImage: "frying.pan", action: onCook)
            }
            Divider()
            Button("Move to tomorrow", systemImage: "calendar.badge.plus", action: onMoveToTomorrow)
            Button("Move to…", systemImage: "arrow.right.circle", action: onMove)
            Button("Copy to…", systemImage: "doc.on.doc", action: onCopy)
            Button("Repeat weekly (4 weeks)", systemImage: "repeat", action: onRepeat)
            Divider()
            Button("Remove from plan", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if entry.isCooked {
            StatusBadge(text: entry.batch != nil ? "Eaten" : "Cooked", symbol: "checkmark", tint: .green)
        } else if entry.batch != nil {
            StatusBadge(text: "Leftovers", symbol: "takeoutbag.and.cup.and.straw", tint: .teal)
        } else if missing.isEmpty {
            StatusBadge(text: "Ready", symbol: "checkmark.circle.fill", tint: .green)
        } else {
            StatusBadge(text: "Missing \(missing.count)", symbol: "cart", tint: .orange)
        }
    }
}

// MARK: - Move / copy

struct RelocateMealView: View {
    @Environment(\.dismiss) private var dismiss
    let relocation: Relocation
    let onConfirm: (Date, MealType) -> Void

    @State private var date: Date
    @State private var mealType: MealType

    init(relocation: Relocation, onConfirm: @escaping (Date, MealType) -> Void) {
        self.relocation = relocation
        self.onConfirm = onConfirm
        _date = State(initialValue: Calendar.current.date(byAdding: .day, value: 1, to: relocation.entry.date) ?? relocation.entry.date)
        _mealType = State(initialValue: relocation.entry.mealType)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Day", selection: $date, displayedComponents: .date)
                Picker("Meal", selection: $mealType) {
                    ForEach(MealType.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle(relocation.kind == .move ? "Move meal" : "Copy meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(relocation.kind == .move ? "Move" : "Copy") {
                        onConfirm(date, mealType)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Add meal

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @Query private var households: [Household]

    @State private var date: Date
    @State private var mealType: MealType
    @State private var selectedRecipe: Recipe?
    @State private var servings: Int
    @State private var searchText = ""
    @State private var showingNewRecipe = false
    @State private var didSetDefaultServings = false

    /// Meals already planned this week, used to favour recipes that share ingredients.
    var weekEntries: [MealPlanEntry] = []

    init(date: Date, mealType: MealType, recipe: Recipe? = nil, weekEntries: [MealPlanEntry] = []) {
        _date = State(initialValue: date)
        _mealType = State(initialValue: mealType)
        _selectedRecipe = State(initialValue: recipe)
        _servings = State(initialValue: recipe?.servings ?? 2)
        self.weekEntries = weekEntries
    }

    /// Non-staple ingredient keys already in the week's plan.
    private var weekIngredientKeys: Set<String> {
        Set(weekEntries.compactMap(\.recipe).flatMap { recipe in
            recipe.ingredients.map(\.name).filter { !PrepStaples.isStaple($0) }.map(IngredientNameMatcher.key)
        })
    }

    private func overlap(_ recipe: Recipe) -> [String] {
        let keys = weekIngredientKeys
        guard !keys.isEmpty else { return [] }
        var seen: Set<String> = []
        return recipe.ingredients.compactMap { ingredient in
            let key = IngredientNameMatcher.key(ingredient.name)
            guard keys.contains(key), !PrepStaples.isStaple(ingredient.name), seen.insert(key).inserted else { return nil }
            return ingredient.name
        }
    }

    private var filteredRecipes: [Recipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = query.isEmpty ? recipes : recipes.filter { $0.name.localizedCaseInsensitiveContains(query) }
        guard query.isEmpty, !weekIngredientKeys.isEmpty else { return base }
        return base.sorted { overlap($0).count > overlap($1).count }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                    Stepper(value: $servings, in: 1...24) {
                        LabeledContent("Servings", value: "\(servings)")
                    }
                }

                Section {
                    if recipes.isEmpty {
                        ContentUnavailableView {
                            Label("No recipes yet", systemImage: "book.closed")
                        } description: {
                            Text("Create a recipe to start planning meals.")
                        } actions: {
                            Button("New Recipe") { showingNewRecipe = true }
                                .buttonStyle(.glassProminent)
                        }
                    } else {
                        ForEach(filteredRecipes) { recipe in
                            recipeRow(recipe)
                        }
                    }
                } header: {
                    Text("Recipe")
                } footer: {
                    if !weekIngredientKeys.isEmpty {
                        Text("Recipes that share ingredients with this week's plan are listed first. Sharing cuts cost and waste.")
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search recipes")
            .navigationTitle("Plan a Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark", role: .confirm) {
                        guard let selectedRecipe else { return }
                        MealPlanViewModel(modelContext: modelContext)
                            .addMeal(recipe: selectedRecipe, on: date, mealType: mealType, servings: servings)
                        dismiss()
                    }
                    .disabled(selectedRecipe == nil)
                }
            }
            .sheet(isPresented: $showingNewRecipe) {
                RecipeFormView()
            }
            .task {
                guard !didSetDefaultServings, let household = households.first, !household.members.isEmpty else { return }
                didSetDefaultServings = true
                servings = max(Int(household.servingsPerMeal.rounded(.up)), 1)
            }
        }
        .presentationDetents([.large])
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        let isSelected = selectedRecipe == recipe
        let scale = recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1
        let missing = PantryMatcher()
            .matches(
                requirements: recipe.ingredients.map {
                    IngredientRequirement(name: $0.name, quantity: $0.requiredQuantity * scale, unit: $0.unit)
                },
                inventory: inventory
            )
            .filter { !$0.isInStock }
        let shared = overlap(recipe)

        return Button {
            withAnimation(.snappy) {
                selectedRecipe = recipe
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text("\(recipe.ingredients.count) ingredients · serves \(recipe.servings)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if missing.isEmpty {
                            StatusBadge(text: "In stock", tint: .green)
                        } else {
                            StatusBadge(text: "Missing \(missing.count)", tint: .orange)
                        }
                        if !shared.isEmpty {
                            StatusBadge(text: "Shares \(shared.count)", symbol: "link", tint: .indigo)
                        }
                    }
                    if !shared.isEmpty {
                        Text("Uses \(shared.prefix(3).joined(separator: ", ")) already on the plan")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack { MealPlanView() }
        .modelContainer(try! PersistenceController.makeInMemoryContainer())
}
