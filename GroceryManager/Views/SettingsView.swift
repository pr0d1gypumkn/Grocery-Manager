import AuthenticationServices
import StoreKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var households: [Household]
    @State private var settings = AppSettings.shared
    @State private var entitlements = EntitlementService.shared
    @State private var account = AccountSession.shared

    @State private var showingPaywall = false
    @State private var exportDocument: TransferDocument?
    @State private var showingImporter = false
    @State private var message: String?
    @State private var confirmingReset = false
    @State private var showingAccount = false
    @State private var showingManageSubscriptions = false
    @State private var showingPrivacy = false
    @State private var confirmingDeleteAccount = false
    @State private var isDeletingAccount = false

    var body: some View {
        NavigationStack {
            Form {
                planSection
                householdSection
                regionSection
                automationSection
                dataSection
                if APIClient.isConfigured { accountSection }
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .close) { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $showingAccount) { AccountView() }
            .sheet(isPresented: $showingPrivacy) { PrivacyPolicyView() }
            .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
            .confirmationDialog("Delete your Mealy account?", isPresented: $confirmingDeleteAccount, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { deleteAccount() }
            } message: {
                Text("This permanently deletes your account, your shared households you own, and the data synced to our server. Data on this device and in your iCloud stays. If you subscribed through the App Store, cancel it in your Apple Account settings too.")
            }
            .fileExporter(
                isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                document: exportDocument,
                contentType: exportDocument?.contentType ?? .json,
                defaultFilename: exportDocument?.fileName ?? "mealy-export"
            ) { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .commaSeparatedText, .data, .zip, .item]) { result in
                handleImport(result)
            }
            .alert("Settings", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
            .confirmationDialog("Replace everything with sample data?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Replace with sample data", role: .destructive) {
                    DemoData.wipe(modelContext)
                    DemoData.load(into: modelContext)
                    settings.didSeedDemoData = true
                    message = "Sample data loaded."
                }
            } message: {
                Text("This deletes your recipes, plan, list and stock on this device. Export first if you want to keep them.")
            }
        }
    }

    // MARK: Sections

    private var planSection: some View {
        Section {
            HStack {
                IconTile(symbol: entitlements.isPlus ? "sparkles" : "leaf.fill", tint: entitlements.isPlus ? .purple : .green, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entitlements.isPlus ? "Mealy Plus" : "Free plan").font(.headline)
                    Text(planDescription).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !entitlements.isPlus {
                    Button("Upgrade") { showingPaywall = true }
                        .buttonStyle(.glassProminent)
                        .tint(.purple)
                }
            }
            if entitlements.isPlus, entitlements.snapshot.source == .appStore {
                Button("Manage subscription", systemImage: "creditcard") { showingManageSubscriptions = true }
            }
            Button("Restore purchases", systemImage: "arrow.clockwise") {
                Task { await SubscriptionStore.shared.restore() }
            }
            #if DEBUG
            Toggle("Debug: unlock Plus features", isOn: Binding(
                get: { entitlements.debugOverride != nil },
                set: { entitlements.setDemoPlus($0) }
            ))
            #endif
        } header: {
            Text("Plan")
        }
    }

    private var planDescription: String {
        guard entitlements.isPlus else { return "Planning, recipes, groceries, pantry and prep are free, no account needed." }
        if let expires = entitlements.snapshot.expiresAt { return "Renews \(expires.formatted(date: .abbreviated, time: .omitted))" }
        return "Active"
    }

    @ViewBuilder
    private var householdSection: some View {
        Section {
            NavigationLink {
                HouseholdView()
            } label: {
                LabeledContent("Household", value: householdSummary)
            }
        } header: {
            Text("Who you cook for")
        } footer: {
            Text("Portion sizes per person set the default servings for planned meals.")
        }
    }

    private var householdSummary: String {
        guard let household = households.first, !household.members.isEmpty else { return "Not set" }
        return "\(household.members.count) people · \(household.servingsPerMeal.quantityText) servings"
    }

    private var regionSection: some View {
        Section("Region & units") {
            Picker("Region", selection: $settings.region) {
                ForEach(Region.allCases) { region in
                    Text("\(region.displayName) (\(region.currencyCode))").tag(region)
                }
            }
            Picker("Units", selection: $settings.unitSystem) {
                ForEach(UnitSystem.allCases) { system in
                    Text(system.displayName).tag(system)
                }
            }
            if Feature.priceAwareShopping.isAvailable {
                LabeledContent("Prices shown in", value: settings.currencyCode)
            }
            if entitlements.hasFeature(.recipeSuggestions) {
                TextField("Diet tags (vegetarian, nut-free…)", text: Binding(get: { settings.dietTags.joined(separator: ", ") }, set: { settings.dietTags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
            }
            if entitlements.hasFeature(.priceAwareShopping) {
                HStack {
                    Text("Weekly budget")
                    Spacer()
                    TextField("Off", value: Binding(
                        get: { Double(settings.weeklyBudgetCents) / 100 },
                        set: { settings.weeklyBudgetCents = Int(($0 * 100).rounded()) }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    Text(settings.currencyCode).foregroundStyle(.secondary)
                }
            } else if Feature.priceAwareShopping.isAvailable {
                LockedFeatureCard(feature: .priceAwareShopping)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    private var automationSection: some View {
        Section {
            Toggle("Build grocery list from the plan", isOn: $settings.autoBuildGroceryList)
            Toggle("Checked-off items go into stock", isOn: $settings.autoStockOnCheck)
        } header: {
            Text("Automation")
        } footer: {
            Text("Both are on by default so a week takes minutes to plan and nothing needs logging by hand.")
        }
    }

    private var dataSection: some View {
        Section {
            Button("Export everything (JSON)", systemImage: "square.and.arrow.up") { export(.json) }
            Button("Export grocery list (CSV)", systemImage: "tablecells") { export(.groceriesCSV) }
            Button("Export pantry (CSV)", systemImage: "tablecells") { export(.pantryCSV) }
            Button("Import…", systemImage: "square.and.arrow.down") { showingImporter = true }
            Button("Load sample data", systemImage: "wand.and.sparkles") {
                if DemoData.isEmpty(modelContext) {
                    DemoData.load(into: modelContext)
                    settings.didSeedDemoData = true
                    message = "Sample data loaded."
                } else {
                    confirmingReset = true
                }
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Import accepts Mealy JSON, CSV lists, schema.org recipe JSON and Paprika exports (.paprikarecipes). You are never locked in.")
        }
    }

    private var accountSection: some View {
        Section {
            if account.isSignedIn {
                LabeledContent("Signed in with", value: account.email ?? "Apple ID")
                if HouseholdSyncService.shared.canSync {
                    Button(HouseholdSyncService.shared.isSyncing ? "Syncing…" : "Sync household now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { message = await HouseholdSyncService.shared.sync(modelContext: modelContext, settings: settings) }
                    }
                    .disabled(HouseholdSyncService.shared.isSyncing)
                    if let last = HouseholdSyncService.shared.lastSync {
                        LabeledContent("Last sync", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Button("Sign out") { account.signOut() }
                Button(isDeletingAccount ? "Deleting…" : "Delete account", role: .destructive) { confirmingDeleteAccount = true }
                    .disabled(isDeletingAccount)
            } else {
                Button("Sign in with Apple", systemImage: "apple.logo") { showingAccount = true }
            }
            #if DEBUG
            TextField("Server URL", text: Binding(
                get: { UserDefaults.standard.string(forKey: "api.baseURL") ?? "" },
                set: { UserDefaults.standard.set($0.isEmpty ? nil : $0, forKey: "api.baseURL") }
            ), prompt: Text(APIClient.shared.baseURL?.absoluteString ?? "Server URL"))
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
        } header: {
            Text("Account")
        } footer: {
            Text("Plus subscribers are signed in automatically from their purchase. Sign in with Apple only if you're joining someone else's household. Free features never need it.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Button("Privacy Policy", systemImage: "hand.raised") { showingPrivacy = true }
            Link(destination: LegalLinks.termsOfUse) {
                Label("Terms of Use", systemImage: "doc.text")
            }
            LabeledContent("Version", value: Self.versionText)
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: Actions

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            do {
                try await account.deleteAccount()
                message = "Your account was deleted."
            } catch {
                message = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }

    private enum ExportKind { case json, groceriesCSV, pantryCSV }

    private func export(_ kind: ExportKind) {
        let exporter = DataExporter(modelContext: modelContext)
        do {
            switch kind {
            case .json:
                let preferences = ExportBundle.Preferences(region: settings.region.rawValue, unitSystem: settings.unitSystem.rawValue, weeklyBudgetCents: settings.weeklyBudgetCents, dietTags: settings.dietTags)
                exportDocument = TransferDocument(data: try exporter.json(preferences: preferences), contentType: .json, fileName: "mealy-export")
            case .groceriesCSV:
                exportDocument = TransferDocument(data: Data(exporter.groceriesCSV().utf8), contentType: .commaSeparatedText, fileName: "grocery-list")
            case .pantryCSV:
                exportDocument = TransferDocument(data: Data(exporter.pantryCSV().utf8), contentType: .commaSeparatedText, fileName: "pantry")
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let summary = try DataImporter(modelContext: modelContext).importFile(data: data, fileName: url.lastPathComponent)
                message = summary.description
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// A file produced by an export, handed to `fileExporter`.
struct TransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var data: Data
    var contentType: UTType
    var fileName: String

    init(data: Data, contentType: UTType, fileName: String) {
        self.data = data
        self.contentType = contentType
        self.fileName = fileName
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = .json
        fileName = "import"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Household

struct HouseholdView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var households: [Household]
    @State private var newName = ""
    @State private var joinCode = ""
    @State private var message: String?
    @State private var sync = HouseholdSyncService.shared
    @State private var account = AccountSession.shared
    @State private var entitlements = EntitlementService.shared
    @State private var settings = AppSettings.shared
    @State private var showingAccount = false

    @ViewBuilder
    private var sharingSection: some View {
        if !APIClient.isConfigured {
            EmptyView()
        } else if entitlements.hasFeature(.householdSharing) || sync.isMemberOfSharedHousehold {
            Section {
                if !account.isSignedIn {
                    Button("Sign in with Apple to share", systemImage: "apple.logo") { showingAccount = true }
                } else {
                    Button(sync.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { message = await sync.sync(modelContext: modelContext, settings: settings) }
                    }
                    .disabled(sync.isSyncing)
                    if let code = sync.inviteCode {
                        LabeledContent("Invite code", value: code)
                        ShareLink(item: "Join my Mealy household with code \(code)") {
                            Label("Share invite", systemImage: "square.and.arrow.up")
                        }
                    }
                    joinRow
                }
            } header: {
                Text("Sharing")
            } footer: {
                Text("Everyone in the household sees the same plan, list and pantry. Others don't need their own Plus.")
            }
            .task { if account.isSignedIn { await sync.refreshInvite() } }
            .sheet(isPresented: $showingAccount) { AccountView() }
        } else {
            Section {
                LockedFeatureCard(feature: .householdSharing)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                if account.isSignedIn {
                    joinRow
                } else {
                    Button("Sign in with Apple to join", systemImage: "apple.logo") { showingAccount = true }
                }
            } header: {
                Text("Have an invite?")
            } footer: {
                Text("Joining someone's household is free; their Plus covers sharing.")
            }
            .sheet(isPresented: $showingAccount) { AccountView() }
        }
    }

    private var joinRow: some View {
        HStack {
            TextField("Invite code", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Join") {
                Task {
                    do {
                        try await sync.join(code: joinCode)
                        joinCode = ""
                        message = await sync.sync(modelContext: modelContext, settings: settings)
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            .disabled(joinCode.trimmingCharacters(in: .whitespaces).count < 4)
        }
    }

    private var household: Household? { households.first }

    var body: some View {
        Form {
            Section {
                if let household {
                    TextField("Household name", text: Binding(get: { household.name }, set: { household.name = $0; save() }))
                }
            }
            Section {
                ForEach(household?.members.sorted { $0.sortOrder < $1.sortOrder } ?? []) { member in
                    HStack {
                        TextField("Name", text: Binding(get: { member.name }, set: { member.name = $0; save() }))
                        Spacer()
                        Stepper(value: Binding(get: { member.portionMultiplier }, set: { member.portionMultiplier = $0; save() }), in: 0.25...3, step: 0.25) {
                            Text("\(member.portionMultiplier.quantityText)×")
                                .monospacedDigit()
                                .frame(minWidth: 44, alignment: .trailing)
                        }
                    }
                }
                .onDelete { offsets in
                    let members = household?.members.sorted { $0.sortOrder < $1.sortOrder } ?? []
                    offsets.map { members[$0] }.forEach(modelContext.delete)
                    save()
                }
                HStack {
                    TextField("Add a person", text: $newName)
                    Button("Add") { addMember() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("People and portion sizes")
            } footer: {
                Text("1× is a standard serving. Use 0.5× for small children or 1.5× for big appetites. Together: \(household?.servingsPerMeal.quantityText ?? "2") servings per meal.")
            }
            sharingSection
        }
        .navigationTitle("Household")
        .alert("Household", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .task {
            if households.isEmpty {
                modelContext.insert(Household())
                save()
            }
            if account.isSignedIn { await sync.refreshInvite() }
        }
    }

    private func addMember() {
        guard let household else { return }
        let member = HouseholdMember(name: newName.trimmingCharacters(in: .whitespaces), sortOrder: household.members.count)
        member.household = household
        modelContext.insert(member)
        newName = ""
        save()
    }

    private func save() { try? modelContext.save() }
}

// MARK: - Account

/// Sign in with Apple. Subscribers never see this: their purchase signs them in silently.
/// It's for people who share a household without paying for Plus themselves.
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var account = AccountSession.shared
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Use your Apple ID", systemImage: "apple.logo").font(.headline)
                        Text("No new account or password. Your Apple ID connects you to your household so everyone sees the same plan, list and pantry.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    SignInWithAppleButton(.continue) { request in
                        account.prepare(request)
                    } onCompletion: { result in
                        complete(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .disabled(isWorking)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    if isWorking { ProgressView().frame(maxWidth: .infinity) }
                    if let error { Text(error).foregroundStyle(.red).font(.caption) }
                } footer: {
                    Text("If you subscribe to Plus, your purchase signs you in automatically. Your other data stays on this device and in your iCloud.")
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        if case .failure(let failure) = result, (failure as? ASAuthorizationError)?.code == .canceled { return }
        isWorking = true
        error = nil
        Task {
            do {
                try await account.completeSignInWithApple(result)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }
}
