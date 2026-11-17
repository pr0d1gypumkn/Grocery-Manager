import SwiftData
import SwiftUI

/// Runs one batch-cooking session for a week's plan: steps grouped by what can happen at
/// the same time, with timers, then portions everything into tracked containers.
struct PrepSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]
    @Query private var households: [Household]

    let weekStart: Date
    let entries: [MealPlanEntry]

    @State private var session: PrepSession?
    @State private var plan: PrepPlan?
    @State private var completed: Set<String> = []
    @State private var timers = PrepTimers()
    @State private var showingPortions = false
    @State private var toast: String?

    private var includedEntries: [MealPlanEntry] {
        entries.filter { !$0.isCooked && $0.batch == nil && $0.recipe != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let plan {
                        summary(plan)
                        ForEach(Array(plan.groups.enumerated()), id: \.offset) { index, group in
                            groupCard(index: index, steps: group)
                        }
                        finishButton(plan)
                    } else if includedEntries.isEmpty {
                        ContentUnavailableView("Nothing to prep", systemImage: "calendar.badge.exclamationmark", description: Text("Plan a few meals this week first."))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background { AmbientBackground(tint: .green) }
            .navigationTitle("Prep session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
            .task { buildPlan() }
            .sheet(isPresented: $showingPortions) {
                if let session, let plan {
                    PortionSheet(session: session, plan: plan, entries: includedEntries, inventory: inventory, locations: locations, household: households.first) { result in
                        toast = result
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 12)
                        .task(id: toast) { try? await Task.sleep(for: .seconds(2.5)); withAnimation { self.toast = nil } }
                }
            }
        }
    }

    // MARK: Building

    private func buildPlan() {
        let existing = ((try? modelContext.fetch(FetchDescriptor<PrepSession>())) ?? [])
            .first { Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart) && !$0.isCompleted }
        if let existing, let storedPlan = existing.plan, !storedPlan.steps.isEmpty {
            session = existing
            plan = storedPlan
            completed = Set(existing.completedStepIDs)
            return
        }
        let inputs = PrepSessionPlanner.inputs(for: includedEntries)
        guard !inputs.isEmpty else { return }
        let newPlan = PrepSessionPlanner().plan(inputs)
        let newSession = PrepSession(weekStart: weekStart, title: "Prep for week of \(weekStart.formatted(.dateTime.month().day()))", plan: newPlan)
        modelContext.insert(newSession)
        try? modelContext.save()
        session = newSession
        plan = newPlan
    }

    // MARK: Sections

    private func summary(_ plan: PrepPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassStatRow {
                GlassStatTile(title: "Recipes", value: "\(plan.recipes.count)", symbol: "book.pages.fill", tint: .orange)
                GlassStatTile(title: "Steps", value: "\(completed.count)/\(plan.steps.count)", symbol: "checklist", tint: .green)
                GlassStatTile(title: "About", value: minutesText(plan.estimatedMinutes), symbol: "clock.fill", tint: .indigo)
            }
            Text(plan.recipes.map { "\($0.name) ×\($0.servings)" }.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(completed.count), total: Double(max(plan.steps.count, 1)))
                .tint(.green)
        }
    }

    private func groupCard(index: Int, steps: [PrepStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(steps.count > 1 ? "At the same time" : "Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("Step \(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ForEach(steps) { step in
                stepRow(step)
                if step.id != steps.last?.id { Divider() }
            }
        }
        .glassCard(cornerRadius: 22)
        .opacity(steps.allSatisfy { completed.contains($0.id) } ? 0.55 : 1)
    }

    private func stepRow(_ step: PrepStep) -> some View {
        let done = completed.contains(step.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                toggle(step)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.body)
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
                if !step.detail.isEmpty {
                    Text(step.detail).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    StatusBadge(text: step.lane.title, symbol: step.lane.symbol, tint: laneTint(step.lane))
                    Text(step.recipeNames.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let minutes = step.timerMinutes {
                    timerControl(step, minutes: minutes)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func timerControl(_ step: PrepStep, minutes: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let end = timers.endDates[step.id] {
                let remaining = max(end.timeIntervalSince(context.date), 0)
                HStack(spacing: 10) {
                    Image(systemName: remaining == 0 ? "bell.fill" : "timer")
                        .foregroundStyle(remaining == 0 ? .orange : .green)
                    Text(remaining == 0 ? "Done" : countdown(remaining))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Button("Stop") { timers.stop(step.id) }
                        .font(.caption)
                        .buttonStyle(.glass)
                }
            } else {
                Button {
                    timers.start(step.id, title: step.title, minutes: minutes)
                } label: {
                    Label("Start \(minutes) min timer", systemImage: "timer")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(.green)
            }
        }
    }

    private func finishButton(_ plan: PrepPlan) -> some View {
        VStack(spacing: 8) {
            Button {
                showingPortions = true
            } label: {
                Label("Portion & store", systemImage: "tray.and.arrow.down.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
            Text("Takes the ingredients out of stock once, tracks the containers as stock, and points this week's meals at them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: Helpers

    private func toggle(_ step: PrepStep) {
        withAnimation(.snappy) {
            if completed.contains(step.id) { completed.remove(step.id) } else { completed.insert(step.id) }
        }
        session?.completedStepIDs = Array(completed)
        try? modelContext.save()
    }

    private func laneTint(_ lane: PrepLane) -> Color {
        switch lane {
        case .prep: .green
        case .stove: .orange
        case .oven: .red
        case .passive: .indigo
        case .assemble: .teal
        }
    }

    private func minutesText(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Live countdowns for the session, backed by local notifications so they fire when the
/// app is in the background.
@MainActor
@Observable
final class PrepTimers {
    var endDates: [String: Date] = [:]

    func start(_ id: String, title: String, minutes: Int) {
        let seconds = TimeInterval(minutes * 60)
        endDates[id] = Date.now.addingTimeInterval(seconds)
        Task {
            _ = try? await NotificationManager.shared.requestAuthorization()
            await NotificationManager.shared.scheduleTimer(id: id, title: title, seconds: seconds)
        }
    }

    func stop(_ id: String) {
        endDates[id] = nil
        NotificationManager.shared.cancelTimer(id: id)
    }
}

// MARK: - Portions

private struct PortionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealPlanEntry.date) private var allEntries: [MealPlanEntry]

    let session: PrepSession
    let plan: PrepPlan
    let entries: [MealPlanEntry]
    let inventory: [Ingredient]
    let locations: [StorageLocation]
    let household: Household?
    let onFinish: (String) -> Void

    @State private var rows: [Row] = []
    @State private var scheduleLeftovers = true

    struct Row: Identifiable {
        let id = UUID()
        var recipe: Recipe
        var portions: Int
        var container: String
        var storage: BatchStorage
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.recipe.name).font(.headline)
                            Stepper(value: $row.portions, in: 1...40) {
                                LabeledContent("Portions", value: "\(row.portions)")
                            }
                            TextField("Container (e.g. 4 glass boxes)", text: $row.container)
                            Picker("Store in", selection: $row.storage) {
                                ForEach(BatchStorage.allCases) { storage in
                                    Label(storage.rawValue, systemImage: storage.symbol).tag(storage)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("What you made")
                } footer: {
                    Text("Fridge portions keep 4 days, freezer portions 90. They show up in Stock and expiry alerts like anything else.")
                }
                Section {
                    Toggle("Schedule extra portions as leftovers", isOn: $scheduleLeftovers)
                } footer: {
                    Text("Portions beyond this week's plan are put into empty lunch slots on the following days.")
                }
            }
            .navigationTitle("Portion & store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish", systemImage: "checkmark", role: .confirm) { finish() }
                }
            }
            .task { seedRows() }
        }
    }

    private func seedRows() {
        guard rows.isEmpty else { return }
        rows = plan.recipes.compactMap { summary in
            guard let recipe = entries.first(where: { $0.recipe?.name == summary.name })?.recipe else { return nil }
            return Row(recipe: recipe, portions: summary.servings, container: "", storage: recipe.tags.localizedCaseInsensitiveContains("freezer") ? .freezer : .fridge)
        }
    }

    private func finish() {
        let viewModel = MealPlanViewModel(modelContext: modelContext)
        let specs = rows.map { MealPlanViewModel.BatchSpec(recipe: $0.recipe, portions: $0.portions, container: $0.container, storage: $0.storage) }
        let shortfalls = viewModel.completePrepSession(session, specs: specs, entries: entries, inventory: inventory, locations: locations)
        var scheduled = 0
        if scheduleLeftovers {
            let perMeal = Int(household?.servingsPerMeal.rounded(.up) ?? 2)
            for batch in session.batches {
                scheduled += viewModel.scheduleLeftovers(from: batch, startingAfter: .now, mealType: .lunch, servingsPerMeal: perMeal, allEntries: allEntries)
            }
        }
        var message = "Stored \(rows.reduce(0) { $0 + $1.portions }) portions"
        if scheduled > 0 { message += ", scheduled \(scheduled) leftover meal\(scheduled == 1 ? "" : "s")" }
        if !shortfalls.isEmpty { message += " · short on \(shortfalls.prefix(3).joined(separator: ", "))" }
        onFinish(message)
        dismiss()
    }
}
